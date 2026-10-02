import Testing
import Foundation
@testable import MadiKit

/// 받아 적기가 영상 끝까지 갔는지 앱이 스스로 확인한다 (`TranscriptCoverage` — 2026-10-02, 22분 영상 전사 잘림 뒤).
struct TranscriptCoverageTests {

    /// 소리 조각을 받으면 정해 둔 낱말을 (조각 시작 기준 시각으로) 돌려주는 가짜 엔진. 받은 조각 길이를 적는다.
    final class Fake: TranscriptionProvider, @unchecked Sendable {
        var replies: [[Word]]
        var asked: [Int] = []
        init(_ replies: [[Word]]) { self.replies = replies }
        func transcribe(_ url: URL, languageCode: String) async throws -> Transcript { Transcript(videoID: "v", words: []) }
        func transcribe(samples: [Float], languageCode: String) async throws -> [Word]? {
            asked.append(samples.count)
            return replies.isEmpty ? [] : replies.removeFirst()
        }
    }

    /// 0.05초 창 RMS — `loud` 구간만 소리, 나머지 무음.
    func audio(duration: Double, loud: ClosedRange<Double>) -> AudioAnalyzer.Result {
        let n = Int(duration / AudioAnalyzer.windowSec)
        let rms = (0..<n).map { i -> Double in loud.contains(Double(i) * AudioAnalyzer.windowSec) ? -20 : -80 }
        return AudioAnalyzer.Result(windowSec: AudioAnalyzer.windowSec, rmsDB: rms, silences: [], noAudioTrack: false)
    }

    let head = Transcript(videoID: "v", words: [Word(text: "오늘은", start: 1, end: 1.5), Word(text: "스트레칭.", start: 1.5, end: 2.0)])

    @Test("마지막 낱말 뒤에 소리가 한참 남으면 남은 부분만 이어 받아 적는다 — 시각은 영상 기준으로 옮긴다")
    func continuesTail() async throws {
        let fake = Fake([[Word(text: "이어서", start: 0.6, end: 1.0), Word(text: "설명.", start: 1.0, end: 1.5)]])
        let r = try await TranscriptCoverage.complete(
            head, duration: 200, audio: audio(duration: 200, loud: 0...200), provider: fake,
            samples: { [Float](repeating: 0, count: 200 * 16_000) })
        #expect(r.rounds == 2 && r.added == 2)              // 두 번째에는 새 말이 없어 멈춘다
        #expect(r.transcript.words.map(\.text) == ["오늘은", "스트레칭.", "이어서", "설명."])
        #expect(abs(r.transcript.words[2].start - 2.1) < 1e-9)        // 1.5초(= 2.0 − 0.5) 부터 받은 조각의 0.6초
        #expect(fake.asked.first == (200 * 16_000) - Int(1.5 * 16_000))
    }

    @Test("끝까지 받아 적었으면 아무것도 안 한다 — 마지막 낱말 뒤가 조용하거나 짧다")
    func leavesCompleteTranscript() async throws {
        let fake = Fake([])
        let quiet = try await TranscriptCoverage.complete(
            head, duration: 200, audio: audio(duration: 200, loud: 0...2), provider: fake, samples: { [] })
        let shortTail = try await TranscriptCoverage.complete(
            head, duration: 200, audio: audio(duration: 200, loud: 0...(2 + TranscriptCoverage.tailSoundSec - 1)), provider: fake, samples: { [] })
        #expect(quiet.rounds == 0 && shortTail.rounds == 0 && fake.asked.isEmpty)
        #expect(quiet.transcript == head)
    }

    @Test("이어 받아 적어도 새 말이 없으면 멈춘다 — 음악만 이어지는 끝")
    func stopsWhenNothingNew() async throws {
        let fake = Fake([[]])
        let r = try await TranscriptCoverage.complete(
            head, duration: 200, audio: audio(duration: 200, loud: 0...200), provider: fake,
            samples: { [Float](repeating: 0, count: 200 * 16_000) })
        #expect(r.rounds == 1 && r.added == 0 && fake.asked.count == 1)
        #expect(r.transcript == head)
    }

    @Test("조각을 못 받는 엔진이면 그대로 둔다")
    func engineWithoutSamples() async throws {
        struct Plain: TranscriptionProvider {
            func transcribe(_ url: URL, languageCode: String) async throws -> Transcript { Transcript(videoID: "v", words: []) }
        }
        let r = try await TranscriptCoverage.complete(
            head, duration: 200, audio: audio(duration: 200, loud: 0...200), provider: Plain(),
            samples: { [Float](repeating: 0, count: 200 * 16_000) })
        #expect(r.rounds == 0 && r.transcript == head)
    }
}
