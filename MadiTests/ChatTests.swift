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
                    let a = request.mcp.arguments
                    let id = a[a.firstIndex(of: "--composition")! + 1]
                    let rev = a[a.firstIndex(of: "--revision-of")! + 1]
                    do { try db.saveComposition(self.comp(id, target: 5, revisionOf: rev), origin: .chat) } catch { c.finish(throwing: error); return }
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

    @Test("'앞으로도?' 에 예면 규칙이 되고, 다음 턴 프롬프트 4번 칸에 들어간다. 아니오면 적지 않는다")
    func remembers() async throws {
        let db = try setup()
        let box = Box()
        let job = agent(db, box)
        let first = try await Chat.send(db: db, videoID: "v1", text: "자막은 짧게", viewing: "d") { _ in }
        try await job.chat(messageID: first.id)
        let ask = try #require(try await db.writer.read { try ChatRecord.filter(Column("kind") == "choices").fetchOne($0) })
        try await Chat.answerRemember(db: db, choicesID: ask.id, yes: true)
        #expect(try db.userRules() == ["자막은 짧게"])

        let second = try await Chat.send(db: db, videoID: "v1", text: "훅을 바꿔 줘", viewing: nil) { _ in }
        try await job.chat(messageID: second.id)
        #expect(box.prompts[1].contains("- 자막은 짧게"))
        #expect(box.prompts[1].contains("크리에이터: 자막은 짧게\n너: 30초로 줄였어요."))   // 대화 이력

        let ask2 = try #require(try await db.writer.read { try ChatRecord.filter(Column("kind") == "choices").order(Column("createdAt").desc).fetchOne($0) })
        try await Chat.answerRemember(db: db, choicesID: ask2.id, yes: false)
        #expect(try db.userRules() == ["자막은 짧게"])
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
