import Foundation
import CryptoKit
import Security

/// AI CLI 설치 · 로그인을 앱이 대신 한다 (AGENTS.md §2 · §1-9, docs/stage-6.spec.md 결정 ②).
///
/// **공식 설치 방법만** 쓴다. Homebrew · Node 가 필요한 방법은 뺀다 — 크리에이터 Mac 에 없고,
/// "한 줄만 붙여넣으면 된다" 도 요구다 (§1-9).
/// - Claude Code: 공식 네이티브 설치 스크립트 (`claude.ai/install.sh` — 스크립트가 체크섬을 확인한다) → `~/.local/bin/claude`
/// - Codex: 공식 GitHub 릴리스 `openai/codex` 의 `codex-package-<arch>-apple-darwin.tar.gz`
///   → `~/Library/Application Support/madi/cli/codex/`. `codex-code-mode-host` 가 같이 있어야 MCP 도구가 불린다
///
/// 받은 뒤 **서명 팀**을 확인한다 (Anthropic `Q6L2SF6YDW` · OpenAI `2DC432GLL2`). Codex 는 GitHub 가 기록한 SHA-256 과도 대조한다.
/// 판은 고정하지 않는다 — 공식 최신판을 받고 서명으로 믿는다.
public enum CLIInstaller {
    public static let claudeTeam = "Q6L2SF6YDW"
    public static let codexTeam = "2DC432GLL2"
    static let claudeScript = URL(string: "https://claude.ai/install.sh")!
    static let codexLatest = URL(string: "https://api.github.com/repos/openai/codex/releases/latest")!

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case download(String)
        case checksumMismatch
        case wrongSigner(expected: String, got: String?)
        case scriptFailed(Int32, String)
        case noAssetForArch(String)
        case notFoundAfterInstall

        public var description: String {
            switch self {
            case .download(let m): "받지 못했다: \(m)"
            case .checksumMismatch: "받은 파일의 SHA-256 이 공식 기록과 다르다"
            case .wrongSigner(let e, let g): "서명 팀이 다르다 (기대 \(e), 실제 \(g ?? "서명 없음"))"
            case .scriptFailed(let code, let tail): "설치 스크립트 실패 (종료 코드 \(code)): \(tail)"
            case .noAssetForArch(let a): "이 Mac(\(a))용 파일이 공식 릴리스에 없다"
            case .notFoundAfterInstall: "설치했는데 실행 파일을 찾지 못했다"
            }
        }
    }

    /// Codex 를 넣는 앱 전용 자리. `CLILocator` 가 여기도 본다.
    public static var codexHome: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/cli/codex", directoryHint: .isDirectory)
    }

    public static func install(_ kind: AgentKind, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               codexHome: URL = codexHome) async throws -> URL {
        switch kind {
        case .claude: try await installClaude(home: home)
        case .codex: try await installCodex(into: codexHome)
        }
    }

    // MARK: - Claude Code

    static func installClaude(home: URL) async throws -> URL {
        let (script, response) = try await URLSession.shared.data(from: claudeScript)
        guard (response as? HTTPURLResponse)?.statusCode == 200, script.starts(with: Data("#!".utf8)) else {
            throw Failure.download(claudeScript.absoluteString)
        }
        let tmp = FileManager.default.temporaryDirectory.appending(path: "claude-install-\(UUID().uuidString).sh")
        try script.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        let r = try await ProcessCapture.run(URL(fileURLWithPath: "/bin/bash"), [tmp.path], timeout: .seconds(600), environment: env)
        guard r.status == 0 else {
            throw Failure.scriptFailed(r.status, (r.stderr + r.stdout).split(separator: "\n").suffix(3).joined(separator: "\n"))
        }
        let exe = home.appending(path: ".local/bin/claude")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { throw Failure.notFoundAfterInstall }
        try requireTeam(exe.resolvingSymlinksInPath(), claudeTeam)
        return exe
    }

    // MARK: - Codex

    struct Asset: Equatable { var name: String; var url: URL; var sha256: String }

    /// 공식 릴리스 JSON 에서 이 아키텍처의 패키지를 고른다.
    static func pickCodexAsset(_ releaseJSON: Data, arch: String) throws -> Asset {
        let name = "codex-package-\(arch == "x86_64" ? "x86_64" : "aarch64")-apple-darwin.tar.gz"
        guard let json = try JSONSerialization.jsonObject(with: releaseJSON) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]],
              let a = assets.first(where: { $0["name"] as? String == name }),
              let urlString = a["browser_download_url"] as? String, let url = URL(string: urlString),
              let digest = a["digest"] as? String, digest.hasPrefix("sha256:") else {
            throw Failure.noAssetForArch(arch)
        }
        return Asset(name: name, url: url, sha256: String(digest.dropFirst("sha256:".count)))
    }

    static func installCodex(into dest: URL) async throws -> URL {
        let (release, _) = try await URLSession.shared.data(from: codexLatest)
        let asset = try pickCodexAsset(release, arch: MachineArch.current)
        let (file, response) = try await URLSession.shared.download(from: asset.url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download(asset.name) }
        guard try sha256(of: file) == asset.sha256 else { throw Failure.checksumMismatch }

        // 새 폴더에 풀고 확인이 끝나면 바꿔 끼운다 — 반쯤 깔린 상태가 남지 않게.
        let fm = FileManager.default
        let staging = dest.deletingLastPathComponent().appending(path: "codex.new-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let tar = try await ProcessCapture.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", file.path, "-C", staging.path], timeout: .seconds(300))
        guard tar.status == 0 else { try? fm.removeItem(at: staging); throw Failure.scriptFailed(tar.status, tar.stderr) }
        do {
            for bin in ["bin/codex", "bin/codex-code-mode-host"] {
                try requireTeam(staging.appending(path: bin), codexTeam)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: staging, to: dest)
        return dest.appending(path: "bin/codex")
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 서명 확인

    /// 실행 파일의 서명 팀. 서명이 없거나 깨졌으면 nil.
    public static func signingTeam(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func requireTeam(_ url: URL, _ team: String) throws {
        let got = signingTeam(url)
        guard got == team else { throw Failure.wrongSigner(expected: team, got: got) }
    }

    // MARK: - 로그인

    /// 브라우저 로그인을 띄우고 끝날 때까지 기다린다 (`AISetup.waiting`). 사람은 브라우저에서 버튼만 누른다 (§2).
    public static func login(_ kind: AgentKind, executable: URL) async throws {
        let args = kind == .claude ? ["auth", "login", "--claudeai"] : ["login"]
        let r = try await ProcessCapture.run(executable, args, timeout: .seconds(900))
        guard r.status == 0 else {
            throw Failure.scriptFailed(r.status, (r.stderr + r.stdout).split(separator: "\n").suffix(3).joined(separator: "\n"))
        }
    }
}
