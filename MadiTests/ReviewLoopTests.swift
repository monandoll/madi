import Testing
import Foundation
import GRDB
@testable import MadiKit

/// self-eval 루프의 판단 (docs/stage-5.spec.md 3번). 렌더 없이 결과물 행과 리포트만으로.
struct ReviewLoopTests {

    @Test("판단 — 비면 보여 준다, 2회 미만이면 다시, 2회 뒤 하드가 남으면 포기, 소프트만 남으면 보여 준다")
    func decide() {
        #expect(ReviewLoop.decide(items: [], rounds: 0) == .show)
        #expect(ReviewLoop.decide(items: ["G11"], rounds: 0) == .retry)
        #expect(ReviewLoop.decide(items: ["G1"], rounds: 1) == .retry)
        #expect(ReviewLoop.decide(items: ["G11", "G8"], rounds: 2) == .show)
        #expect(ReviewLoop.decide(items: ["G1", "G11"], rounds: 2) == .gaveUp)
        #expect(ReviewLoop.decide(items: ["G4.fullBody"], rounds: 2) == .gaveUp)
    }

    private func setup() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try VideoRecord(id: "v", source: .folder, sourceRef: "/tmp/v.mov", status: .ready).insert($0) }
        return db
    }

    private func comp(_ id: String, revisionOf: String? = nil) -> Composition {
        Composition(id: id, videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                    meta: Composition.Meta(targetDurationSec: 3), captionSlot: .fullBody,
                    scenes: [Scene(id: "s", role: .hook, source: Scene.Source(videoID: "v", start: 0, end: 3))],
                    revisionOf: revisionOf)
    }

    private func output(_ db: AppDatabase, _ compID: String, items: [String]) throws -> OutputRecord {
        let report = String(decoding: try JSONEncoder().encode(["selfEval": JSONValue.array(items.map { .string($0) })]), as: UTF8.self)
        let o = OutputRecord(id: "o_" + compID, compositionId: compID, path: "/tmp/\(compID).mp4", reviewReport: report,
                             arch: "arm64", createdAt: Date(), verdict: .hidden)
        try db.writer.write { try o.insert($0) }
        return o
    }

    private func verdict(_ db: AppDatabase, _ id: String) throws -> OutputRecord.Verdict? {
        try db.writer.read { try OutputRecord.fetchOne($0, key: id)?.verdict }
    }

    final class Box: @unchecked Sendable { var ids: [String] = [] }

    @Test("v3 — 기존 행은 draft · shown, 횟수는 연속된 selfEval 조상")
    func rounds() throws {
        let db = try setup()
        try db.saveComposition(comp("d"))
        try db.saveComposition(comp("r1", revisionOf: "d"), origin: .selfEval)
        try db.saveComposition(comp("r2", revisionOf: "r1"), origin: .selfEval)
        try db.saveComposition(comp("c1", revisionOf: "r2"), origin: .chat)
        let counts = try db.writer.read { db in
            try ["d", "r2", "c1"].map { try ReviewLoop.rounds(db, compositionID: $0) }
        }
        #expect(counts == [0, 2, 0])
    }

    @Test("되먹임 항목이 있으면 숨기고 selfEval 을 건다")
    func retries() async throws {
        let db = try setup()
        try db.saveComposition(comp("d"))
        let box = Box()
        let loop = ReviewLoop(db: db) { box.ids.append($0) }
        #expect(try await loop.afterRender(try output(db, "d", items: ["G11"])) == .retry)
        #expect(box.ids == ["d"])
        #expect(try verdict(db, "o_d") == .hidden)
    }

    @Test("2회 뒤에도 하드가 남으면 — 하드 실패 없는 앞 판이 있으면 그걸 보여 준다")
    func fallsBack() async throws {
        let db = try setup()
        try db.saveComposition(comp("d"))
        try db.saveComposition(comp("r1", revisionOf: "d"), origin: .selfEval)
        try db.saveComposition(comp("r2", revisionOf: "r1"), origin: .selfEval)
        _ = try output(db, "d", items: ["G11"])          // 소프트 때문에 되먹임을 걸었던 판
        _ = try output(db, "r1", items: ["G1"])
        let loop = ReviewLoop(db: db) { _ in Issue.record("3회째는 걸지 않는다") }
        #expect(try await loop.afterRender(try output(db, "r2", items: ["G1"])) == .gaveUp)
        #expect(try verdict(db, "o_d") == .shown)
        #expect(try verdict(db, "o_r2") == .hidden)
    }

    @Test("앞 판도 전부 하드 실패면 끝내 실패 — 보여 주지 않는다")
    func givesUp() async throws {
        let db = try setup()
        try db.saveComposition(comp("d"))
        try db.saveComposition(comp("r1", revisionOf: "d"), origin: .selfEval)
        try db.saveComposition(comp("r2", revisionOf: "r1"), origin: .selfEval)
        _ = try output(db, "d", items: ["G1"])
        _ = try output(db, "r1", items: ["G1"])
        let loop = ReviewLoop(db: db) { _ in }
        #expect(try await loop.afterRender(try output(db, "r2", items: ["G1"])) == .gaveUp)
        #expect(try verdict(db, "o_r2") == .failed)
        #expect(try verdict(db, "o_d") == .hidden)
        let shown = try await db.writer.read { try OutputRecord.filter(Column("verdict") == "shown").fetchCount($0) }
        #expect(shown == 0)
    }
}
