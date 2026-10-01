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
    /// - 괄호(`[]` · `()`)로 열고 닫는 구간은 낱말 여러 개에 걸쳐도 통째로 뺀다 — 단 `bracketWords` 낱말 안에서 닫힐 때만.
    ///   끝내 안 닫히면 여는 낱말만 뺀다. 전에는 닫는 괄호를 끝까지 기다려 **그 뒤 전사를 전부** 버릴 수 있었다
    ///   (22분 영상 실측: "(댓글 읽음)" 은 바로 닫혔지만, 닫는 낱말이 안 나오면 29초 뒤가 통째로 빈다)
    /// - `♪` · `*` 가 든 낱말을 뺀다
    /// - 시작이 영상 길이 이후인 낱말을 뺀다
    public func droppingNonSpeech(duration: Double, bracketWords: Int = 8) -> Transcript {
        var kept: [Word] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let t = w.text.trimmingCharacters(in: .whitespaces)
            i += 1
            if let first = t.first, first == "[" || first == "(" {
                let c: Character = first == "[" ? "]" : ")"
                if !t.dropFirst().contains(c),
                   let close = words[i..<min(i + bracketWords, words.count)].firstIndex(where: { $0.text.contains(c) }) {
                    i = close + 1
                }
                continue
            }
            if t.contains("♪") || t.contains("*") { continue }
            if w.start >= duration { continue }
            var clamped = w
            clamped.end = min(w.end, duration)   // 마지막 낱말 끝이 영상보다 길게 나온다 (60.00초 영상에 60.08)
            kept.append(clamped)
        }
        return Transcript(videoID: videoID, words: kept)
    }

    /// 영상이 말 도중에 끝났으면 그 마지막 낱말. 마지막 낱말 끝 뒤로 **숨 쉴 틈**(`breath` — 말 끝 뒤 0.15초, 크리에이터 완성본 실측)도
    /// 안 남았으면 말이 파일 끝에서 잘린 것으로 본다. 그 말로 장면을 끝내면 숨 없이 뚝 끊긴다 — 앱은 파일 밖으로 여유를 붙일 수 없다.
    /// 실측 (2026-10-02, `docs/findings/2026-10-01-practical-readiness.md` 1-4): 긴 영상의 앞 60초를 자른 대용 2편은 마지막 낱말이
    /// 파일 끝에 닿거나 넘었다 (남은 틈 0.00 · −0.08초 — 전사가 낱말을 파일 끝까지 늘리고 마침표도 붙인다). 끝인사로 끝난 30분 영상은 1.93초.
    public func clippedAtEnd(duration: Double, breath: Double = 0.15) -> Word? {
        guard let last = words.last, duration - last.end < breath else { return nil }
        return last
    }

    public func words(in range: ClosedRange<Double>) -> [Word] {
        words.filter { $0.start >= range.lowerBound - 1e-9 && $0.start <= range.upperBound + 1e-9 }
    }
}
