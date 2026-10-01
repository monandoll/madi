import Foundation
import CryptoKit
import CoreGraphics

/// 다이제스트 — AI 가 영상을 "읽는" 유일한 창구 (AGENTS.md §6).
///
/// 프레임을 통째로 넣지 않는다. **팩된 텍스트 + 프레임 시트 최대 2장.**
/// ```
/// TRANSCRIPT  낱말(WhisperKit) → 문장으로 묶어 표기
/// SUBJECT     사람 분할 마스크 0.5초 간격 (1단계와 같은 트랙) + 요약
/// AUDIO       무음 구간
/// SCENES      프레임 차분 컷
/// FRAMES      시작 · 컷 직후 프레임을 2×2 격자로, 최대 2장
/// ```
/// ★ 동작을 추측하지 않는다 — "이때 스트레칭 중" 같은 말은 적지 않는다. 자세 이름도 붙이지 않는다.
///   분류기가 없는데 이름을 붙이면 그게 추측이다. AI 는 SUBJECT 숫자와 FRAMES 를 보고 판단한다.
public enum DigestBuilder {

    /// 형식 버전. 텍스트 형식이 바뀌면 올린다 — 옛 버전 다이제스트는 다시 만든다.
    public static let version = 4   // 2: 말이 아닌 전사를 걷는다 · 3: 사람 위치 줄을 구간으로 묶는다 · 4: 영상 끝에서 잘린 말 표시

    public struct Digest: Sendable {
        public var text: String
        public var sheetPaths: [String]
        public var transcript: Transcript
        public var subject: SubjectTrack
        public var audio: AudioAnalyzer.Result
        public var scenes: SceneCutDetector.Result
        /// 부분별 걸린 초. 3단계 3분 판정과 `events` 가 쓴다.
        public var timings: [String: Double]
    }

    /// - Parameter workDir: 프레임 시트를 남기는 곳 (다이제스트가 가리킨다 — 지우면 안 된다).
    ///   사람 추적용 전체 해상도 프레임은 임시 폴더에서 쓰고 지운다 (1분 영상이면 수백 MB).
    /// 분석 단계 — 화면의 "말 받아적기 · 사람 찾기" 줄과 같다. 소리 · 컷 · 그림은 짧아서 `.rest` 하나로 둔다.
    public enum Step: Int, Sendable { case transcribe = 0, findPerson = 1, rest = 2 }

