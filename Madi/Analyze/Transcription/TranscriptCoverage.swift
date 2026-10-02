import Foundation
import os

/// 받아 적기가 영상 끝까지 갔는가 — **앱이 스스로 확인한다** (2026-10-02 사용자 결정: 다시 받아 적기 버튼을 두지 않는다).
///
/// 22분 48초 영상의 전사가 6분 33초에서 끝나 있었다 (WhisperKit 이 소리를 짧게 읽었다 — `8ac4dfe` 에서 고침).
/// 크리에이터는 "전사" 를 모르고, 언제 다시 하라고 누를지도 모른다. 그래서 분석 끝에 앱이 잰다:
/// 마지막 낱말 뒤에 소리가 `tailSoundSec` 넘게 남아 있으면 **남은 부분만** 이어 받아 적는다 (최대 `maxRounds` 번).
/// 같은 소리를 처음부터 다시 받아 적으면 결과가 같다 (같은 모델 · 같은 입력) — 이어 받아 적어야 엔진이 일찍 멈춘 경우를 건진다.
public enum TranscriptCoverage {

    private static let log = Logger(subsystem: "app.madi", category: "transcribe")

    /// 마지막 낱말 뒤에 소리(무음 기준 위)가 이만큼 넘게 남으면 이어 받아 적는다 (초).
    /// 실측 (2026-10-02, `madi-spike coverage` 44편): 크리에이터 공개본 33편은 대부분 0~0.7초, 가장 긴 것 17.2초
    /// (`59HP` — 말이 4초에 끝나고 음악이 이어진다). 시험 영상 11개 최대 5.2초. 잘렸던 22분 영상은 975초.
    /// → 30초면 정상 44편 중 0편이 걸리고 잘림은 잡는다.
    /// ★ 말 **사이**의 빈 곳은 보지 않는다 — 소리는 있는데 말이 없는 구간이 30분 영상에 44.9초(말 없는 시범)였다.
    ///   음악 구간을 따로 받아 적으면 없는 말을 지어내 자막에 들어갈 수 있다
    public static let tailSoundSec = 30.0
    static let maxRounds = 3

    public struct Result: Sendable {
        public var transcript: Transcript
        /// 이어 받아 적은 횟수 (0 = 처음 것이 끝까지 갔다).
        public var rounds: Int
        public var added: Int
    }

    /// `from` ~ `to` 사이에 소리(무음 기준 `AudioAnalyzer.silenceDB` 위)가 있는 초.
    public static func soundSeconds(_ audio: AudioAnalyzer.Result, from: Double, to: Double) -> Double {
        let w = audio.windowSec
        let lo = max(0, Int(from / w)), hi = min(audio.rmsDB.count, Int(to / w))
        guard lo < hi else { return 0 }
        return Double(audio.rmsDB[lo..<hi].filter { $0 >= AudioAnalyzer.silenceDB }.count) * w
    }

    /// - Parameters:
    ///   - transcript: 말 아닌 것을 걷어 낸 전사 (`droppingNonSpeech`)
    ///   - samples: 16kHz 모노 소리 — 이어 받아 적을 때만 읽는다
    public static func complete(
        _ transcript: Transcript, duration: Double, audio: AudioAnalyzer.Result,
        provider: any TranscriptionProvider, languageCode: String = "ko",
        samples: () async throws -> [Float]
    ) async throws -> Result {
        var words = transcript.words
        var loaded: [Float]?
        var rounds = 0, added = 0
        while rounds < maxRounds {
            let last = words.last?.end ?? 0
            guard soundSeconds(audio, from: last, to: duration) > tailSoundSec else { break }
            if loaded == nil { loaded = try await samples() }
            guard let all = loaded else { break }
            let from = max(0, last - 0.5)          // 걸친 낱말을 다시 듣게 조금 앞에서
            let lo = Int(from * 16_000)
            guard lo < all.count,
                  let got = try await provider.transcribe(samples: Array(all[lo...]), languageCode: languageCode) else { break }
            rounds += 1
            let fresh = Transcript(videoID: transcript.videoID,
                                   words: got.map { Word(text: $0.text, start: $0.start + from, end: $0.end + from) })
                .droppingNonSpeech(duration: duration).words
                .filter { $0.start >= last - 0.05 }
            log.info("이어 받아 적기 \(transcript.videoID, privacy: .public): \(String(format: "%.1f", from), privacy: .public)초부터 낱말 \(fresh.count)개")
            guard !fresh.isEmpty else { break }
            words += fresh
            added += fresh.count
        }
        return Result(transcript: Transcript(videoID: transcript.videoID, words: words), rounds: rounds, added: added)
    }
}
