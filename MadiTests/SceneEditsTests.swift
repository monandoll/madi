import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 사람이 장면 카드에서 고친 것 (docs/stage-6.spec.md — 행동 연결).
struct SceneEditsTests {

    let words: [Word] = [
        Word(text: "하나", start: 0.1, end: 0.6), Word(text: "둘", start: 0.6, end: 1.0),
        Word(text: "셋", start: 3.0, end: 3.5), Word(text: "넷", start: 3.5, end: 4.0), Word(text: "다섯.", start: 4.0, end: 4.6),
    ]

    func comp() -> Composition {
        Composition(
            id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 3), captionSlot: .fullBody,
            scenes: [
                Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v", start: 0.1, end: 1.0),
                      captions: [Caption(id: "s1-c1", start: 0, end: 0.9, text: "하나 둘", secondary: "one two")]),
                Scene(id: "s2", role: .demo, source: Scene.Source(videoID: "v", start: 3.0, end: 4.0),
                      captions: [Caption(id: "s2-c1", start: 0, end: 1.0, text: "셋 넷", secondary: "three four")]),
            ]
        )
    }

    func apply(_ e: SceneEdit) throws -> Composition {
        try SceneEdits.apply(e, to: comp(), newID: "n", words: words, style: try StyleStore.load().values.caption, sourceDuration: 10)
    }

    @Test("새 편집안이다 — id · revisionOf")
    func newVersion() throws {
        let c = try apply(.remove(sceneID: "s2"))
        #expect(c.id == "n" && c.revisionOf == "c" && c.scenes.map(\.id) == ["s1"])
        #expect(throws: SceneEdits.Failure.lastScene) { try SceneEdits.apply(.remove(sceneID: "s1"), to: c, newID: "m", words: words, style: try StyleStore.load().values.caption, sourceDuration: 10) }
    }

    @Test("늘리기 — 끝을 1초 늘리고 낱말 경계에 맞춘 뒤 그 장면 자막만 다시 채운다 (영문은 비운다)")
    func extendRefills() throws {
        let c = try apply(.extend(sceneID: "s2", seconds: 1))
        #expect(c.scenes[1].source.end == 5.0)       // 4.0 + 1 — 낱말 안에 떨어지지 않아 그대로
        #expect(c.scenes[1].captions.map(\.text).joined(separator: " ").hasSuffix("다섯."))
        #expect(c.scenes[1].captions.allSatisfy { $0.secondary == nil })
        #expect(c.scenes[0].captions[0].secondary == "one two")    // 안 건드린 장면은 그대로
        try validate(c)
    }

    @Test("줄이기 — 너무 짧아지면 거절")
    func shorten() throws {
        #expect(throws: SceneEdits.Failure.tooShort) { try apply(.shorten(sceneID: "s1", seconds: 0.8)) }
        let c = try apply(.shorten(sceneID: "s2", seconds: 0.5))
        #expect(c.scenes[1].source.end == 3.5)
    }

    @Test("쉬는 구간 되살리기 — 끝을 다음 장면 시작까지")
    func restoreGap() throws {
        let c = try apply(.restoreGap(sceneID: "s1"))
        #expect(c.scenes[0].source.end == 3.0)
    }

    @Test("순서 바꾸기 · 자막 고치기")
    func moveAndCaption() throws {
        #expect(try apply(.move(from: IndexSet(integer: 1), to: 0)).scenes.map(\.id) == ["s2", "s1"])
        let c = try apply(.editCaption(sceneID: "s1", text: "하나 두울", secondary: nil))
        #expect(c.scenes[0].captions[0].text == "하나 두울" && c.scenes[0].captions[0].secondary == nil)
    }

    @Test("멈추기 — 줄 선 작업만 멈춘다")
    func cancelQueued() async throws {
        let db = try AppDatabase.inMemory()
        let queue = JobQueue(db: db, handlers: [:])
        try await db.writer.write { db in var j = JobRecord(kind: .agent, targetId: "v"); try j.insert(db) }
        #expect(try await queue.cancel(targetIds: ["v"]) == 1)
        let job = try #require(try await db.writer.read { try JobRecord.fetchOne($0) })
        #expect(job.state == .failed && job.error == "멈춤")
    }
}
