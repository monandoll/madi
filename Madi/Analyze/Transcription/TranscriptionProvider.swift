import Foundation

/// 전사. **아키텍처 분기를 가두는 두 곳 중 하나다** (`AGENTS.md §3`, `§14`).
///
/// Apple Silicon 은 WhisperKit(CoreML/ANE), Intel 은 whisper.cpp 폴백이다.
/// `#if arch(arm64)` 를 코드 곳곳에 뿌리지 않고 **런타임에 한 번 골라 주입한다.**
public protocol TranscriptionProvider: Sendable {
    /// **낱말 단위 타임스탬프가 필수다.** 문장 단위로만 오면 자막을 끊을 수 없고
    /// G6(싱크 0.15초)을 맞출 수도 없다.
    func transcribe(_ url: URL, languageCode: String) async throws -> Transcript
}

public extension TranscriptionProvider {
    func transcribe(_ url: URL) async throws -> Transcript {
        try await transcribe(url, languageCode: "ko")
    }
}

public enum TranscriptionFailure: Error, CustomStringConvertible {
    case modelUnavailable(String)
    case noWordTimestamps

    public var description: String {
        switch self {
        case .modelUnavailable(let reason): "전사 모델을 준비하지 못했습니다: \(reason)"
        case .noWordTimestamps:
            "전사에 낱말 단위 시각이 없습니다 — 이 결과로는 자막을 끊을 수 없습니다"
        }
    }
}
