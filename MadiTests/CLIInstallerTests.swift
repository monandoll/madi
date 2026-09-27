import Testing
import Foundation
@testable import MadiKit

/// CLI 설치 대행 (docs/stage-6.spec.md 결정 ②). 네트워크 없이 되는 부분만 — 실제 설치는 `madi-spike cli-install`.
struct CLIInstallerTests {

    static let release = #"""
    {"tag_name":"rust-v0.157.1","assets":[
     {"name":"codex-package-aarch64-apple-darwin.tar.gz","browser_download_url":"https://github.com/openai/codex/releases/download/rust-v0.157.1/codex-package-aarch64-apple-darwin.tar.gz","digest":"sha256:6cda538d19c2f4d9dce965369aa22011afa9dce8c7a73c234b66eb3611ea4aab"},
     {"name":"codex-package-x86_64-apple-darwin.tar.gz","browser_download_url":"https://github.com/openai/codex/releases/download/rust-v0.157.1/codex-package-x86_64-apple-darwin.tar.gz","digest":"sha256:d2285a56c7d1f74923e708b18308870e367479a4423784ed488578af89d6af77"},
     {"name":"codex-aarch64-unknown-linux-musl.tar.gz","browser_download_url":"https://x","digest":"sha256:00"}]}
    """#

    @Test("이 Mac 의 아키텍처에 맞는 공식 패키지와 SHA-256 을 고른다")
    func picksAsset() throws {
        let arm = try CLIInstaller.pickCodexAsset(Data(Self.release.utf8), arch: "arm64")
        #expect(arm.name == "codex-package-aarch64-apple-darwin.tar.gz")
        #expect(arm.sha256 == "6cda538d19c2f4d9dce965369aa22011afa9dce8c7a73c234b66eb3611ea4aab")
        let intel = try CLIInstaller.pickCodexAsset(Data(Self.release.utf8), arch: "x86_64")
        #expect(intel.name.contains("x86_64"))
    }

    @Test("digest 가 없으면 받지 않는다 — 대조할 수 없다")
    func refusesWithoutDigest() {
        let noDigest = #"{"assets":[{"name":"codex-package-aarch64-apple-darwin.tar.gz","browser_download_url":"https://x"}]}"#
        #expect(throws: CLIInstaller.Failure.noAssetForArch("arm64")) {
            try CLIInstaller.pickCodexAsset(Data(noDigest.utf8), arch: "arm64")
        }
    }

    @Test("서명 팀 — 서명 없는 파일은 nil, 다른 팀이면 거절")
    func signingTeam() throws {
        let f = FileManager.default.temporaryDirectory.appending(path: "unsigned-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        #expect(CLIInstaller.signingTeam(f) == nil)
        #expect(throws: CLIInstaller.Failure.wrongSigner(expected: CLIInstaller.codexTeam, got: nil)) {
            try CLIInstaller.requireTeam(f, CLIInstaller.codexTeam)
        }
    }

    @Test("SHA-256 을 스트리밍으로 잰다")
    func hashes() throws {
        let f = FileManager.default.temporaryDirectory.appending(path: "h-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        #expect(try CLIInstaller.sha256(of: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
