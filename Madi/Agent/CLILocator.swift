import Foundation

/// AI 가 연결됐는가 — 설치 · 로그인 (AGENTS.md §10 "AI 미연결 상태에서는 러너를 스폰하지 않는다").
///
/// 4단계는 **알아내기까지만** 한다. 설치 · 로그인을 대신 해 주는 것은 6단계(배포)다 (docs/stage-4.spec.md).
public enum AgentConnection: Sendable, Equatable {
    case notInstalled
    case notLoggedIn(executable: URL, version: String?)
    case ready(executable: URL, version: String?)

    public var isReady: Bool { if case .ready = self { true } else { false } }
}

public enum CLILocator {
    /// Finder 로 켠 앱은 로그인 셸의 PATH 를 모른다. 설치 방법별 흔한 자리를 직접 본다.
    public static func searchDirectories(home: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin"),          // Homebrew (Apple Silicon)
            URL(fileURLWithPath: "/usr/local/bin"),             // Homebrew (Intel) · 공식 설치 스크립트
            home.appending(path: ".local/bin"),                 // Claude Code 설치 스크립트
            home.appending(path: ".claude/local"),              // Claude Code 옛 로컬 설치
            home.appending(path: ".npm-global/bin"),
            home.appending(path: ".bun/bin"),
            home.appending(path: ".volta/bin"),
        ]
    }

    /// 실행 파일 자리. 흔한 자리에 없으면 로그인 셸에 한 번 묻는다 (nvm 처럼 자리가 사람마다 다른 설치).
    public static func locate(_ kind: AgentKind, home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> URL? {
        let fm = FileManager.default
        for dir in searchDirectories(home: home) {
            let url = dir.appending(path: kind.command)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        let shell = URL(fileURLWithPath: "/bin/zsh")
        guard let r = try? await ProcessCapture.run(shell, ["-lc", "command -v \(kind.command)"], timeout: .seconds(10)),
              r.status == 0 else { return nil }
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    public static func connection(_ kind: AgentKind) async -> AgentConnection {
        guard let exe = await locate(kind) else { return .notInstalled }
        let version = try? await ProcessCapture.run(exe, ["--version"], timeout: .seconds(15))
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let loggedIn: Bool
        switch kind {
        case .claude:
            // `{"loggedIn": true, ...}`
            let r = try? await ProcessCapture.run(exe, ["auth", "status"], timeout: .seconds(15))
            loggedIn = r.map { Self.claudeLoggedIn($0.stdout) } ?? false
        case .codex:
            // "Logged in using ChatGPT" — 판에 따라 표준 오류로 나온다
            let r = try? await ProcessCapture.run(exe, ["login", "status"], timeout: .seconds(15))
            loggedIn = r.map { $0.status == 0 && ($0.stdout + $0.stderr).contains("Logged in") } ?? false
        }
        return loggedIn ? .ready(executable: exe, version: version) : .notLoggedIn(executable: exe, version: version)
    }

    static func claudeLoggedIn(_ json: String) -> Bool {
        guard let d = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return false }
        return d["loggedIn"] as? Bool ?? false
    }
}

/// 짧은 명령 하나를 돌려 출력을 모은다 (버전 · 로그인 확인용). 긴 턴은 `AgentRunner`.
enum ProcessCapture {
    struct Result: Sendable { var status: Int32; var stdout: String; var stderr: String }

    static func run(_ exe: URL, _ args: [String], timeout: Duration) async throws -> Result {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = AgentRunner.environment(for: exe)
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let exited = AsyncStream<Int32> { c in p.terminationHandler = { c.yield($0.terminationStatus); c.finish() } }
        try p.run()
        let killer = Task.detached { try await Task.sleep(for: timeout); p.terminate() }
        async let o = Task.detached { (try? out.fileHandleForReading.readToEnd()) ?? Data() }.value
        async let e = Task.detached { (try? err.fileHandleForReading.readToEnd()) ?? Data() }.value
        var status: Int32 = -1
        for await s in exited { status = s }
        killer.cancel()
        return Result(status: status, stdout: String(decoding: await o, as: UTF8.self), stderr: String(decoding: await e, as: UTF8.self))
    }
}