    public static func build(
        videoID: String, url: URL, transcriber: any TranscriptionProvider, workDir: URL,
        progress: (@Sendable (Step, Double) -> Void)? = nil
    ) async throws -> Digest {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "madi-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let info = try await FrameSheet.info(of: url)

        var timings: [String: Double] = [:]
        var clock = Date()
        func lap(_ name: String) { timings[name] = Date().timeIntervalSince(clock); clock = Date() }

        // 맥에 여유가 있으면(`LoadGovernor` full) 셋을 **동시에** 돌린다 — 받아적기(음성 칩) · 소리 분석(CPU) ·
        // 영상 한 번 읽기(해독기 + 사람 분할). 뜨겁거나 · 메모리 8GB 이하 · 저전력이면 하나씩 — 한꺼번에 몰리면
        // macOS 가 강제로 확 느리게 만든다(스로틀링). 1분 영상 52초 중 49초이던 사람 · 컷을 한 번 읽기로 줄였다.
        progress?(.transcribe, 0)
        progress?(.findPerson, 0)
        let stepSec = 0.5
        let end = info.duration - 0.05
        let subjectTimes = stride(from: 0.0, to: max(end, stepSec), by: stepSec).map { $0 }
        @Sendable func transcribe() async throws -> Transcript {
            try await transcriber.transcribe(url, languageCode: "ko", progress: { progress?(.transcribe, $0) })
        }
        func scanVideo() async throws -> (SubjectTrack, SceneCutDetector.Result) {
            var follower = SubjectFollower()
            let scan = try await VideoScan.run(
                url: url, subjectTimes: subjectTimes, cutFPS: SceneCutDetector.sampleFPS,
                onSubject: { t, image in
                    follower.add(t: t, parts: try SubjectDetector.maskComponents(image, minCoverage: SubjectTrackBuilder.defaultMinCoverage))
                },
                progress: { progress?(.findPerson, 0.95 * $0) }
            )
            let track = SubjectTrack(
                source: SourceInfo(videoID: videoID, width: Int(info.size.width.rounded()), height: Int(info.size.height.rounded()),
                                   durationSec: info.duration, fps: Double(info.fps)),
                stepSec: stepSec, samples: follower.samples
            )
            return (track, SceneCutDetector.result(thumbs: scan.thumbs, stepSec: scan.cutStep))
        }

        let rawTranscript: Transcript
        let audio: AudioAnalyzer.Result
        let subject: SubjectTrack
        let scenes: SceneCutDetector.Result
        let parallel = LoadGovernor.shared.level == .full
        timings["parallel"] = parallel ? 1 : 0
        if parallel {
            async let transcribed = transcribe()
            async let audioResult = AudioAnalyzer.analyze(url)
            (subject, scenes) = try await scanVideo()
            lap("scan")
            audio = try await audioResult
            rawTranscript = try await transcribed
            lap("transcriptWait")
        } else {
            rawTranscript = try await transcribe()
            lap("transcript")
            audio = try await AudioAnalyzer.analyze(url)
            lap("audio")
            (subject, scenes) = try await scanVideo()
            lap("scan")
        }
        // 말이 아닌 것(괄호로 싼 소리 설명 · 영상 길이를 넘는 낱말)은 여기서 걷는다 — 두 전사 엔진이 다 지나는 한 곳.
        let transcript = rawTranscript.droppingNonSpeech(duration: info.duration)
        progress?(.transcribe, 1)

        // 시작 + 컷 직후(0.3초 뒤 — 전환 효과를 피한다). 1초 안에 몰린 건 하나로. 최대 8장.
        var times = [0.0]
        for c in scenes.cuts where c + 0.3 < info.duration && c + 0.3 - times.last! >= 1 { times.append(c + 0.3) }
        if times.count > 8 { times = stride(from: 0, to: 8, by: 1).map { times[$0 * times.count / 8] } }
        let frames = try await FrameSheet.extract(from: url, at: times, into: scratch.appending(path: "frames"), prefix: "")
        var sheetPaths: [String] = []
        var sheetTimes: [[Double]] = []
        for (n, start) in stride(from: 0, to: frames.count, by: 4).enumerated() {
            let chunk = Array(frames[start..<min(start + 4, frames.count)])
            let images = try chunk.map { try StillRenderer.loadImage($0) }
            let out = workDir.appending(path: "sheet_\(n).png")
            try FrameSheet.gridOf(images, columns: 2, cellWidth: 360, to: out)
            sheetPaths.append(out.path)
            sheetTimes.append(Array(times[start..<min(start + 4, times.count)]))
        }

        lap("frames")
        let text = render(
            videoID: videoID, info: info, transcript: transcript, subject: subject,
            audio: audio, scenes: scenes,
            sheets: zip(sheetPaths, sheetTimes).map { ($0.0, $0.1) }
        )
        return Digest(text: text, sheetPaths: sheetPaths, transcript: transcript,
                      subject: subject, audio: audio, scenes: scenes, timings: timings)
    }

