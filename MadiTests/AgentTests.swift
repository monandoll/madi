import Testing
import Foundation
@testable import MadiKit

/// AI CLI 한 턴 (docs/stage-4.spec.md 3번). 줄 읽기는 **실제 CLI 출력**(2026-09-27, 길이만 줄임)으로,
/// 프로세스는 가짜 CLI 셸 스크립트로 잰다. 진짜 CLI 확인은 `docs/findings/2026-09-27-agent-cli-smoke.md`.
struct AgentTests {

    private func request(_ dir: URL) -> AgentRequest {
        AgentRequest(
            prompt: "편집안을 만들어라",
            mcp: .madi(executable: URL(fileURLWithPath: "/Applications/Madi.app/Contents/MacOS/madi-mcp"),
                       videoID: "v1", compositionID: "c1",
                       dbPath: "/Users/x/Library/Application Support/madi/madi.sqlite"),
            workDir: dir
        )
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "agent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func parse(_ provider: any AgentProvider, _ lines: [String]) -> [AgentEvent] {
        var p = provider.makeParser()
        return lines.flatMap { p.parse(line: $0) }
    }

    // MARK: - Claude

    @Test("Claude 인자 — 기본 도구 끔 · madi 서버만 · 설정 안 읽음 · 모델 지정 안 함")
    func claudeArguments() throws {
        let dir = try tempDir()
        let args = try ClaudeAgent().arguments(for: request(dir))
        #expect(args.contains("--strict-mcp-config"))
        #expect(args[args.firstIndex(of: "--tools")! + 1] == "")
        #expect(args[args.firstIndex(of: "--setting-sources")! + 1] == "")
        #expect(args[args.firstIndex(of: "--allowedTools")! + 1] == "mcp__madi__read_digest,mcp__madi__write_composition")
        #expect(!args.contains("--model"))
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "mcp.json"))) as? [String: Any]
        let madi = try #require((config?["mcpServers"] as? [String: Any])?["madi"] as? [String: Any])
        #expect(madi["args"] as? [String] == ["--video", "v1", "--composition", "c1", "--db", "/Users/x/Library/Application Support/madi/madi.sqlite"])
    }

    static let claudeLines = [
        #"{"type":"system","subtype":"init","cwd":"/tmp/w","tools":["mcp__madi__read_digest","mcp__madi__write_composition"],"mcp_servers":[{"name":"madi","status":"connected"}],"model":"claude-opus-5-5","claude_code_version":"2.1.283"}"#,
        #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"tool_use","id":"toolu_01","name":"mcp__madi__read_digest","input":{"videoId":"v1"}}]}}"#,
        #"{"type":"rate_limit_event"}"#,
        ##"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_01","content":[{"type":"text","text":"# VIDEO v1"}]}]}}"##,
        #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"영상 길이는 60.0초입니다."}]}}"#,
        #"{"type":"result","subtype":"success","is_error":false,"result":"영상 길이는 60.0초입니다.","duration_ms":3839,"num_turns":2,"modelUsage":{"claude-opus-5-5":{"inputTokens":10}}}"#,
    ]

    @Test("Claude stream-json 을 읽는다 — 시작 · 도구 호출 · 말 · 끝(모델)")
    func claudeParses() {
        #expect(parse(ClaudeAgent(), Self.claudeLines) == [
            .started(model: "claude-opus-5-5", tools: ["mcp__madi__read_digest", "mcp__madi__write_composition"]),
            .toolCall(name: "read_digest", ok: nil),
            .toolCall(name: "read_digest", ok: true),
            .text("영상 길이는 60.0초입니다."),
            .finished(AgentOutcome(isError: false, message: "영상 길이는 60.0초입니다.", model: "claude-opus-5-5")),
        ])
    }

    @Test("Claude 오류 결과는 실패로 끝난다")
    func claudeError() {
        let events = parse(ClaudeAgent(), [#"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["로그인 만료"]}"#])
        #expect(events == [.finished(AgentOutcome(isError: true, message: "로그인 만료", model: nil))])
    }

    // MARK: - Codex

    @Test("Codex 인자 — 사용자 설정 무시 · 읽기 전용 · 셸 끔 · 코드 모드는 켜 둠 · madi 승인 없이")
    func codexArguments() throws {
        let args = try CodexAgent().arguments(for: request(try tempDir()))
        #expect(args.prefix(2) == ["exec", "--json"])
        #expect(args.contains("--ignore-user-config"))
        #expect(args[args.firstIndex(of: "-s")! + 1] == "read-only")
        #expect(args.contains("features.shell_tool=false"))
        #expect(!args.contains { $0.hasPrefix("features.code_mode_host") })
        #expect(args.contains(#"mcp_servers.madi.default_tools_approval_mode="approve""#))
        #expect(args.contains(#"mcp_servers.madi.args=["--video","v1","--composition","c1","--db","/Users/x/Library/Application Support/madi/madi.sqlite"]"#))
        #expect(!args.contains("-m") && !args.contains("--model"))
        #expect(args.last == "-")
    }

    @Test("TOML 문자열 — 따옴표 · 역슬래시가 깨지지 않는다")
    func tomlEscapes() {
        #expect(CodexAgent.toml(#"/a "b"\c"#) == #""/a \"b\"\\c""#)
    }

    static let codexLines = [
        #"{"type":"thread.started","thread_id":"01a0"}"#,
        #"{"type":"turn.started"}"#,
        #"{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Codex is ignoring 1 unrecognized configuration setting."}}"#,
        #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"다이제스트를 읽겠습니다.\n"}}"#,
        #"{"type":"item.started","item":{"id":"item_2","type":"mcp_tool_call","server":"madi","tool":"read_digest","arguments":{"videoId":"v1"},"result":null,"error":null,"status":"in_progress"}}"#,
        ##"{"type":"item.completed","item":{"id":"item_2","type":"mcp_tool_call","server":"madi","tool":"read_digest","arguments":{"videoId":"v1"},"result":{"content":[{"type":"text","text":"# VIDEO v1"}]},"error":null,"status":"completed"}}"##,
        #"{"type":"item.completed","item":{"id":"item_3","type":"mcp_tool_call","server":"madi","tool":"write_composition","arguments":{},"result":null,"error":{"message":"MCP tool call requires approval, but approval policy is never"},"status":"failed"}}"#,
        #"{"type":"turn.completed","usage":{"input_tokens":31998,"output_tokens":293}}"#,
    ]

    @Test("Codex --json 을 읽는다 — 경고 · 말 · 도구 성공/실패 · 끝")
    func codexParses() {
        #expect(parse(CodexAgent(), Self.codexLines) == [
            .started(model: nil, tools: nil),
            .warning("Codex is ignoring 1 unrecognized configuration setting."),
            .text("다이제스트를 읽겠습니다.\n"),
            .toolCall(name: "read_digest", ok: nil),
            .toolCall(name: "read_digest", ok: true),
            .toolCall(name: "write_composition", ok: false),
            .finished(AgentOutcome(isError: false)),
        ])
    }

    @Test("Codex 턴 실패")
    func codexFailed() {
        let events = parse(CodexAgent(), [
            #"{"type":"error","message":"stream disconnected"}"#,
            #"{"type":"turn.failed","error":{"message":"You've hit your usage limit."}}"#,
        ])
        #expect(events.last == .finished(AgentOutcome(isError: true, message: "You've hit your usage limit.")))
    }

    // MARK: - 실행기 (가짜 CLI)

    /// 표준 입력을 파일에 적고, 준비한 줄을 내보내고, 주어진 코드로 끝나는 가짜 CLI.
    private func fakeCLI(_ dir: URL, lines: [String], stderr: String = "", exit code: Int32 = 0) throws -> URL {
        let body = lines.map { "printf '%s\\n' '\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
        let script = """
        #!/bin/sh
        cat > "\(dir.path)/stdin.txt"
        printf '%s' "$*" > "\(dir.path)/argv.txt"
        \(body)
        printf '%s' '\(stderr)' >&2
        exit \(code)
        """
        let url = dir.appending(path: "fake-cli")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func collect(_ runner: AgentRunner, _ req: AgentRequest) async throws -> [AgentEvent] {
        var out: [AgentEvent] = []
        for try await e in runner.run(req) { out.append(e) }
        return out
    }

    @Test("프롬프트를 표준 입력으로 주고 끝까지 읽는다")
    func runsTurn() async throws {
        let dir = try tempDir()
        let exe = try fakeCLI(dir, lines: Self.claudeLines)
        let events = try await collect(AgentRunner(executable: exe, provider: ClaudeAgent()), request(dir.appending(path: "work")))
        #expect(events.count == 5)
        #expect(events.last == .finished(AgentOutcome(isError: false, message: "영상 길이는 60.0초입니다.", model: "claude-opus-5-5")))
        #expect(try String(contentsOf: dir.appending(path: "stdin.txt"), encoding: .utf8) == "편집안을 만들어라")
    }

    @Test("madi 말고 다른 도구가 보이면 턴을 끊는다")
    func refusesExtraTools() async throws {
        let dir = try tempDir()
        let leaky = #"{"type":"system","subtype":"init","tools":["Bash","mcp__madi__read_digest"],"model":"m"}"#
        let exe = try fakeCLI(dir, lines: [leaky] + Self.claudeLines.dropFirst())
        let events = try await collect(AgentRunner(executable: exe, provider: ClaudeAgent()), request(dir.appending(path: "work")))
        guard case .finished(let outcome) = try #require(events.last) else { Issue.record("끝나지 않았다"); return }
        #expect(outcome.isError)
        #expect(outcome.message?.contains("Bash") == true)
        #expect(!events.contains(.text("영상 길이는 60.0초입니다.")))
    }

    @Test("결과 없이 죽으면 표준 오류를 붙여 실패로 끝난다 — 조용히 끝나지 않는다")
    func failsLoudly() async throws {
        let dir = try tempDir()
        let exe = try fakeCLI(dir, lines: [], stderr: "Please run /login", exit: 1)
        let events = try await collect(AgentRunner(executable: exe, provider: CodexAgent()), request(dir.appending(path: "work")))
        #expect(events == [.finished(AgentOutcome(isError: true, message: "Please run /login"))])
    }

    @Test("시간을 넘기면 멈추고 실패로 끝난다")
    func timesOut() async throws {
        let dir = try tempDir()
        let url = dir.appending(path: "slow-cli")
        try "#!/bin/sh\ncat > /dev/null\nsleep 30\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let events = try await collect(AgentRunner(executable: url, provider: ClaudeAgent(), timeout: .milliseconds(500)), request(dir.appending(path: "work")))
        guard case .finished(let outcome) = try #require(events.last) else { Issue.record("끝나지 않았다"); return }
        #expect(outcome.isError)
        #expect(outcome.message?.contains("끝나지 않아") == true)
    }

    @Test("Claude 로그인 상태 JSON")
    func claudeLogin() {
        #expect(CLILocator.claudeLoggedIn(#"{"loggedIn": true, "authMethod": "claude.ai"}"#))
        #expect(!CLILocator.claudeLoggedIn(#"{"loggedIn": false}"#))
        #expect(!CLILocator.claudeLoggedIn("Not logged in"))
    }
}
