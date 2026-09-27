import Foundation
import os

/// AI CLI 한 턴을 자식 프로세스로 돌린다. CLI 가 무엇이든 여기 하나다 (AGENTS.md §2 — 유일한 자식 프로세스).
///
/// - 프롬프트는 표준 입력으로 준다 (`ps` 에 안 보이고 길이 제한이 없다)
/// - 표준 출력을 줄 단위로 `AgentStreamParser` 에 넣어 `AgentEvent` 로 흘린다
/// - **도구가 madi 2개 말고 보이면 턴을 끊는다** — CLI 가 도구 목록을 알려 줄 때(Claude `init`)만 잴 수 있다
/// - 결과 사건 없이 끝나면(로그인 만료 · CLI 가 죽음) 표준 오류 끝을 붙여 실패로 끝낸다. 조용히 끝나지 않는다 (§2-4)
public struct AgentRunner: Sendable {
    static let log = Logger(subsystem: "app.madi", category: "agent")

    public var executable: URL
    public var provider: any AgentProvider
    public var timeout: Duration

    public init(executable: URL, provider: any AgentProvider, timeout: Duration = .seconds(600)) {
        self.executable = executable; self.provider = provider; self.timeout = timeout
    }

    public func run(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await drive(request, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func drive(_ request: AgentRequest, _ out: AsyncThrowingStream<AgentEvent, Error>.Continuation) async throws {
        try FileManager.default.createDirectory(at: request.workDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = try provider.arguments(for: request)
        process.currentDirectoryURL = request.workDir
        process.environment = Self.environment(for: executable)
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = AsyncStream<Int32> { c in
            process.terminationHandler = { c.yield($0.terminationStatus); c.finish() }
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        try process.run()
        Self.log.info("\(provider.kind.rawValue, privacy: .public) 턴 시작 pid \(process.processIdentifier)")

        if provider.promptViaStdin { stdin.fileHandleForWriting.write(Data(request.prompt.utf8)) }
        try? stdin.fileHandleForWriting.close()

        // 표준 오류는 따로 모은다 — 파이프가 차면 CLI 가 멈춘다.
        let errTask = Task.detached { () -> Data in
            (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        }
        let timeoutTask = Task.detached { [timeout] in
            try await Task.sleep(for: timeout)
            process.terminate()
        }
        defer { timeoutTask.cancel() }

        var parser = provider.makeParser()
        var finished = false
        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                for event in parser.parse(line: line) {
                    if case .started(_, let tools?) = event, let extra = Self.unexpectedTools(tools) {
                        process.terminate()
                        out.yield(.finished(AgentOutcome(isError: true, message: "madi 도구 말고 다른 도구가 열려 있다: \(extra.joined(separator: ", "))")))
                        finished = true
                        break
                    }
                    if case .finished = event { finished = true }
                    out.yield(event)
                }
                if finished { break }
            }
        } catch is CancellationError {
            process.terminate()
            throw CancellationError()
        }

        var status: Int32 = 0
        for await s in exited { status = s }
        let err = String(decoding: await errTask.value, as: UTF8.self)
        if !finished {
            let tail = err.split(separator: "\n").suffix(5).joined(separator: "\n")
            let timedOut = clock.now - startedAt >= timeout
            out.yield(.finished(AgentOutcome(
                isError: true,
                message: timedOut ? "\(provider.kind.rawValue) 가 \(timeout) 안에 끝나지 않아 멈췄다"
                    : tail.isEmpty ? "\(provider.kind.rawValue) 가 결과 없이 끝났다 (종료 코드 \(status))" : tail
            )))
        }
        Self.log.info("\(provider.kind.rawValue, privacy: .public) 턴 끝 종료 코드 \(status)")
    }

    /// madi 서버 도구가 아닌 것. 없으면 nil.
    static func unexpectedTools(_ tools: [String]) -> [String]? {
        let extra = tools.filter { !$0.hasPrefix("mcp__\(MadiToolNames.server)__") }
        return extra.isEmpty ? nil : extra
    }

    /// Finder 로 켠 앱은 PATH 가 `/usr/bin:/bin` 뿐이다. CLI 가 옆에 둔 도우미(Codex 의 code-mode-host 등)를
    /// 찾을 수 있게 실행 파일 폴더를 앞에 넣는다. 부모가 Claude Code 안이면 붙는 표시는 지운다 (중첩으로 오인).
    static func environment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("CLAUDECODE") || key.hasPrefix("CLAUDE_CODE_") { env[key] = nil }
        var dirs: [String] = [
            executable.deletingLastPathComponent().path,
            executable.resolvingSymlinksInPath().deletingLastPathComponent().path,
        ]
        dirs += CLILocator.searchDirectories(home: FileManager.default.homeDirectoryForCurrentUser).map { $0.path }
        let inherited: String = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        dirs += inherited.split(separator: ":").map { String($0) }
        var seen = Set<String>()
        env["PATH"] = dirs.filter { seen.insert($0).inserted }.joined(separator: ":")
        return env
    }
}
