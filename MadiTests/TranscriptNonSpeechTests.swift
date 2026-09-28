import Testing
@testable import MadiKit

/// Whisper 가 음악 · 소음 구간에 지어낸 말을 걷는다 (헬스장 촬영본 실측 — `Transcript.droppingNonSpeech`).
struct TranscriptNonSpeechTests {

    private func t(_ words: [(String, Double)]) -> Transcript {
        Transcript(videoID: "v", words: words.map { Word(text: $0.0, start: $0.1, end: $0.1 + 0.3) })
    }

    @Test("괄호로 싼 소리 설명은 낱말 여러 개에 걸쳐도 통째로 빠진다")
    func dropsBracketedSpans() {
        let got = t([("[두", 5.2), ("번째", 5.6), ("도전!]", 6.0), ("오늘은", 8.0), ("(음악)", 9.0), ("스쿼트", 10.0)])
            .droppingNonSpeech(duration: 47.3)
        #expect(got.words.map(\.text) == ["오늘은", "스쿼트"])
    }

    @Test("♪ · * 낱말과 영상 길이 뒤의 낱말은 빠진다")
    func dropsMusicAndPastEnd() {
        let got = t([("♪", 1), ("안녕하세요", 2), ("*박수*", 3), ("끝", 46), ("유령", 50)])
            .droppingNonSpeech(duration: 47.3)
        #expect(got.words.map(\.text) == ["안녕하세요", "끝"])
    }

    @Test("보통 말은 그대로다")
    func keepsSpeech() {
        let words = [("골반이", 0.0), ("틀어지신", 0.4), ("분들은", 0.9)]
        #expect(t(words).droppingNonSpeech(duration: 10).words.map(\.text) == words.map(\.0))
    }
}
