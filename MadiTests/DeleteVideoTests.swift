import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 촬영본 삭제 (UIAction.gallery(.delete)). 앱 사본 · 편집안 · 결과물 · 분석 · 채팅을 지우고, 다시 들이지 않는다.
struct DeleteVideoTests {

    private func comp(_ id: String, revisionOf: String? = nil) -> Composition {
        Composition(id: id, videoID: "v1", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                    meta: Composition.Meta(targetDurationSec: 5), captionSlot: .fullBody,
                    scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v1", start: 0, end: 5))],
                    revisionOf: revisionOf)
    }

    @Test("편집안 사슬 · 결과물 · 내보낸 이력 · 채팅 · 줄 선 작업이 지워지고, 영상 행은 삭제 표시로 남는다. 지울 파일을 돌려준다")
    func deletesEverything() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try VideoRecord(id: "v1", source: .photos, sourceRef: "ph:1", localPath: "/tmp/orig/v1.mov",
                            durationSec: 10, status: .ready).insert(db)
            try VideoRecord(id: "v2", source: .photos, sourceRef: "ph:2", status: .ready).insert(db)
        }
        try db.saveComposition(comp("d"))
        try db.saveComposition(comp("r1", revisionOf: "d"), origin: .chat)
        try db.writer.write { db in
            try OutputRecord(id: "o1", compositionId: "r1", path: "/tmp/out/o1.mp4", reviewReport: nil, arch: "arm64", createdAt: Date()).insert(db)
            try db.execute(sql: "INSERT INTO export (outputId, target, createdAt) VALUES ('o1', 'photos', ?)", arguments: [Date()])
            try ChatRecord(videoId: "v1", kind: .creator, text: "줄여 줘").insert(db)
            var render = JobRecord(kind: .render, targetId: "r1"); try render.insert(db)
            var other = JobRecord(kind: .analyze, targetId: "v2"); try other.insert(db)
        }

        let files = try db.deleteVideo("v1", analysisRoot: URL(fileURLWithPath: "/tmp/analysis"))
        #expect(Set(files.map(\.path)) == ["/tmp/out/o1.mp4", "/tmp/orig/v1.mov", "/tmp/analysis/v1"])

        try db.writer.read { db in
            #expect(try CompositionRecord.fetchCount(db) == 0)
            #expect(try OutputRecord.fetchCount(db) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM export") == 0)
            #expect(try ChatRecord.fetchCount(db) == 0)
            #expect(try JobRecord.fetchAll(db).map(\.targetId) == ["v2"])     // 다른 영상 작업은 그대로
            let v = try #require(try VideoRecord.fetchOne(db, key: "v1"))
            #expect(v.deletedAt != nil && v.localPath == nil)
        }
    }

    @Test("지운 영상은 사진 보관함 · 폴더에서 다시 보여도 들이지 않는다")
    func doesNotReimport() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try VideoRecord(id: "v1", source: .photos, sourceRef: "ph:1", status: .ready).insert($0) }
        try db.deleteVideo("v1", analysisRoot: URL(fileURLWithPath: "/tmp/analysis"))
        let importer = Importer(db: db, queue: nil, originals: FileManager.default.temporaryDirectory)
        let item = IncomingVideo(source: .photos, sourceRef: "ph:1", fileExtension: "MOV", capturedAt: Date()) { _, _ in
            Issue.record("지운 영상을 다시 받으면 안 된다")
        }
        #expect(try await importer.receive(item) == nil)
        #expect(try await db.writer.read { try VideoRecord.fetchCount($0) } == 1)
    }
}
