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
        // 쓴 말은 "보내지 못함" — 화면에 "다시 보내기" 가 붙는다 (알림이 다시 보내 달라고 한다)
        let mine = try #require(try await db.writer.read { try ChatRecord.fetchOne($0, key: sent.id) })
        #expect(mine.kind == .creatorNotSent && mine.text == "줄여 줘")
    }

    @Test("멈추기로 끊긴 수정 턴도 알림을 남기고 쓴 말은 '보내지 못함' — 취소된 작업 안에서도 적힌다")
    func cancelledTurnLeavesRetry() async throws {
        let db = try setup()
        let sent = try await Chat.send(db: db, videoID: "v1", text: "끝에 한 문장", viewing: "d") { _ in }
        let job = AgentJob(
            db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"),
            choose: { .init(kind: .claude, executable: URL(fileURLWithPath: "/x/claude"), version: nil) },
            userRules: { [] },
            workRoot: FileManager.default.temporaryDirectory.appending(path: "chat-\(UUID().uuidString)"),
            turn: { _, _ in
                AsyncThrowingStream { c in
                    Task { try? await Task.sleep(for: .seconds(30)); c.finish() }   // 끝나지 않는 턴
                }
            },
            makeCompositionID: { _ in "cX" },
            onDraft: { _ in }
        )
        let task = Task { try await job.chat(messageID: sent.id) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = await task.result
        let rows = try await db.writer.read { try ChatRecord.fetchAll($0) }
        #expect(rows.contains { $0.kind == .notice && $0.payloadValues["key"] == .string(Chat.Key.aiDraftFailed) })
        #expect(rows.first { $0.id == sent.id }?.kind == .creatorNotSent)
    }

    // MARK: 첫 요청 — 편집안이 아직 없을 때 (2026-10-01: 요구 없이 만들지 않는다)

    private func emptyShot() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: "/tmp/v1", durationSec: 60, status: .ready).insert($0) }
        return db
    }

    /// 첫 초안 턴의 가짜 AI — 편집안을 저장하고 한마디 한다. `question` 이면 답만 한다.
    private func drafter(_ db: AppDatabase, _ box: Box, fail: Bool = false, question: Bool = false) -> AgentJob {
        AgentJob(
            db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"),
            choose: { .init(kind: .claude, executable: URL(fileURLWithPath: "/x/claude"), version: nil) },
            userRules: { [] },
            workRoot: FileManager.default.temporaryDirectory.appending(path: "chat-\(UUID().uuidString)"),
            turn: { _, request in
                AsyncThrowingStream { c in
                    box.prompts.append(request.prompt)
                    if fail { c.yield(.finished(AgentOutcome(isError: true, message: "한도"))); c.finish(); return }
                    if question { c.yield(.text("어깨 스트레칭 영상이에요.")); c.yield(.finished(AgentOutcome(isError: false))); c.finish(); return }
                    let a = request.mcp.arguments
                    do { try db.saveComposition(self.comp(a[a.firstIndex(of: "--composition")! + 1])) } catch { c.finish(throwing: error); return }
                    c.yield(.text("어깨 부분으로 만들었어요."))
                    c.yield(.finished(AgentOutcome(isError: false)))
                    c.finish()
                }
            },
            makeCompositionID: { _ in "draft1" },
            onDraft: { box.renders.append($0) }
        )
    }

    @Test("첫 요청 — 분석이 끝났으면 AI 초안, 아니면 분석부터 건다. 남은 말이 '아직 답하지 않은 요청' 이다")
    func firstRequestEnqueues() async throws {
        let db = try emptyShot()
        final class Kinds: @unchecked Sendable { var v: [JobRecord.Kind] = [] }
        let kinds = Kinds()
        #expect(try db.pendingDraftRequest(videoID: "v1").isEmpty)          // 넣기만 했다 — 요청 없음
        try await Chat.sendFirstRequest(db: db, videoID: "v1", text: "어깨 부분만 20초로") { k, _ in kinds.v.append(k) }
        #expect(kinds.v == [.analyze])                                       // 분석 전 — 분석부터
        #expect(try db.pendingDraftRequest(videoID: "v1").map(\.text) == ["어깨 부분만 20초로"])

        // AI 가 답한 뒤(질문에 답만)에는 기다리는 요청이 없다
        try await db.writer.write { try ChatRecord(videoId: "v1", kind: .assistant, text: "답").insert($0) }
        #expect(try db.pendingDraftRequest(videoID: "v1").isEmpty)
    }

    @Test("원본을 아직 안 받은 영상(사진 보관함에 있던 것)에 요청하면 말만 남긴다 — 분석은 원본이 온 뒤 가져오기가 건다")
    func firstRequestWaitsForOriginal() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try VideoRecord(id: "v1", source: .photos, sourceRef: "ph:OLD", status: .importing).insert($0) }
        final class Kinds: @unchecked Sendable { var v: [JobRecord.Kind] = [] }
        let kinds = Kinds()
        try await Chat.sendFirstRequest(db: db, videoID: "v1", text: "알아서 만들어줘") { k, _ in kinds.v.append(k) }
        #expect(kinds.v.isEmpty)
        #expect(try db.pendingDraftRequest(videoID: "v1").count == 1)
    }

    @Test("첫 초안 턴 — 크리에이터 말이 요청 칸에 들어가고, AI 말이 그 편집안과 함께 대화에 남는다")
    func firstDraftUsesRequest() async throws {
        let db = try emptyShot()
        let box = Box()
        try await Chat.sendFirstRequest(db: db, videoID: "v1", text: "어깨 부분만 20초로") { _, _ in }
        try await drafter(db, box).run(videoID: "v1")
        #expect(box.prompts.first?.contains("크리에이터: 어깨 부분만 20초로") == true)
        #expect(box.prompts.first?.contains("크리에이터: 크리에이터:") == false)
        let rows = try await db.writer.read { try ChatRecord.order(Column("createdAt")).fetchAll($0) }
        #expect(rows.map(\.kind) == [.creator, .assistant])
        #expect(rows.last?.compositionId == "draft1" && rows.last?.text == "어깨 부분으로 만들었어요.")
        #expect(box.renders == ["draft1"])                                   // 초안이 나오면 렌더가 걸린다
    }

    @Test("첫 요청이 질문이면 답만 한다 — 편집안 없음 · 다시 묻는 상태")
    func firstQuestionAnswersOnly() async throws {
        let db = try emptyShot()
        try await Chat.sendFirstRequest(db: db, videoID: "v1", text: "이거 무슨 영상이야?") { _, _ in }
        try await drafter(db, Box(), question: true).run(videoID: "v1")
        #expect(try await db.writer.read { try CompositionRecord.fetchCount($0) } == 0)
        #expect(try db.pendingDraftRequest(videoID: "v1").isEmpty)
        let last = try #require(try await db.writer.read { try ChatRecord.order(Column("createdAt").desc).fetchOne($0) })
        #expect(last.kind == .assistant && last.compositionId == nil)
    }

    @Test("첫 초안이 막히면 쓴 말은 '보내지 못함' + 알림 — 요청은 더 기다리지 않는다 (다시 보내기를 눌러야 다시 한다)")
    func firstDraftFailure() async throws {
        let db = try emptyShot()
        let sent = try await Chat.sendFirstRequest(db: db, videoID: "v1", text: "알아서 만들어줘") { _, _ in }
        await #expect(throws: (any Error).self) { try await drafter(db, Box(), fail: true).run(videoID: "v1") }
        #expect(try await db.writer.read { try ChatRecord.fetchOne($0, key: sent.id) }?.kind == .creatorNotSent)
        #expect(try db.pendingDraftRequest(videoID: "v1").isEmpty)
    }

    @Test("요청이 없으면 전처럼 '이 영상으로 초안' (판정 도구 · 다시 해 보기) — 대화에 아무것도 안 남긴다")
    func draftWithoutRequest() async throws {
        let db = try emptyShot()
        let box = Box()
        try await drafter(db, box).run(videoID: "v1")
        #expect(box.prompts.first?.contains("크리에이터: \(PromptAssembler.firstDraftRequest)") == true)
        #expect(try await db.writer.read { try ChatRecord.fetchCount($0) } == 0)
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
