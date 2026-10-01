import Foundation
import WhisperKit
import os

/// Apple Silicon 전사. CoreML 로 ANE 를 쓴다 (`AGENTS.md §17` Tier 1).
///
/// ⚠ **모델 가중치를 처음 한 번 내려받는다.** `AGENTS.md §2` 는
///   "Apple Silicon 에서는 외부 바이너리를 받지 않는다 — 첫 실행 준비 화면도 필요 없다"
///   고 적고 있는데, 가중치는 바이너리가 아니지만 **첫 실행 다운로드인 것은 같다.**
///   번들에 넣을지(용량) 받을지(첫 실행 대기)는 사람이 정할 문제다
///   (`docs/findings/2026-09-26-whisperkit.md §1`).
/// `WhisperKit` 자체가 `Sendable` 이 아니라 actor 로 감쌀 수 없다 —
/// actor 안에 두면 `await` 마다 인스턴스가 격리 경계를 넘어 컴파일이 막힌다.
/// **동시성은 큐가 막는다** (`AGENTS.md §2`: 분석 1 동시). 그 전제 위에서 `@unchecked` 다.
public final class WhisperKitProvider: TranscriptionProvider, @unchecked Sendable {

    private static let log = Logger(subsystem: "app.madi", category: "transcribe")

    private let modelName: String
    private let modelFolder: URL?
    private let tokenizerFolder: URL?
    private let lock = NSLock()
    private var pipe: WhisperKit?

    /// - Parameter model: `tiny` · `base` · `small` · `medium` · `large-v3`.
    ///
    /// 기본이 `small` 인 이유: `base` 는 한국어를 자주 틀린다 —
    /// "사람들은"→"그럼 들은", "서른 번씩"→"서로머시에". 그 오독이 분절을 망가뜨려
    /// 쌤 경계와 **4/13** 밖에 안 맞았고, `small` 로 올리니 **9/13** 이 됐다.
    /// 속도 차이는 데운 뒤 2.5초 vs 3.6초로 거의 없다
    /// (`docs/findings/2026-09-26-caption-splitter.md §2`).
    /// - Parameters:
    ///   - modelFolder · tokenizerFolder: 앱이 받아 둔 폴더 (`ModelPreparer`). 주면 **WhisperKit 이 아무것도 받지 않는다** —
    ///     안 주면 WhisperKit 이 `~/Documents/huggingface/` 에 받는다 (측정 도구에서만 쓴다).
    public init(model: String = "small", modelFolder: URL? = nil, tokenizerFolder: URL? = nil) {
        self.modelName = model
        self.modelFolder = modelFolder
        self.tokenizerFolder = tokenizerFolder
    }

    /// 모델을 올리고 한 번 데운다. 처음(새 빌드마다 한 번)은 CoreML 컴파일로 ~50초 걸린다.
    public func warmUp() async throws { _ = try await pipeline() }

    private func cached() -> WhisperKit? {
        lock.lock(); defer { lock.unlock() }
        return pipe
    }

    private func store(_ made: WhisperKit) {
        lock.lock(); defer { lock.unlock() }
        pipe = made
    }

    private func pipeline() async throws -> WhisperKit {
        if let made = cached() { return made }
        do {
            let config = modelFolder.map {
                WhisperKitConfig(model: modelName, modelFolder: $0.path, tokenizerFolder: tokenizerFolder,
                                 prewarm: true, load: true, download: false)
            } ?? WhisperKitConfig(model: modelName)
            let made = try await WhisperKit(config)
            store(made)
            return made
        } catch {
            throw TranscriptionFailure.modelUnavailable(error.localizedDescription)
        }
    }

    public func transcribe(_ url: URL, languageCode: String) async throws -> Transcript {
        try await transcribe(url, languageCode: languageCode, progress: nil)
    }

    public func transcribe(_ url: URL, languageCode: String,
                           progress report: (@Sendable (Double) -> Void)?) async throws -> Transcript {
        // 소리는 **우리가 읽어서** 넘긴다 (AVAssetReader → 16kHz 모노, whisper.cpp 와 같은 길).
        // WhisperKit 의 파일 읽기(AVAudioFile)는 22분 48초 유튜브 mp4 의 소리를 **393.7초**로 읽었다 — 소리 트랙은 1367.6초인데.
        // 그래서 6분 33초 뒤의 말이 전부 빠졌고, AI 가 "전사가 6분 33초까지만 있다" 고 답했다 (2026-10-01 실제 앱).
        let samples = try await AudioAnalyzer.mono16k(url)
        let words = try await transcribe(samples: samples, languageCode: languageCode, progress: report)
        let id = url.deletingPathExtension().lastPathComponent
        Self.log.info("전사 \(id, privacy: .public): 낱말 \(words.count)개")
        return Transcript(videoID: id, words: words)
    }

    public func transcribe(samples: [Float], languageCode: String) async throws -> [Word]? {
        try await transcribe(samples: samples, languageCode: languageCode, progress: nil)
    }

    private func transcribe(samples: [Float], languageCode: String,
                            progress report: (@Sendable (Double) -> Void)?) async throws -> [Word] {
        guard !samples.isEmpty else { return [] }
        let pipe = try await pipeline()
        // 진행률 — WhisperKit 의 `progress`(창마다 자식, 창 안에서는 찾아 들어간 만큼)를 0.5초마다 읽는다.
        // `Progress` 는 스레드 안전하다. 끝나면 WhisperKit 이 새것으로 바꾸므로 시작 전에 잡아 둔다.
        nonisolated(unsafe) let watched = pipe.progress
        let poller = report.map { report in
            Task {
                while !Task.isCancelled {
                    report(min(max(watched.fractionCompleted, 0), 1))
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        defer { poller?.cancel() }
        let options = DecodingOptions(
            language: languageCode,
            // ★ 이게 켜져 있지 않으면 낱말 시각이 안 나온다. 켜는 걸 잊으면
            //   문장 단위만 오고 분절도 G6 도 불가능해진다.
            wordTimestamps: true
        )
        let results: [TranscriptionResult] = try await pipe.transcribe(audioArray: samples, decodeOptions: options)

        var words: [Word] = []
        var segments = 0
        for result in results {
            for segment in result.segments {
                segments += 1
                guard let timings = segment.words else { continue }
                for w in timings {
                    let text = w.word.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    words.append(Word(
                        text: text, start: Double(w.start), end: Double(w.end)
                    ))
                }
            }
        }
        // 말이 있었는데(구간이 있는데) 낱말 시각이 없으면 wordTimestamps 가 안 켜진 것이다.
        // 말이 아예 없는 영상(음악 · 효과음만)은 빈 전사가 맞다 — 분석을 실패시키지 않는다.
        guard segments == 0 || !words.isEmpty else { throw TranscriptionFailure.noWordTimestamps }
        return words.sorted { $0.start < $1.start }
    }
}
