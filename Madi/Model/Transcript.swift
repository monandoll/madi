import Foundation

/// 전사 한 낱말. **word 단위 타임스탬프가 필수다** (`AGENTS.md §3`, `§6`).
///
/// 문장 단위로만 있으면 자막을 끊을 수가 없고, 끊더라도 G6(싱크 0.15초)를 맞출 수 없다.
public struct Word: Codable, Hashable, Sendable {
    public var text: String
    /// 원본 초.
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text; self.start = start; self.end = end
    }
}

/// 한 원본의 전사.
public struct Transcript: Codable, Hashable, Sendable {
    public var videoID: String
    public var words: [Word]

    public init(videoID: String, words: [Word]) {
        self.videoID = videoID; self.words = words
    }

    /// 말이 아닌 것을 걷어 낸다. Whisper 는 음악 · 소음만 있는 구간에 말을 **지어낸다** —
    /// `[두 번째 도전!]` · `(음악)` · `♪` 처럼 괄호로 싼 소리 설명이 오고, 시각이 영상 길이를 넘기도 한다
    /// (헬스장 촬영본 실측: 47초 영상에 `[035.88-059.32] [두 번째 주인공]`). 그게 자막 · 제목으로 들어가면 안 된다.
    /// - 괄호(`[]` · `()`)로 열고 닫는 구간은 낱말 여러 개에 걸쳐도 통째로 뺀다
    /// - `♪` · `*` 가 든 낱말을 뺀다
    /// - 시작이 영상 길이 이후인 낱말을 뺀다
    public func droppingNonSpeech(duration: Double) -> Transcript {
        var kept: [Word] = []
        var closer: Character?
        for w in words {
            let t = w.text.trimmingCharacters(in: .whitespaces)
            if let c = closer {
                if t.contains(c) { closer = nil }
                continue
            }
            if let first = t.first, first == "[" || first == "(" {
                let c: Character = first == "[" ? "]" : ")"
                if !t.dropFirst().contains(c) { closer = c }
                continue
            }
            if t.contains("♪") || t.contains("*") { continue }
            if w.start >= duration { continue }
            var w = w
            w.end = min(w.end, duration)   // 마지막 낱말 끝이 영상보다 길게 나온다 (60.00초 영상에 60.08)
            kept.append(w)
        }
        return Transcript(videoID: videoID, words: kept)
    }

    public func words(in range: ClosedRange<Double>) -> [Word] {
        words.filter { $0.start >= range.lowerBound - 1e-9 && $0.start <= range.upperBound + 1e-9 }
    }
}
