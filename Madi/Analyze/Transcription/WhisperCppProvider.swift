import Foundation
import whisper
import os

/// Intel(x86_64) 전사 — whisper.cpp (AGENTS.md §17 Tier 2).
///
/// WhisperKit 은 x86_64 로 빌드는 되지만 **전사 중 죽는다** (`TextDecoding.prepareDecoderInputs` EXC_BAD_ACCESS,
/// Rosetta 실측 — docs/stage-3.spec.md 결정 ④). 그래서 Intel 에서는 이걸 쓴다.
/// 모델은 같은 Whisper small 의 GGML 형식이다 (`downloads.json` `model.whisper-small-ggml`).
///
/// ★ 낱말 시각은 whisper.cpp 의 **토큰 시각**(`token_timestamps`)을 낱말로 묶어 만든다.
///   WhisperKit 의 낱말 시각보다 거칠 수 있다. Intel 성능 · 정확도는 실기 확인 못 함 (§17).
/// `whisper_context` 는 스레드 안전하지 않다 — 동시성은 큐가 막는다 (분석 1 동시) + 잠금.
public final class WhisperCppProvider: TranscriptionProvider, @unchecked Sendable {

    private static let log = Logger(subsystem: "app.madi", category: "transcribe")
    private let modelPath: URL
    private let lock = NSLock()
    private var context: OpaquePointer?

    public init(modelPath: URL) { self.modelPath = modelPath }

    deinit { if let context { whisper_free(context) } }

    public func warmUp() async throws { _ = try loadContext() }

    private func loadContext() throws -> OpaquePointer {
        try lock.withLock { try loadContextLocked() }
    }

    private func loadContextLocked() throws -> OpaquePointer {
        if let context { return context }
        // whisper.cpp · ggml 내부 로그를 끈다 (표준 오류로 수십 줄씩 나온다). 실패는 반환값으로 본다.
        whisper_log_set({ _, _, _ in }, nil)
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let made = whisper_init_from_file_with_params(modelPath.path, params) else {
            throw TranscriptionFailure.modelUnavailable("whisper.cpp 모델을 읽지 못했다: \(modelPath.lastPathComponent)")
        }
        context = made
        return made
    }

    public func transcribe(_ url: URL, languageCode: String) async throws -> Transcript {
        let samples = try await AudioAnalyzer.mono16k(url)
        let id = url.deletingPathExtension().lastPathComponent
        let words = try await transcribe(samples: samples, languageCode: languageCode) ?? []
        Self.log.info("전사(whisper.cpp) \(id, privacy: .public): 낱말 \(words.count)개")
        return Transcript(videoID: id, words: words)
    }

    public func transcribe(samples: [Float], languageCode: String) async throws -> [Word]? {
        guard !samples.isEmpty else { return [] }
        return Self.words(from: try decode(try loadContext(), samples: samples, languageCode: languageCode))
    }

    /// whisper.cpp 호출 — 동기 · 잠금 안에서. `whisper_context` 는 스레드 안전하지 않다.
    private func decode(_ ctx: OpaquePointer, samples: [Float], languageCode: String) throws -> [Token] {
        try lock.withLock {
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.print_special = false
            params.token_timestamps = true      // ★ 낱말 시각의 근거. 끄면 분절 · G6 불가
            params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))

            let status = languageCode.withCString { lang -> Int32 in
                params.language = lang
                return samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
            }
            guard status == 0 else { throw TranscriptionFailure.modelUnavailable("whisper.cpp 전사 실패 (\(status))") }

            var tokens: [Token] = []
            let eot = whisper_token_eot(ctx)
            for s in 0..<whisper_full_n_segments(ctx) {
                for t in 0..<whisper_full_n_tokens(ctx, s) {
                    let data = whisper_full_get_token_data(ctx, s, t)
                    guard data.id < eot, let cText = whisper_full_get_token_text(ctx, s, t) else { continue }
                    let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(cText).assumingMemoryBound(to: UInt8.self), count: strlen(cText)))
                    // t0 · t1 은 10ms 단위.
                    tokens.append(Token(bytes: bytes, start: Double(data.t0) / 100, end: Double(data.t1) / 100))
                }
            }
            return tokens
        }
    }

    struct Token { var bytes: [UInt8]; var start: Double; var end: Double }

    /// 토큰을 낱말로 묶는다. 앞에 공백이 붙은 토큰이 새 낱말의 시작이다.
    ///
    /// ★ 한글 한 글자(UTF-8 3바이트)가 **토큰 두 개로 쪼개질 수 있다.** 토큰 텍스트를 따로 문자열로 만들면
    ///   깨진 글자(�)가 나온다. 바이트로 모았다가 낱말 단위로 한 번에 푼다.
    static func words(from tokens: [Token]) -> [Word] {
        var out: [Word] = []
        var bytes: [UInt8] = []
        var start = 0.0, end = 0.0
        func flush() {
            let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { out.append(Word(text: text, start: start, end: max(end, start))) }
            bytes = []
        }
        for tok in tokens {
            if tok.bytes.first == UInt8(ascii: " ") || bytes.isEmpty {
                flush()
                start = tok.start
            }
            bytes += tok.bytes
            end = tok.end
        }
        flush()
        return out
    }
}
