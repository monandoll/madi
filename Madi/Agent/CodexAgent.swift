import Foundation

/// Codex CLI — `codex exec --json` (AGENTS.md §3).
///
/// Claude 와 달리 "도구를 전부 끈다" 옵션이 없다. 사용자 설정을 무시하고 기능을 하나씩 끈다
/// (`docs/findings/2026-09-27-agent-cli-smoke.md`, Codex CLI 0.156.1 기준):
/// - `--ignore-user-config` 사용자 `config.toml` 의 플러그인 · MCP 서버 · 모델을 싣지 않는다. 로그인은 그대로
/// - `-s read-only` 파일을 쓰지 못한다
/// - 기능 끔 (`disabledFeatures`). **코드 모드(`code_mode_host`)는 끄지 않는다** — MCP 도구도 그 안에서 불린다
/// - madi 서버는 승인 없이 부른다 (`exec` 는 승인 정책이 never 라 승인 필요면 그대로 실패한다)
/// - 모델은 지정하지 않는다 (결정 ②). Codex 는 쓴 모델을 이벤트에 안 알려 준다 — CLI 판만 남는다
///
/// ⚠ 판마다 기능 이름이 바뀐다. 모르는 키는 Codex 가 경고로 알려 주고, 그건 `.warning` 으로 `events` 에 남는다.
public struct CodexAgent: AgentProvider {
    public let kind = AgentKind.codex
    public let promptViaStdin = true

    static let disabledFeatures = [
        "shell_tool", "unified_exec", "apps", "plugins", "multi_agent", "image_generation",
        "browser_use", "browser_use_external", "computer_use", "goals", "view_image", "sleep_tool",
        "tool_suggest", "skill_search", "in_app_browser", "hooks",
    ]

    public init() {}

    public func arguments(for request: AgentRequest) throws -> [String] {
        var args = [
            "exec", "--json", "--ignore-user-config", "--skip-git-repo-check",
            "-s", "read-only", "-C", request.workDir.path,
        ]
        for f in Self.disabledFeatures { args += ["-c", "features.\(f)=false"] }
        args += ["-c", #"web_search="disabled""#]
        let server = "mcp_servers.\(MadiToolNames.server)"
        args += ["-c", "\(server).command=\(Self.toml(request.mcp.executable.path))"]
        args += ["-c", "\(server).args=[\(request.mcp.arguments.map(Self.toml).joined(separator: ","))]"]
        args += ["-c", #"\#(server).default_tools_approval_mode="approve""#]
        args += ["-"]   // 프롬프트는 표준 입력
        return args
    }

    /// TOML 기본 문자열. 경로에 공백("Application Support") · 따옴표가 들어가도 깨지지 않게.
    static func toml(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04X", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    public func makeParser() -> any AgentStreamParser { Parser() }

    /// `--json` 한 줄 = JSON 하나. 쓰는 것: `thread.started` · `item.*` · `turn.completed` · `turn.failed` · `error`.
    struct Parser: AgentStreamParser {
        private var lastError: String?

        mutating func parse(line: String) -> [AgentEvent] {
            guard let d = Self.json(line) else { return [] }
            let item = d["item"] as? [String: Any] ?? [:]
            switch d["type"] as? String {
            case "thread.started":
                return [.started(model: nil, tools: nil)]

            case "item.started" where item["type"] as? String == "mcp_tool_call":
                return [.toolCall(name: item["tool"] as? String ?? "?", ok: nil)]

            case "item.completed":
                switch item["type"] as? String {
                case "agent_message":
                    return (item["text"] as? String).map { [.text($0)] } ?? []
                case "mcp_tool_call":
                    return [.toolCall(name: item["tool"] as? String ?? "?", ok: item["status"] as? String == "completed")]
                case "error":
                    return (item["message"] as? String).map { [.warning($0)] } ?? []
                default:
                    return []
                }

            case "turn.completed":
                return [.finished(AgentOutcome(isError: false))]

            case "turn.failed":
                let message = ((d["error"] as? [String: Any])?["message"] as? String) ?? lastError
                return [.finished(AgentOutcome(isError: true, message: message))]

            case "error":
                // 턴 밖의 오류(로그인 · 네트워크). 곧 turn.failed 가 오거나 프로세스가 끝난다.
                lastError = d["message"] as? String
                return lastError.map { [.warning($0)] } ?? []

            default:
                return []
            }
        }
    }
}
