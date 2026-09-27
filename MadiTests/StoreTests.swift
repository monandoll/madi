import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 저장소 v1. 원칙 몇 개는 DB 가 직접 막는지 본다 (코드 약속이 아니라).
struct StoreTests {

    private func video(_ db: AppDatabase, ref: String = "ph:1") throws -> VideoRecord {
        let v = VideoRecord(source: .photos, sourceRef: ref, status: .ready)
        try db.writer.write { try v.insert($0) }
        return v
    }

    private func comp(_ id: String, video: String, revisionOf: String? = nil) -> Composition {
        Composition(
            id: id, videoID: video, templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 10), captionSlot: .upperBody,
            scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: video, start: 0, end: 3),
                           captions: [Caption(id: "c", start: 0, end: 1, text: "어깨가")])],
            revisionOf: revisionOf
        )
    }

    @Test("빈 DB 에 마이그레이션이 되고 편집안이 왕복한다")
    func migratesAndRoundTrips() throws {
        let db = try AppDatabase.inMemory()
        let v = try video(db)
        try db.saveComposition(comp("c1", video: v.id))
        let back = try db.writer.read { try CompositionRecord.fetchOne($0, key: "c1") }
        let c = try #require(back).composition()
        #expect(c.style == StyleRef(id: "short.v1", version: 1))
        #expect(c.scenes[0].captions[0].text == "어깨가")
    }

    @Test("같은 원본을 두 번 들이지 않는다")
    func rejectsDuplicateSource() throws {
        let db = try AppDatabase.inMemory()
        _ = try video(db, ref: "ph:same")
        #expect(throws: (any Error).self) { _ = try video(db, ref: "ph:same") }
    }

    @Test("검증을 통과하지 못한 편집안은 저장되지 않는다")
    func rejectsInvalidComposition() throws {
        let db = try AppDatabase.inMemory()
        let v = try video(db)
        var bad = comp("c1", video: v.id)
        bad.scenes[0].overlays = [Overlay(id: "o", kind: .mark, start: 0, end: 1,
                                         anchor: NormPoint(x: 0.5, y: 0.5), payload: ["color": .string("red")])]
        #expect(throws: (any Error).self) { try db.saveComposition(bad) }
        #expect(try db.writer.read { try CompositionRecord.fetchCount($0) } == 0)
    }

    @Test("결과물이 있는 편집안은 제자리에서 고칠 수 없다 — DB 가 막는다")
    func freezesCompositionWithOutput() throws {
        let db = try AppDatabase.inMemory()
        let v = try video(db)
        try db.saveComposition(comp("c1", video: v.id))
        try db.writer.write { db in
            try OutputRecord(id: "o1", compositionId: "c1", path: "/tmp/o.mp4", reviewReport: nil,
                             arch: MachineArch.current, createdAt: Date()).insert(db)
        }
        // 리포지토리를 거치지 않는 SQL 도 막혀야 한다.
        #expect(throws: DatabaseError.self) {
            try db.writer.write { try $0.execute(sql: "UPDATE composition SET json = '{}' WHERE id = 'c1'") }
        }
        // 고치는 길은 새 편집안이다.
        try db.saveComposition(comp("c2", video: v.id, revisionOf: "c1"))
        #expect(try db.writer.read { try CompositionRecord.fetchOne($0, key: "c2") }?.revisionOf == "c1")
    }

    @Test("결과물은 편집안 없이 존재할 수 없다")
    func outputNeedsComposition() throws {
        let db = try AppDatabase.inMemory()
        #expect(throws: DatabaseError.self) {
            try db.writer.write { db in
                try OutputRecord(id: "o1", compositionId: "없음", path: "/tmp/o.mp4", reviewReport: nil,
                                 arch: MachineArch.current, createdAt: Date()).insert(db)
            }
        }
    }

    @Test("같은 대상에 같은 종류의 살아 있는 작업은 하나뿐이다")
    func oneLiveJobPerTarget() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            var a = JobRecord(kind: .analyze, targetId: "v1")
            try a.insert(db)
            var b = JobRecord(kind: .analyze, targetId: "v1")
            #expect(throws: DatabaseError.self) { try b.insert(db) }
            // 끝난 작업이 있으면 다시 걸 수 있다.
            a.state = .done
            try a.update(db)
            try b.insert(db)
        }
    }

    @Test("이벤트에 아키텍처가 남는다")
    func eventsRecordArch() throws {
        let db = try AppDatabase.inMemory()
        try db.log("render.done", subject: "c1", payload: ["seconds": .number(12.5)])
        let e = try #require(try db.writer.read { try EventRecord.fetchOne($0) })
        #expect(["arm64", "x86_64"].contains(e.arch))
        #expect(e.payload?.contains("12.5") == true)
    }
}
