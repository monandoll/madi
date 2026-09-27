import Foundation

/// Claude Code — `claude -p --output-format stream-json` (AGENTS.md §3).
///
/// 옵션만으로 도구 2개로 닫힌다 (`docs/findings/2026-09-27-agent-cli-smoke.md`):
/// - `--tools ""` 기본 도구(셸 · 파일 · 웹) 전부 끔
/// - `--strict-mcp-config` 사용자 MCP 서버를 싣지 않음. `--mcp-config` 의 madi 하나만
/// - `--setting-sources ""` 사용자 · 프로젝트 설정(훅 등)을 읽지 않음
/// - 모델은 지정하지 않는다 (결정 ② — 구독 기본값, 쓴 것을 기록)
public struct ClaudeAgent: AgentProvider {
    public let kind = AgentKind.claude
    public let promptViaStdin = true

    public init() {}

    public func arguments(for request: AgentRequest) throws -> [String] {
        let config: [String: Any] = ["mcpServers": [MadiToolNames.server: [
            "type": "stdio",
            "command": request.mcp.executable.path,
            "args": request.mcp.arguments,
        ]]]
        let url = request.workDir.appending(path: "mcp.json")
        try JSONSerialization.data(withJSONObject: config, options: [.withoutEscapingSlashes]).write(to: url)
        return [
            "-p",
            "--output-format", "stream-json", "--verbose",
            "--mcp-config", url.path, "--strict-mcp-config",
            "--tools", "",
            "--allowedTools", MadiToolNames.claude.joined(separator: ","),
            "--setting-sources", "",
            "--no-session-persistence",
        ]
    }

    public func makeParser() -> any AgentStreamParser { Parser() }

    /// `stream-json` 한 줄 = JSON 하나. 쓰는 것: `system/init` · `assistant` · `user`(도구 결과) · `result`.
    struct Parser: AgentStreamParser {
        private var toolNames: [String: String] = [:]

        mutating func parse(line: String) -> [AgentEvent] {
            guard let d = Self.json(line) else { return [] }
            switch d["type"] as? String {
            case "system" where d["subtype"] as? String == "init":
                return [.started(model: d["model"] as? String, tools: d["tools"] as? [String])]

            case "assistant":
                let content = (d["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                return content.compactMap { c in
                    switch c["type"] as? String {
                    case "text":
                        return (c["text"] as? String).map(AgentEvent.text)
                    case "tool_use":
                        let name = Self.shortName(c["name"] as? String ?? "?")
                        if let id = c["id"] as? String { toolNames[id] = name }
                        return .toolCall(name: name, ok: nil)
                    default:
                        return nil
                    }
                }

            case "user":
                let content = (d["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                return content.compactMap { c in
                    guard c["type"] as? String == "tool_result", let id = c["tool_use_id"] as? String else { return nil }
                    return .toolCall(name: toolNames[id] ?? "?", ok: !(c["is_error"] as? Bool ?? false))
                }

            case "result":
                let failed = (d["is_error"] as? Bool ?? false) || (d["subtype"] as? String ?? "success") != "success"
                let model = (d["modelUsage"] as? [String: Any]).flatMap { $0.keys.sorted().first }
                let message = (d["result"] as? String) ?? (d["errors"] as? [String])?.joined(separator: "\n")
                return [.finished(AgentOutcome(isError: failed, message: message, model: model))]

            default:
                return []
            }
        }

        /// `mcp__madi__read_digest` → `read_digest`
        static func shortName(_ name: String) -> String {
            let prefix = "mcp__\(MadiToolNames.server)__"
            return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        }
    }
}
