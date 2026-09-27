import Testing
import Foundation
import CryptoKit
@testable import MadiKit

/// 앱이 대신 받는 파일 — 공식 배포처 · 커밋 고정 · SHA-256 (§2 · §3). 네트워크 없이 file:// 로 흉내 낸다.
struct DownloadsTests {

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "madi-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func file(_ dir: URL, _ name: String, _ body: String, path: String) throws -> DownloadCatalog.File {
        let url = dir.appending(path: name)
        try Data(body.utf8).write(to: url)
        let hash = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        return DownloadCatalog.File(url: url, path: path, size: Int64(body.utf8.count), sha256: hash)
    }

    @Test("목록: 모든 주소가 커밋에 고정되고 해시가 있다")
    func catalogIsPinned() throws {
        let c = try DownloadCatalog.bundled()
        for pack in c.packs {
            for f in pack.files {
                #expect(f.url.scheme == "https")
                // 브랜치 이름(main)으로 받지 않는다 — 40자리 커밋이 주소에 있어야 한다.
                #expect(f.url.absoluteString.range(of: "/[0-9a-f]{40}/", options: .regularExpression) != nil, "\(f.url)")
                #expect(f.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
                #expect(f.size > 0)
            }
        }
        let model = try #require(c.pack(ModelPreparer.packID))
        #expect(model.files.contains { $0.path.hasSuffix("TextDecoder.mlmodelc/weights/weight.bin") })
        #expect(model.files.contains { $0.path == "tokenizers/models/openai/whisper-small/tokenizer.json" })
        #expect(abs(Double(model.totalSize) / 1e6 - 489) < 5)
    }

    @Test("목록: 글꼴 7종 전부 OFL, 라이선스 파일을 같이 받는다")
    func catalogFontsAreOFL() throws {
        let fonts = try DownloadCatalog.bundled().packs.filter { $0.kind == .font }
        #expect(Set(fonts.compactMap(\.family)) == ["SUIT Variable", "Noto Sans KR", "Gothic A1", "Jua", "Gowun Dodum", "Do Hyeon", "Black Han Sans"])
        for f in fonts {
            #expect(f.license == "OFL-1.1")
            #expect(f.files.contains { $0.path.hasSuffix("/OFL.txt") })
            #expect(f.files.allSatisfy { $0.path.hasPrefix("fonts/\(f.family!)/") })
        }
    }

    @Test("받은 파일은 해시를 확인하고, 이미 받은 건 건너뛴다")
    func fetchVerifiesAndSkips() async throws {
        let src = try tempDir(), root = try tempDir()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: root) }
        let pack = DownloadCatalog.Pack(id: "t", kind: .font, family: "T", license: "OFL-1.1", files: [
            try file(src, "a", "가나다", path: "fonts/T/a.ttf"),
            try file(src, "b", "라이선스", path: "fonts/T/OFL.txt"),
        ])
        #expect(!Downloads.isReady(pack, root: root))
        try await Downloads.fetch(pack, root: root)
        #expect(Downloads.isReady(pack, root: root))
        #expect(try String(contentsOf: root.appending(path: "fonts/T/a.ttf"), encoding: .utf8) == "가나다")
        // 원본이 없어져도 다시 받지 않으니 괜찮다.
        try FileManager.default.removeItem(at: src)
        try await Downloads.fetch(pack, root: root)
    }

    @Test("해시가 틀리면 버리고 제자리에 두지 않는다")
    func rejectsChecksumMismatch() async throws {
        let src = try tempDir(), root = try tempDir()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: root) }
        var f = try file(src, "a", "진짜", path: "fonts/T/a.ttf")
        f.sha256 = String(repeating: "0", count: 64)
        let pack = DownloadCatalog.Pack(id: "t", kind: .font, family: "T", license: "OFL-1.1", files: [f])
        await #expect(throws: DownloadError.self) { try await Downloads.fetch(pack, root: root) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "fonts/T/a.ttf").path))
        #expect(!Downloads.isReady(pack, root: root))
    }

    @Test("글꼴 목록 — 기본 먼저, 목록 글꼴은 받기 전에도 보인다")
    func fontChoices() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let choices = FontLibrary.choices(catalog: try DownloadCatalog.bundled(), root: root)
        #expect(choices.first == FontLibrary.Choice(family: nil, source: .bundled))
        let jua = try #require(choices.first { $0.family == "Jua" })
        if case .catalog(let ready, _, let bytes) = jua.source { #expect(!ready && bytes > 1_000_000) } else { Issue.record("Jua 가 목록 글꼴이 아니다") }
        #expect(choices.contains { $0.family == "Apple SD Gothic Neo" && $0.source == .installed })
        #expect(Set(choices.compactMap(\.family)).count == choices.count - 1)   // 중복 없음
    }

    @Test("모델 준비 — 받고 데우다 실패하면 기다리던 쪽에 알린다")
    func preparerFailsLoudly() async throws {
        let src = try tempDir(), root = try tempDir()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: root) }
        // 진짜 모델이 아닌 파일 — 받기는 되지만 데우기(WhisperKit 로드)에서 실패해야 한다.
        let pack = DownloadCatalog.Pack(id: ModelPreparer.packID, kind: .model, family: nil, license: "MIT", files: [
            try file(src, "c", "{}", path: "whisperkit/openai_whisper-small/config.json"),
        ])
        let preparer = try ModelPreparer(catalog: DownloadCatalog(packs: [pack]), root: root)
        var seen: [ModelPreparer.State] = []
        let stream = await preparer.states()
        let watcher = Task { for await s in stream { seen.append(s); if case .failed = s { break } } ; return seen }
        await preparer.prepare(retryDelaySec: 0.01)
        let states = await watcher.value
        #expect(states.contains(.warming))
        guard case .failed = await preparer.state else { Issue.record("실패 상태가 아니다: \(await preparer.state)"); return }
        await #expect(throws: TranscriptionFailure.self) { _ = try await preparer.readyProvider() }
    }
}
