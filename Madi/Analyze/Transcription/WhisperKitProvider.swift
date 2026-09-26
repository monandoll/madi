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
    private let lock = NSLock()
    private var pipe: WhisperKit?

    /// - Parameter model: `tiny` · `base` · `small` · `medium` · `large-v3`.
    ///
    /// 기본이 `small` 인 이유: `base` 는 한국어를 자주 틀린다 —
    /// "사람들은"→"그럼 들은", "서른 번씩"→"서로머시에". 그 오독이 분절을 망가뜨려
    /// 쌤 경계와 **4/13** 밖에 안 맞았고, `small` 로 올리니 **9/13** 이 됐다.
    /// 속도 차이는 데운 뒤 2.5초 vs 3.6초로 거의 없다
    /// (`docs/findings/2026-09-26-caption-splitter.md §2`).
    public init(model: String = "small") {
        self.modelName = model
    }

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
            let made = try await WhisperKit(WhisperKitConfig(model: modelName))
            store(made)
            return made
        } catch {
            throw TranscriptionFailure.modelUnavailable(error.localizedDescription)
        }
    }

    public func transcribe(_ url: URL, languageCode: String) async throws -> Transcript {
        let pipe = try await pipeline()
        let options = DecodingOptions(
            language: languageCode,
            // ★ 이게 켜져 있지 않으면 낱말 시각이 안 나온다. 켜는 걸 잊으면
            //   문장 단위만 오고 분절도 G6 도 불가능해진다.
            wordTimestamps: true
        )
        let results = try await pipe.transcribe(
            audioPath: url.path(percentEncoded: false), decodeOptions: options
        )

        var words: [Word] = []
        for result in results {
            for segment in result.segments {
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
        guard !words.isEmpty else { throw TranscriptionFailure.noWordTimestamps }

        let id = url.deletingPathExtension().lastPathComponent
        Self.log.info("전사 \(id, privacy: .public): 낱말 \(words.count)개")
        return Transcript(videoID: id, words: words.sorted { $0.start < $1.start })
    }
}
