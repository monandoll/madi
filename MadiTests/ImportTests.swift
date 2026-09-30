import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 가져오기 (§2). PhotoKit 없이 도는 핵심 로직과 폴더 감시.
struct ImportTests {

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "madi-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// `source` 파일을 복사해 주는 가짜 원본. 처음 `failTimes` 번은 실패한다 (iCloud 끊김).
    private func item(_ ref: String, copying source: URL, failTimes: Int = 0) -> IncomingVideo {
        let failures = Counter(failTimes)
        return IncomingVideo(source: .photos, sourceRef: ref, fileExtension: "MOV", capturedAt: Date()) { dest, progress in
            if await failures.take() { throw URLError(.networkConnectionLost) }
            try FileManager.default.copyItem(at: source, to: dest)
            progress(1)
        }
    }

    actor Counter {
        var left: Int
        init(_ n: Int) { left = n }
        func take() -> Bool { if left > 0 { left -= 1; return true }; return false }
    }

    @Test("새 영상 — 행 · 원본 사본 · 길이 · 분석 작업")
    func importsNewVideo() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 1)
        let db = try AppDatabase.inMemory()
        let queue = JobQueue(db: db, handlers: [:])   // 처리기 없음 — 줄만 선다
        let importer = Importer(db: db, queue: queue, originals: dir.appending(path: "originals"))

        let v = try #require(try await importer.receive(item("ph:A", copying: source)))
        #expect(v.status == .ready)
        #expect(v.localPath?.hasPrefix(dir.appending(path: "originals").path) == true)
        #expect(v.localPath?.hasSuffix(".mov") == true)
        #expect(abs((v.durationSec ?? 0) - 1) < 0.1 && v.width == 128)
        let jobs = try await db.writer.read { try JobRecord.fetchAll($0) }
        #expect(jobs.map(\.kind) == [.analyze] && jobs.first?.targetId == v.id)
        let events = try await db.writer.read { try EventRecord.fetchAll($0) }.map(\.kind)
        #expect(events.contains("import.seen") && events.contains("import.ready"))
    }

    @Test("같은 영상은 두 번 들이지 않는다")
    func skipsKnownVideo() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 0.5)
        let db = try AppDatabase.inMemory()
        let importer = Importer(db: db, queue: nil, originals: dir.appending(path: "originals"))
        _ = try await importer.receive(item("ph:A", copying: source))
        #expect(try await importer.receive(item("ph:A", copying: source)) == nil)
        #expect(try await db.writer.read { try VideoRecord.fetchCount($0) } == 1)
    }

    @Test("앱이 내보낸 결과물은 촬영본으로 다시 들이지 않는다 — 방금 보낸 것(메모리) · 이력 둘 다")
    func skipsOwnExports() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 0.5)
        let db = try AppDatabase.inMemory()
        let queue = JobQueue(db: db, handlers: [:])
        let importer = Importer(db: db, queue: queue, originals: dir.appending(path: "originals"))

        // 이력 — 사진 앱으로 보낸 결과물의 식별자
        let comp = Composition(id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                               meta: Composition.Meta(targetDurationSec: 1), captionSlot: .fullBody,
                               scenes: [Scene(id: "s", role: .hook, source: Scene.Source(videoID: "v", start: 0, end: 0.5))])
        try await db.writer.write { try VideoRecord(id: "v", source: .folder, sourceRef: "/x", status: .ready).insert($0) }
        try db.saveComposition(comp)
        try await db.writer.write { db in
            try OutputRecord(id: "o", compositionId: "c", path: source.path, reviewReport: nil, arch: "arm64", createdAt: Date()).insert(db)
            var e = ExportRecord(outputId: "o", target: .photos, location: "ph:OUT/L0/001")
            try e.insert(db)
        }
        #expect(try await importer.receive(item("ph:OUT/L0/001", copying: source)) == nil)

        // 방금 보낸 것 — 이력이 적히기 전에 사진 앱 변경 알림이 먼저 와도 걸러진다
        Exporter.sent.insert("ph:SENT/L0/001")
        defer { Exporter.sent.remove("ph:SENT/L0/001") }
        #expect(try await importer.receive(item("ph:SENT/L0/001", copying: source)) == nil)

        // 입구 폴더에 저장한 것 — 이력의 경로는 NFD, 폴더 감시가 읽는 경로는 NFC 로 온다 (실제 앱에서 이렇게 새어 들어왔다)
        let nfd = "/inbox/배꼽을 쏙.mp4".decomposedStringWithCanonicalMapping
        let nfc = "/inbox/배꼽을 쏙.mp4".precomposedStringWithCanonicalMapping
        #expect(Array(nfd.utf8) != Array(nfc.utf8))
        try await db.writer.write { db in
            var e = ExportRecord(outputId: "o", target: .folder, location: nfd)
            try e.insert(db)
        }
        let folderItem = IncomingVideo(source: .folder, sourceRef: nfc, fileExtension: "mp4", capturedAt: Date()) { dest, _ in
            try FileManager.default.copyItem(at: source, to: dest)
        }
        #expect(try await importer.receive(folderItem) == nil)

        // 촬영본 행도 분석 작업도 생기지 않는다. 다른 영상은 그대로 들어온다
        #expect(try await db.writer.read { try VideoRecord.fetchCount($0) } == 1)
        #expect(try await db.writer.read { try JobRecord.fetchCount($0) } == 0)
        #expect(try await importer.receive(item("ph:SHOT/L0/001", copying: source))?.status == .ready)
    }

    @Test("사진 보관함에 있던 영상 — 목록에만 올린다(복사 · 분석 없음). 아는 영상 · 지운 영상 · 내보낸 결과물은 건너뛴다")
    func listsExistingLibrary() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.inMemory()
        let queue = JobQueue(db: db, handlers: [:])
        let importer = Importer(db: db, queue: queue, originals: dir.appending(path: "originals"))
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        func listed(_ ref: String) -> Importer.Listed {
            Importer.Listed(sourceRef: ref, capturedAt: old, durationSec: 42, width: 1080, height: 1920)
        }
        // 이미 아는 영상 하나 · 지운 영상 하나
        try await db.writer.write { db in
            try VideoRecord(id: "known", source: .photos, sourceRef: "ph:KNOWN", status: .ready).insert(db)
            try VideoRecord(id: "gone", source: .photos, sourceRef: "ph:GONE", status: .listed).insert(db)
            try db.execute(sql: "UPDATE video SET deletedAt = ? WHERE id = 'gone'", arguments: [Date()])
        }
        Exporter.sent.insert("ph:OURS"); defer { Exporter.sent.remove("ph:OURS") }

        let fresh = try await importer.list([listed("ph:A"), listed("ph:B"), listed("ph:KNOWN"), listed("ph:GONE"), listed("ph:OURS")])
        #expect(Set(fresh.map(\.sourceRef)) == ["ph:A", "ph:B"])
        let a = try #require(try await db.writer.read { try VideoRecord.filter(Column("sourceRef") == "ph:A").fetchOne($0) })
        #expect(a.status == .listed && a.localPath == nil && a.durationSec == 42 && a.height == 1920 && a.capturedAt == old)
        #expect(try await db.writer.read { try JobRecord.fetchCount($0) } == 0)             // 분석을 걸지 않는다
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "originals").path))   // 복사도 없다
        // 다시 훑어도 늘지 않는다
        #expect(try await importer.list([listed("ph:A"), listed("ph:B")]).isEmpty)
    }

    @Test("목록에만 있던 영상을 고르면 그때 원본을 받고 분석을 건다 — 받는 동안은 '받는 중'")
    func fetchesListedOnDemand() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 0.5)
        let db = try AppDatabase.inMemory()
        let queue = JobQueue(db: db, handlers: [:])
        let importer = Importer(db: db, queue: queue, originals: dir.appending(path: "originals"))
        _ = try await importer.list([Importer.Listed(sourceRef: "ph:OLD", capturedAt: nil, durationSec: 9, width: 10, height: 10)])

        final class Seen: @unchecked Sendable { var status: VideoRecord.Status? }
        let seen = Seen()
        let item = IncomingVideo(source: .photos, sourceRef: "ph:OLD", fileExtension: "MOV", capturedAt: nil) { dest, _ in
            seen.status = try await db.writer.read { try VideoRecord.filter(Column("sourceRef") == "ph:OLD").fetchOne($0)?.status }
            try FileManager.default.copyItem(at: source, to: dest)
        }
        let v = try #require(try await importer.receive(item))
        #expect(seen.status == .importing)                                  // 받는 동안
        #expect(v.status == .ready && v.localPath != nil)
        #expect(try await db.writer.read { try VideoRecord.fetchCount($0) } == 1)   // 같은 행이다
        #expect(try await db.writer.read { try JobRecord.fetchAll($0) }.map(\.kind) == [.analyze])
    }

    @Test("원본 받기에 실패하면 남기고, 다시 보이면 이어 받는다")
    func retriesFailedFetch() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 0.5)
        let db = try AppDatabase.inMemory()
        let importer = Importer(db: db, queue: nil, originals: dir.appending(path: "originals"))
        let flaky = item("ph:A", copying: source, failTimes: 1)
        let first = try #require(try await importer.receive(flaky))
        #expect(first.status == .failed && first.error != nil)
        let second = try #require(try await importer.receive(flaky))
        #expect(second.status == .ready && second.id == first.id)
    }

    @Test("폴더에 넣은 영상이 저절로 들어온다 — 쓰는 중인 파일은 기다린다")
    func folderWatcherImports() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = dir.appending(path: "inbox")
        let db = try AppDatabase.inMemory()
        let importer = Importer(db: db, queue: nil, originals: dir.appending(path: "originals"))
        let watcher = FolderWatcher(importer: importer, folder: inbox)
        try watcher.start()
        defer { watcher.stop() }

        try await TestVideo.makeSolid(at: dir.appending(path: "clip.mp4"), seconds: 0.5)
        try FileManager.default.moveItem(at: dir.appending(path: "clip.mp4"), to: inbox.appending(path: "clip.mp4"))
        try "메모".write(to: inbox.appending(path: "note.txt"), atomically: true, encoding: .utf8)

        var video: VideoRecord?
        for _ in 0..<50 where video?.status != .ready {
            try await Task.sleep(nanoseconds: 100_000_000)
            video = try await db.writer.read { try VideoRecord.fetchOne($0) }
        }
        #expect(video?.status == .ready)
        #expect(video?.source == .folder)
        #expect(try await db.writer.read { try VideoRecord.fetchCount($0) } == 1)   // .txt 는 무시
    }
}
