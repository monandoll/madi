import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 결과물을 쓰는 일 — 폴더 저장 · 봤다 · 휴지통 · 보관 기간 (docs/stage-6.spec.md 7번). 사진 앱 보내기는 권한이 필요해 여기서 안 돈다.
struct ExportTests {

    private func setup(_ dir: URL) throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        let file = dir.appending(path: "o.mp4")
        try Data("video".utf8).write(to: file)
        let comp = Composition(id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                               meta: Composition.Meta(targetDurationSec: 3), captionSlot: .fullBody,
                               scenes: [Scene(id: "s", role: .hook, source: Scene.Source(videoID: "v", start: 0, end: 3))])
        try db.writer.write { try VideoRecord(id: "v", source: .folder, sourceRef: "/x", status: .ready).insert($0) }
        try db.saveComposition(comp)
        try db.writer.write { try OutputRecord(id: "o", compositionId: "c", path: file.path, reviewReport: nil, arch: "arm64", createdAt: Date()).insert($0) }
        return db
    }

    private func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test("고른 폴더에 복사하고 이력을 남긴다. 이름이 겹치면 번호를 붙인다")
    func toFolder() async throws {
        let dir = try tmp(), dest = try tmp()
        let db = try setup(dir)
        let a = try await Exporter.toFolder(db, outputID: "o", folder: dest, name: "골반 스트레칭")
        let b = try await Exporter.toFolder(db, outputID: "o", folder: dest, name: "골반 스트레칭")
        #expect(a.lastPathComponent == "골반 스트레칭.mp4" && b.lastPathComponent == "골반 스트레칭 2.mp4")
        #expect(try await db.writer.read { try ExportRecord.fetchCount($0) } == 2)
    }

    @Test("저장 창에서 고른 자리에 저장 — 같은 이름은 바꿔 쓰고(저장 창이 이미 물었다) 이력은 그 경로")
    func toFileReplaces() async throws {
        let dir = try tmp(), dest = try tmp()
        let db = try setup(dir)
        let url = dest.appending(path: "테스트 · 골반 스트레칭.mp4")
        try Data("old".utf8).write(to: url)
        try await Exporter.toFile(db, outputID: "o", url: url)
        #expect(try Data(contentsOf: url) == Data("video".utf8))
        #expect(try await db.writer.read { try ExportRecord.fetchOne($0) }?.location == url.path)
    }

    @Test("내보내는 이름은 '스튜디오 · 제목' — 첫 실행이 약속한 꼴. 경로 글자는 바꾸고, 비면 제목만 · '마디'")
    func fileName() {
        #expect(Exporter.fileName(studio: "수현쌤", title: "골반 스트레칭") == "수현쌤 · 골반 스트레칭")
        #expect(Exporter.fileName(studio: "", title: "a/b:c") == "a-b-c")
        #expect(Exporter.fileName(studio: " ", title: "") == "마디")
    }

    @Test("봤다는 처음 한 번만 적는다 · 휴지통은 파일을 옮기고 행은 남긴다")
    func seenAndTrash() async throws {
        let dir = try tmp()
        let db = try setup(dir)
        let first = Date(timeIntervalSince1970: 1000)
        try await Exporter.markSeen(db, outputID: "o", at: first)
        try await Exporter.markSeen(db, outputID: "o", at: Date())
        #expect(try await db.writer.read { try OutputRecord.fetchOne($0, key: "o") }?.seenAt == first)
        try await Exporter.trash(db, outputID: "o")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "o.mp4").path))
        let row = try #require(try await db.writer.read { try OutputRecord.fetchOne($0, key: "o") })
        #expect(row.trashedAt != nil)
        // 휴지통으로 옮긴 결과물은 스냅숏에서 빠진다
        let snap = try await db.writer.read { try LibrarySnapshot.read($0) }
        #expect(snap.outputs.isEmpty)
    }

    @Test("휴지통으로 보낸 결과물도 '만든 적 있다' — 편집안을 열 때 몰래 다시 만들지 않는다")
    func everMadeCountsTrashed() async throws {
        let dir = try tmp()
        let db = try setup(dir)
        #expect(try db.hasEverMadeOutput(videoID: "v"))
        try await Exporter.trash(db, outputID: "o")
        #expect(try db.hasEverMadeOutput(videoID: "v"))       // 스냅숏에선 빠져도 여기선 센다
        try await db.writer.write { try VideoRecord(id: "w", source: .folder, sourceRef: "/y", status: .ready).insert($0) }
        #expect(try !db.hasEverMadeOutput(videoID: "w"))
    }

    @Test("보관 기간 — 기간이 지난 촬영본의 앱 사본만 지우고, 작업이 걸린 영상은 건너뛴다")
    func retention() async throws {
        let dir = try tmp()
        let db = try AppDatabase.inMemory()
        let old = dir.appending(path: "old.mov"), busy = dir.appending(path: "busy.mov"), fresh = dir.appending(path: "fresh.mov")
        for f in [old, busy, fresh] { try Data("x".utf8).write(to: f) }
        let now = Date()
        try await db.writer.write { db in
            try VideoRecord(id: "old", source: .photos, sourceRef: "a", localPath: old.path, capturedAt: now - 100 * 86400, status: .ready).insert(db)
            try VideoRecord(id: "busy", source: .photos, sourceRef: "b", localPath: busy.path, capturedAt: now - 100 * 86400, status: .ready).insert(db)
            try VideoRecord(id: "fresh", source: .photos, sourceRef: "c", localPath: fresh.path, capturedAt: now - 10 * 86400, status: .ready).insert(db)
            var j = JobRecord(kind: .analyze, targetId: "busy"); try j.insert(db)
        }
        let removed = try await Retention.sweep(db, keepDays: 90, now: now)
        #expect(removed == ["old"])
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: busy.path) && FileManager.default.fileExists(atPath: fresh.path))
        #expect(try await Retention.sweep(db, keepDays: 0, now: now).isEmpty)     // 0 = 계속 둔다
    }
}
