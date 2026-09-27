import Foundation

/// 전사. **아키텍처 분기를 가두는 두 곳 중 하나다** (`AGENTS.md §3`, `§14`).
///
/// Apple Silicon 은 WhisperKit(CoreML/ANE), Intel 은 whisper.cpp 폴백이다.
/// `#if arch(arm64)` 를 코드 곳곳에 뿌리지 않고 **런타임에 한 번 골라 주입한다.**
public protocol TranscriptionProvider: Sendable {
    /// **낱말 단위 타임스탬프가 필수다.** 문장 단위로만 오면 자막을 끊을 수 없고
    /// G6(싱크 0.15초)을 맞출 수도 없다.
    func transcribe(_ url: URL, languageCode: String) async throws -> Transcript

    /// 모델을 올리고 한 번 데운다. 첫 영상이 이 비용을 치르지 않게 미리 부른다.
    func warmUp() async throws
}

public extension TranscriptionProvider {
    func warmUp() async throws {}

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

/// 이 Mac 에서 쓸 전사 엔진. **아키텍처 분기는 여기 한 곳이다** (§3 · §14 — 런타임에 한 번 골라 주입한다).
///
/// | | 엔진 | 모델 팩 |
/// |---|---|---|
/// | Apple Silicon | WhisperKit (CoreML · ANE) | `model.whisper-small` |
/// | Intel | whisper.cpp (CPU · Metal) | `model.whisper-small-ggml` |
///
/// WhisperKit 은 x86_64 로 빌드는 되지만 전사 중 죽는다 (docs/stage-3.spec.md 결정 ④).
public enum TranscriptionEngine: String, Sendable {
    case whisperKit, whisperCpp

    public static var forThisMachine: TranscriptionEngine {
        MachineArch.current == "arm64" ? .whisperKit : .whisperCpp
    }

    public var packID: String {
        switch self {
        case .whisperKit: "model.whisper-small"
        case .whisperCpp: "model.whisper-small-ggml"
        }
    }

    /// `root` 는 받은 파일이 있는 곳 (`Downloads.defaultRoot`).
    public func makeProvider(root: URL) -> any TranscriptionProvider {
        switch self {
        case .whisperKit:
            WhisperKitProvider(model: "small",
                               modelFolder: root.appending(path: "whisperkit/openai_whisper-small"),
                               tokenizerFolder: root.appending(path: "tokenizers"))
        case .whisperCpp:
            WhisperCppProvider(modelPath: root.appending(path: "whispercpp/ggml-small.bin"))
        }
    }
}
