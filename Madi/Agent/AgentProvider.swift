import Foundation

/// 크리에이터 본인 구독의 AI CLI 를 자식 프로세스로 띄운다 (AGENTS.md §2 · §10, docs/stage-4.spec.md 3번).
///
/// **둘 다 필수다** (§3) — Claude Code · Codex. 이 파일은 둘이 같이 쓰는 모양만 정한다.
/// CLI 마다 다른 것은 두 가지뿐: 인자를 만드는 법(`arguments`)과 출력 한 줄을 읽는 법(`makeParser`).
/// 둘 다 프로세스 없이 테스트한다. 프로세스는 `AgentRunner` 하나가 띄운다.
///
/// AI 에게는 **도구 2개만** 준다 (`madi-mcp`). 셸 · 파일 · 웹은 CLI 옵션으로 끈다 — 끄는 법은 CLI 마다 다르고
/// 판마다 바뀐다 (`docs/findings/2026-09-27-agent-cli-smoke.md`).
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude, codex

    /// 실행 파일 이름.
    public var command: String { rawValue }
}

/// AI CLI 가 띄울 MCP 서버 (`madi-mcp` 와 그 인자).
public struct MCPLaunch: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable; self.arguments = arguments
    }

    /// 번들 안 `madi-mcp` 로 영상 하나 · 편집안 하나에 묶어 띄운다 (결정 ①).
    public static func madi(executable: URL, videoID: String, compositionID: String,
                            revisionOf: String? = nil, dbPath: String? = nil) -> MCPLaunch {
        var args = ["--video", videoID, "--composition", compositionID]
        if let revisionOf { args += ["--revision-of", revisionOf] }
        if let dbPath { args += ["--db", dbPath] }
        return MCPLaunch(executable: executable, arguments: args)
    }
}

/// 한 턴 요청.
public struct AgentRequest: Sendable {
    /// 조립된 프롬프트 (4번 단위 — §10 순서).
    public var prompt: String
    public var mcp: MCPLaunch
    /// **빈 폴더.** CLI 가 여기서 CLAUDE.md · AGENTS.md 같은 걸 줍지 않게 한다. 설정 파일도 여기 쓴다.
    public var workDir: URL

    public init(prompt: String, mcp: MCPLaunch, workDir: URL) {
        self.prompt = prompt; self.mcp = mcp; self.workDir = workDir
    }
}

/// CLI 출력에서 읽어 낸 것. 화면(채팅 스트리밍)과 `events` 가 읽는다.
public enum AgentEvent: Sendable, Equatable {
    /// 턴 시작. CLI 가 알려 주는 만큼만 채운다 — Codex 는 모델 · 도구 목록을 안 알려 준다.
    case started(model: String?, tools: [String]?)
    /// AI 가 사람에게 한 말. 채팅에 스트리밍한다 (도구 호출 내부는 보이지 않는다 — §10).
    case text(String)
    /// 도구 호출. `ok == nil` 이면 시작, 아니면 끝.
    case toolCall(name: String, ok: Bool?)
    /// 턴은 계속되지만 남겨 둘 것 (Codex 가 모르는 설정 키를 무시했다 등 — 판이 바뀐 신호다).
    case warning(String)
    /// 턴 끝.
    case finished(AgentOutcome)
}

public struct AgentOutcome: Sendable, Equatable {
    public var isError: Bool
    /// 마지막 말 또는 오류 문장.
    public var message: String?
    /// 실제로 쓴 모델 (결정 ② — 지정하지 않고 기록만 한다). 모르면 nil.
    public var model: String?

    public init(isError: Bool, message: String? = nil, model: String? = nil) {
        self.isError = isError; self.message = message; self.model = model
    }
}

/// CLI 출력 한 줄 → 사건들. 줄 사이에 기억할 것(도구 호출 id → 이름)이 있어 상태를 가진다.
public protocol AgentStreamParser {
    mutating func parse(line: String) -> [AgentEvent]
}

public protocol AgentProvider: Sendable {
    var kind: AgentKind { get }
    /// `request.workDir` 에 필요한 설정 파일을 쓰고 인자를 돌려준다.
    func arguments(for request: AgentRequest) throws -> [String]
    func makeParser() -> any AgentStreamParser
    /// 프롬프트를 표준 입력으로 줄지. 인자로 주면 `ps` 에 보이고 길이 제한이 있다.
    var promptViaStdin: Bool { get }
}

public enum AgentProviders {
    public static func provider(_ kind: AgentKind) -> any AgentProvider {
        switch kind {
        case .claude: ClaudeAgent()
        case .codex: CodexAgent()
        }
    }
}

/// 이 턴에 AI 가 봐도 되는 도구 이름 — MCP 서버 이름이 `madi` 다.
public enum MadiToolNames {
    public static let server = "madi"
    public static let all = ["read_digest", "write_composition"]
    /// Claude 식 이름 (`mcp__<서버>__<도구>`).
    public static let claude = all.map { "mcp__\(server)__\($0)" }
}

// MARK: - 줄 읽기 도우미

extension AgentStreamParser {
    static func json(_ line: String) -> [String: Any]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any]
    }
}
