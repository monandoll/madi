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

    @Test("늘리기 — 끝을 1초 늘리고 낱말 경계에 맞춘 뒤 그 장면 자막만 다시 채운다. 글자가 그대로인 덩어리는 영문을 지킨다")
    func extendRefills() throws {
        let c = try apply(.extend(sceneID: "s2", seconds: 1))
        #expect(c.scenes[1].source.end == 5.0)       // 4.0 + 1 — 낱말 안에 떨어지지 않아 그대로
        #expect(c.scenes[1].captions.map(\.text).joined(separator: " ").hasSuffix("다섯."))
        // 새로 들어온 말("다섯.")이 붙어 덩어리가 바뀌었으면 영문이 비고, 그대로인 덩어리는 영문이 남는다
        for cap in c.scenes[1].captions {
            #expect(cap.secondary == (cap.text == "셋 넷" ? "three four" : nil))
        }
        #expect(c.scenes[0].captions[0].secondary == "one two")    // 안 건드린 장면은 그대로
        try validate(c)
    }

    @Test("말 없는 곳으로 늘리면 덩어리 글자가 그대로라 영문도 그대로 — 1초 늘렸다고 영문이 사라지지 않는다")
    func extendKeepsEnglish() throws {
        let c = try apply(.extend(sceneID: "s1", seconds: 1))     // 1.0 → 2.0, 뒤 낱말은 3.0 부터
        #expect(c.scenes[0].source.end > 1.0)
        #expect(c.scenes[0].captions.map(\.text) == ["하나 둘"])
        #expect(c.scenes[0].captions.first?.secondary == "one two")
    }

    @Test("늘리기는 다른 장면이 쓰는 원본에서 멈춘다 — 같은 말이 두 장면에 두 번 나오지 않는다")
    func extendStopsAtNextScene() throws {
        let c = try apply(.extend(sceneID: "s1", seconds: 5))     // 1.0 + 5 → 뒤 장면(3.0~)에서 멈춘다
        #expect(c.scenes[0].source.end <= 3.0)
        #expect(!c.scenes[0].captions.map(\.text).joined().contains("셋"))
        // 이미 붙어 있으면 늘릴 것이 없다
        var touching = comp()
        touching.scenes[0].source.end = 3.0
        #expect(throws: SceneEdits.Failure.noChange) {
            try SceneEdits.apply(.extend(sceneID: "s1", seconds: 1), to: touching, newID: "n", words: words,
                                 style: try StyleStore.load().values.caption, sourceDuration: 10)
        }
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
        // 영문을 주지 않으면(카드) 영문은 그대로 — 전에는 지워졌다
        let c = try apply(.editCaption(sceneID: "s1", text: "하나 두울", secondary: nil))
        #expect(c.scenes[0].captions[0].text == "하나 두울" && c.scenes[0].captions[0].secondary == "one two")
        let e = try apply(.editCaption(sceneID: "s1", text: "하나 둘", secondary: "one, two"))
        #expect(e.scenes[0].captions[0].secondary == "one, two")
    }

    @Test("바뀌는 것이 없으면 새 편집안을 만들지 않는다 — 끝에 닿은 장면 늘리기 · 제자리 옮기기 · 같은 자막 · 뒤에 틈 없음")
    func noChange() throws {
        // 원본 끝(10초)에 닿은 장면. 끝이 원본보다 조금 넘어 있어도(10.08 — 실제 앱 60.08/60.00) 줄여서 새 판을 만들지 않는다
        for end in [10.0, 10.08] {
            var c = comp()
            c.scenes[1].source.end = end
            #expect(throws: SceneEdits.Failure.noChange) {
                try SceneEdits.apply(.extend(sceneID: "s2", seconds: 1), to: c, newID: "n", words: words,
                                     style: try StyleStore.load().values.caption, sourceDuration: 10)
            }
        }
        #expect(throws: SceneEdits.Failure.noChange) { try apply(.move(from: IndexSet(integer: 0), to: 0)) }
        #expect(throws: SceneEdits.Failure.noChange) { try apply(.move(from: IndexSet(integer: 0), to: 1)) }
        #expect(throws: SceneEdits.Failure.noChange) { try apply(.editCaption(sceneID: "s1", text: "하나 둘", secondary: "one two")) }
        #expect(throws: SceneEdits.Failure.noChange) { try apply(.restoreGap(sceneID: "s2")) }   // 마지막 장면 — 뒤에 틈이 없다
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
