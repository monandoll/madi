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
    public static let version = 1

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
    public static func build(
        videoID: String, url: URL, transcriber: any TranscriptionProvider, workDir: URL
    ) async throws -> Digest {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "madi-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let info = try await FrameSheet.info(of: url)

        var timings: [String: Double] = [:]
        var clock = Date()
        func lap(_ name: String) { timings[name] = Date().timeIntervalSince(clock); clock = Date() }

        let transcript = try await transcriber.transcribe(url)
        lap("transcript")
        let subject = try await SubjectTrackBuilder.build(
            videoID: videoID, url: url, workDir: scratch.appending(path: "subject")
        )
        lap("subject")
        let audio = try await AudioAnalyzer.analyze(url)
        lap("audio")
        let scenes = try await SceneCutDetector.detect(url)
        lap("scenes")

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
        for s in sentences { out.append("[\(t2(s.start))-\(t2(s.end))] \(s.text)") }

        out.append("\n## SUBJECT  (0.5s, 정규화 x y w h — y 는 아래에서, 사람 분할 마스크)")
        for s in subject.samples {
            if let b = s.box {
                out.append(String(format: "%@  %.2f %.2f %.2f %.2f", t3(s.t), b.x, b.y, b.w, b.h))
            } else {
                out.append("\(t3(s.t))  -")
            }
        }
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