    /// 원본이 같은지 가르는 값. 크기 · 수정 시각 · 앞 256KB 해시.
    /// 같으면 다이제스트를 다시 만들지 않는다 (§6 캐시).
    public static func fingerprint(of url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 256 * 1024) ?? Data()
        let hash = SHA256.hash(data: head).map { String(format: "%02x", $0) }.joined()
        return "\(size)-\(Int(modified))-\(hash.prefix(16))"
    }

    // MARK: - 텍스트

    /// 사람 위치 줄. 0.5초 표본을 **비슷하면 한 줄로 묶는다** — 위치 · 크기(x y w h)가 모두 구간 첫 표본에서
    /// `tolerance` 안이면 같은 구간이다. 전에는 표본마다 한 줄이라 31분 영상에서 이 칸만 3,732줄(다이제스트의 93%)이었다
    /// — AI 턴이 느려지고 구독을 많이 먹는다. 자세가 바뀌면(서기 ↔ 바닥, 높이 0.3 넘게) 구간이 끊겨 그대로 보인다.
    /// 화면 잡기(리프레임)는 이 글이 아니라 표본(`SubjectTrack`)을 쓴다 — 여기서 줄여도 영향 없다.
    static func subjectLines(_ samples: [SubjectSample], tolerance: Double = 0.03) -> [String] {
        func t3(_ t: Double) -> String { String(format: "%05.1f", t) }
        var out: [String] = []
        var i = 0
        while i < samples.count {
            let first = samples[i]
            var j = i + 1
            while j < samples.count {
                let next = samples[j]
                switch (first.box, next.box) {
                case (nil, nil): j += 1; continue
                case let (a?, b?) where abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
                                    && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance:
                    j += 1; continue
                default: break
                }
                break
            }
            let run = samples[i..<j]
            let time = run.count == 1 ? t3(first.t) : "\(t3(first.t))-\(t3(run.last!.t))"
            let boxes = run.compactMap(\.box)
            if boxes.isEmpty {
                out.append("\(time)  -")
            } else {
                let n = Double(boxes.count)
                out.append(String(format: "%@  %.2f %.2f %.2f %.2f", time,
                                  boxes.map(\.x).reduce(0, +) / n, boxes.map(\.y).reduce(0, +) / n,
                                  boxes.map(\.w).reduce(0, +) / n, boxes.map(\.h).reduce(0, +) / n))
            }
            i = j
        }
        return out
    }

    static func render(
        videoID: String, info: FrameSheet.Info, transcript: Transcript, subject: SubjectTrack,
        audio: AudioAnalyzer.Result, scenes: SceneCutDetector.Result, sheets: [(String, [Double])]
    ) -> String {
        func t3(_ t: Double) -> String { String(format: "%05.1f", t) }
        func t2(_ t: Double) -> String { String(format: "%06.2f", t) }
        var out: [String] = []
        out.append(String(format: "# VIDEO %@   duration %.1fs   %dx%d   %.0ffps",
                          videoID, info.duration, Int(info.size.width), Int(info.size.height), info.fps))

        out.append("\n## TRANSCRIPT")
        let sentences = self.sentences(transcript.words)
        if sentences.isEmpty { out.append("(말 없음)") }
        // 영상이 말 도중에 끝났으면 마지막 문장에 표시한다 — 그 문장으로 장면을 끝내면 숨 없이 뚝 끊긴다 (`write_composition` 이 거절한다)
        let clipped = transcript.clippedAtEnd(duration: info.duration) != nil
        for (i, s) in sentences.enumerated() {
            out.append("[\(t2(s.start))-\(t2(s.end))] \(s.text)" + (clipped && i == sentences.count - 1 ? "  \(clippedMark)" : ""))
        }

        out.append("\n## SUBJECT  (0.5s 표본 · 비슷하면 `시작-끝` 한 줄로 묶음, 정규화 x y w h — y 는 아래에서, 사람 분할 마스크)")
        out.append(contentsOf: subjectLines(subject.samples))
        let found = subject.samples.compactMap(\.box)
        if found.isEmpty {
            out.append("(요약) 사람을 찾지 못했다")
        } else {
            let heights = found.map(\.h).sorted()
            let centers = found.map { $0.x + $0.w / 2 }
            out.append(String(format: "(요약) 사람 높이 중앙 %.2f · 좌우 이동 %.2f · 못 찾은 표본 %.0f%%",
                              heights[heights.count / 2],
                              (centers.max() ?? 0) - (centers.min() ?? 0),
                              subject.missingRatio * 100))
        }

        out.append("\n## AUDIO")
        if audio.noAudioTrack {
            out.append("(오디오 트랙 없음)")
        } else if audio.silences.isEmpty {
            out.append("(무음 구간 없음)")
        } else {
            for r in audio.silences {
                out.append(String(format: "silence %@-%@ (%.1fs)", t3(r.lowerBound), t3(r.upperBound), r.upperBound - r.lowerBound))
            }
        }

        out.append("\n## SCENES")
        out.append(scenes.cuts.isEmpty ? "(컷 없음)" : scenes.cuts.map { "cut \(t3($0))" }.joined(separator: "  "))

        out.append("\n## FRAMES")
        for (path, times) in sheets {
            let label = times.map { String(format: "%03.0fs", $0) }.joined(separator: " / ")
            out.append("\(URL(fileURLWithPath: path).lastPathComponent)   (\(label))")
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// 낱말을 문장으로 묶는다. **표기용**이다 — 자막 분절(`CaptionSplitter`)과 다르다.
    /// 끝 문장부호에서, 또는 0.5초 넘게 쉬면 끊는다.
    /// TRANSCRIPT 마지막 줄에 붙는 표시. 제작 지침(playbook)이 이 글자를 가리킨다.
    public static let clippedMark = "(영상 끝에서 말이 잘림)"

    static func sentences(_ words: [Word]) -> [(start: Double, end: Double, text: String)] {
        var out: [(Double, Double, String)] = []
        var cur: [Word] = []
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            out.append((f.start, l.end, cur.map(\.text).joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)))
            cur = []
        }
        for w in words {
            if let last = cur.last, w.start - last.end > 0.5 { flush() }
            cur.append(w)
            if let c = w.text.trimmingCharacters(in: .whitespaces).last, ".?!。".contains(c) { flush() }
        }
        flush()
        return out
    }
}
