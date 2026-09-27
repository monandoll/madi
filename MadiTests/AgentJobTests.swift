import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 분석 → AI 한 턴 → 초안 (docs/stage-4.spec.md 5번). CLI 는 가짜 턴으로 바꿔 끼운다.
struct AgentJobTests {

    private func setup() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: "/tmp/v1.mov", durationSec: 20, status: .ready).insert($0) }
        return db
    }

    private let claude = AgentJob.Choice(kind: .claude, executable: URL(fileURLWithPath: "/opt/homebrew/bin/claude"), version: "2.1.283")

    /// write_composition 을 부른 것처럼 초안을 저장하고 끝을 알리는 가짜 턴.
    private func savingTurn(_ db: AppDatabase) -> AgentJob.Turn {
        { _, request in
            AsyncThrowingStream { c in
                let args = request.mcp.arguments
                let id = args[args.firstIndex(of: "--composition")! + 1]
                let comp = Composition(
                    id: id, videoID: "v1", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                    meta: Composition.Meta(targetDurationSec: 5), captionSlot: .fullBody,
                    scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v1", start: 0, end: 3))]
                )
                do { try db.saveComposition(comp) } catch { c.finish(throwing: error); return }
                c.yield(.started(model: "claude-opus-5-5", tools: MadiToolNames.claude))
                c.yield(.text("훅을 앞으로 가져왔어요."))
                c.yield(.finished(AgentOutcome(isError: false, message: "훅을 앞으로 가져왔어요.", model: "claude-opus-5-5")))
                c.finish()
            }
        }
    }

    private func events(_ db: AppDatabase, _ kind: String) throws -> [EventRecord] {
        try db.writer.read { try EventRecord.filter(Column("kind") == kind).fetchAll($0) }
    }

    @Test("v2 마이그레이션 — agent 작업을 받는다")
    func migration() throws {
        let db = try setup()
        try db.writer.write { var j = JobRecord(kind: .agent, targetId: "v1"); try j.insert($0) }
        #expect(try db.writer.read { try JobRecord.filter(Column("kind") == "agent").fetchCount($0) } == 1)
    }

    @Test("AI 고르기 — 설정값, 없으면 연결된 쪽(둘 다면 Claude), 설정한 쪽이 안 되면 다른 쪽으로 몰래 바꾸지 않는다")
    func choosing() async {
        let exe = URL(fileURLWithPath: "/x")
        let both: @Sendable (AgentKind) async -> AgentConnection = { _ in .ready(executable: exe, version: nil) }
        let codexOnly: @Sendable (AgentKind) async -> AgentConnection = { $0 == .codex ? .ready(executable: exe, version: nil) : .notInstalled }
        #expect(await AgentJob.defaultChoice(preferred: nil, connection: both)?.kind == .claude)
        #expect(await AgentJob.defaultChoice(preferred: .codex, connection: both)?.kind == .codex)
        #expect(await AgentJob.defaultChoice(preferred: nil, connection: codexOnly)?.kind == .codex)
        #expect(await AgentJob.defaultChoice(preferred: .claude, connection: codexOnly) == nil)
        // 설정의 "연결 끊기" — 연결돼 있어도 쓰지 않는다
        #expect(await AgentJob.defaultChoice(preferred: nil, disabled: true, connection: both) == nil)
    }

    @Test("AI 가 연결돼 있지 않으면 스폰하지 않고 이벤트만 남긴다 — 실패가 아니다")
    func notConnected() async throws {
        let db = try setup()
        let job = AgentJob(db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"), choose: { nil },
                           turn: { _, _ in Issue.record("스폰하면 안 된다"); return AsyncThrowingStream { $0.finish() } })
        try await job.run(videoID: "v1")
        #expect(try events(db, "agent.notConnected").count == 1)
    }

    @Test("초안이 저장되면 끝 — CLI · 판 · 모델 · 걸린 시간 · AI 가 한 말을 남긴다. 렌더는 걸지 않는다")
    func drafts() async throws {
        let db = try setup()
        let work = FileManager.default.temporaryDirectory.appending(path: "agentjob-\(UUID().uuidString)")
        let job = AgentJob(db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"), choose: { [claude] in claude },
                           workRoot: work, turn: savingTurn(db), makeCompositionID: { "draft_\($0)" })
        try await job.run(videoID: "v1")
        #expect(try await db.writer.read { try CompositionRecord.fetchOne($0, key: "draft_v1") } != nil)
        let finished = try #require(try events(db, "agent.turn.finished").first?.payload)
        #expect(finished.contains(#""cli":"claude""#) && finished.contains("2.1.283") && finished.contains("claude-opus-5-5"))
        #expect(finished.contains("훅을 앞으로 가져왔어요."))
        #expect(try events(db, "agent.draft.ready").first?.subjectId == "draft_v1")
        #expect(try await db.writer.read { try JobRecord.filter(Column("kind") == "render").fetchCount($0) } == 0)
        #expect(!FileManager.default.fileExists(atPath: work.appending(path: "draft_v1").path))
    }

    @Test("턴이 끝났는데 초안이 없으면 실패다 — 조용히 넘어가지 않는다")
    func failsWithoutDraft() async throws {
        let db = try setup()
        let job = AgentJob(db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"), choose: { [claude] in claude },
                           turn: { _, _ in AsyncThrowingStream { c in c.yield(.finished(AgentOutcome(isError: false))); c.finish() } })
        await #expect(throws: AgentJob.Failure.self) { try await job.run(videoID: "v1") }
        #expect(try events(db, "agent.turn.finished").first?.payload?.contains(#""ok":false"#) == true)
    }

    @Test("분석 → AI 작업이 큐에서 이어진다")
    func chainsInQueue() async throws {
        let db = try setup()
        let job = AgentJob(db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"), choose: { [claude] in claude },
                           turn: savingTurn(db), makeCompositionID: { "draft_\($0)" })
        final class Box: @unchecked Sendable { var queue: JobQueue? }
        let box = Box()
        let queue = JobQueue(db: db, handlers: [
            .analyze: { j in try await box.queue?.enqueue(.agent, targetId: j.targetId) },
            .agent: job.handler,
        ])
        box.queue = queue
        try await queue.start()
        try await queue.enqueue(.analyze, targetId: "v1")
        await queue.waitUntilIdle()
        #expect(try await db.writer.read { try JobRecord.filter(Column("kind") == "agent" && Column("state") == "done").fetchCount($0) } == 1)
        #expect(try await db.writer.read { try CompositionRecord.fetchOne($0, key: "draft_v1") } != nil)
    }
}
