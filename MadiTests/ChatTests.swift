import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 채팅 수정 (docs/stage-6.spec.md 5번 · AGENTS.md §10). AI 는 가짜 턴.
struct ChatTests {

    private func comp(_ id: String, target: Double = 10, revisionOf: String? = nil) -> Composition {
        Composition(id: id, videoID: "v1", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                    meta: Composition.Meta(targetDurationSec: target), captionSlot: .fullBody,
                    scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v1", start: 0, end: target))],
                    revisionOf: revisionOf)
    }

    private func setup() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: "/tmp/v1", durationSec: 60, status: .ready).insert($0) }
        try db.saveComposition(comp("d"))
        return db
    }

    final class Box: @unchecked Sendable { var prompts: [String] = []; var renders: [String] = []; var args: [[String]] = [] }

    private func agent(_ db: AppDatabase, _ box: Box, fail: Bool = false) -> AgentJob {
        AgentJob(
            db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"),
            choose: { .init(kind: .claude, executable: URL(fileURLWithPath: "/x/claude"), version: nil) },
            userRules: { (try? db.userRules()) ?? [] },
            workRoot: FileManager.default.temporaryDirectory.appending(path: "chat-\(UUID().uuidString)"),
            turn: { _, request in
                AsyncThrowingStream { c in
                    box.prompts.append(request.prompt)
                    box.args.append(request.mcp.arguments)
                    if fail { c.yield(.finished(AgentOutcome(isError: true, message: "한도"))); c.finish(); return }
                    // 질문 — 편집안 없이 답만 (playbook · Chat.request)
                    if request.prompt.contains("크리에이터: [질문]") {
                        c.yield(.text("헬스장에서 찍은 스쿼트 영상이에요."))
                        c.yield(.finished(AgentOutcome(isError: false))); c.finish(); return
                    }
                    let a = request.mcp.arguments
                    let id = a[a.firstIndex(of: "--composition")! + 1]
                    let rev = a[a.firstIndex(of: "--revision-of")! + 1]
                    do {
                        try db.saveComposition(self.comp(id, target: 5, revisionOf: rev), origin: .chat)
                        // madi-mcp 가 하는 일 — 일반 규칙 제안을 이벤트로 (프롬프트에 "[이번만]" 이 있으면 제안하지 않는다)
                        if !request.prompt.contains("[이번만]") {
                            try db.log("agent.rule.proposed", subject: id, payload: ["rule": .string("영상은 15초 안팎으로")])
                        }
                    } catch { c.finish(throwing: error); return }
                    c.yield(.text("30초로 줄였어요."))
                    c.yield(.finished(AgentOutcome(isError: false)))
                    c.finish()
                }
            },
            makeCompositionID: { _ in "c\(UUID().uuidString.prefix(4))" },
            onDraft: { box.renders.append($0) }
        )
    }

    @Test("보낸 말 → 새 편집안(origin chat · revisionOf 보고 있던 판) → 렌더 → AI 말 · '앞으로도?' 선택지")
    func edits() async throws {
        let db = try setup()
        let box = Box()
        let job = agent(db, box)
        let sent = try await Chat.send(db: db, videoID: "v1", text: "30초로 줄여 줘", viewing: "d") { _ in }
        try await job.chat(messageID: sent.id)

        let (comps, rows) = try await db.writer.read { db in
            (try CompositionRecord.filter(Column("origin") == "chat").fetchAll(db),
             try ChatRecord.order(Column("createdAt")).fetchAll(db))
        }
        #expect(comps.count == 1 && comps[0].revisionOf == "d")
        #expect(box.renders == [comps[0].id])
        #expect(box.args[0].contains("--origin") && box.args[0].contains("chat"))
        #expect(box.prompts[0].contains("크리에이터: 30초로 줄여 줘"))
        #expect(rows.map(\.kind) == [.creator, .assistant, .choices])
        #expect(rows[1].text == "30초로 줄였어요." && rows[1].compositionId == comps[0].id)
        #expect(rows[2].payloadValues["ask"] == .string(Chat.Key.askRemember))
    }

    @Test("'앞으로도?' 에 예면 AI 가 다듬은 일반 문장이 규칙이 되고, 다음 턴 프롬프트 4번 칸에 들어간다. 아니오면 적지 않는다")
    func remembers() async throws {
        let db = try setup()
        let box = Box()
        let job = agent(db, box)
        let first = try await Chat.send(db: db, videoID: "v1", text: "자막은 짧게", viewing: "d") { _ in }
        try await job.chat(messageID: first.id)
        let ask = try #require(try await db.writer.read { try ChatRecord.filter(Column("kind") == "choices").fetchOne($0) })
        try await Chat.answerRemember(db: db, choicesID: ask.id, yes: true)
        #expect(try db.userRules() == ["영상은 15초 안팎으로"])     // 크리에이터 말이 아니라 AI 가 다듬은 일반 문장

        let second = try await Chat.send(db: db, videoID: "v1", text: "훅을 바꿔 줘", viewing: nil) { _ in }
        try await job.chat(messageID: second.id)
        #expect(box.prompts[1].contains("- 영상은 15초 안팎으로"))
        #expect(box.prompts[1].contains("크리에이터: 자막은 짧게\n너: 30초로 줄였어요."))   // 대화 이력

        let ask2 = try #require(try await db.writer.read { try ChatRecord.filter(Column("kind") == "choices").order(Column("createdAt").desc).fetchOne($0) })
        try await Chat.answerRemember(db: db, choicesID: ask2.id, yes: false)
        #expect(try db.userRules() == ["영상은 15초 안팎으로"])
    }

    @Test("질문에는 답만 한다 — 새 편집안 · 렌더 · '앞으로도?' 없이 AI 말 한 줄")
    func answersQuestion() async throws {
        let db = try setup()
        let box = Box()
        let sent = try await Chat.send(db: db, videoID: "v1", text: "[질문] 무슨 영상이야?", viewing: "d") { _ in }
        try await agent(db, box).chat(messageID: sent.id)
        let (comps, rows) = try await db.writer.read { db in
            (try CompositionRecord.filter(Column("origin") == "chat").fetchCount(db),
             try ChatRecord.order(Column("createdAt")).fetchAll(db))
        }
        #expect(comps == 0 && box.renders.isEmpty)
        #expect(rows.map(\.kind) == [.creator, .assistant])
        #expect(rows[1].text == "헬스장에서 찍은 스쿼트 영상이에요." && rows[1].compositionId == nil)
    }

    @Test("일반화할 게 없으면 묻지 않는다 (AI 가 rule 을 비움)")
    func noAskWithoutRule() async throws {
        let db = try setup()
        let sent = try await Chat.send(db: db, videoID: "v1", text: "[이번만] 3번 장면 빼 줘", viewing: "d") { _ in }
        try await agent(db, Box()).chat(messageID: sent.id)
        let kinds = try await db.writer.read { try ChatRecord.fetchAll($0).map(\.kind) }
        #expect(kinds == [.creator, .assistant])
    }

    @Test("수정 턴이 실패하면 알림 줄(문구 키)을 남기고 작업은 실패한다")
    func failure() async throws {
        let db = try setup()
        let sent = try await Chat.send(db: db, videoID: "v1", text: "줄여 줘", viewing: "d") { _ in }
        await #expect(throws: (any Error).self) { try await agent(db, Box(), fail: true).chat(messageID: sent.id) }
        let notice = try #require(try await db.writer.read { try ChatRecord.filter(Column("kind") == "notice").fetchOne($0) })
        #expect(notice.payloadValues["key"] == .string(Chat.Key.aiDraftFailed))
    }

    @Test("보내지 못하면 쓴 말을 지우지 않고 creatorNotSent 로 남긴다")
    func notSent() async throws {
        let db = try setup()
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await Chat.send(db: db, videoID: "v1", text: "남아야 한다", viewing: "d") { _ in throw Boom() }
        }
        let row = try #require(try await db.writer.read { try ChatRecord.fetchOne($0) })
        #expect(row.kind == .creatorNotSent && row.text == "남아야 한다")
    }
}
