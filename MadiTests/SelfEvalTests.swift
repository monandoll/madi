import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 되먹임 턴 · 루프 전체 (docs/stage-5.spec.md 4번). AI 는 가짜 턴, 렌더는 진짜(합성 영상).
struct SelfEvalTests {

    private func comp(_ id: String, firstScene role: SceneRole = .hook, captionAt: Double? = 0.1, revisionOf: String? = nil) -> Composition {
        let caps = captionAt.map { [Caption(id: "c", start: $0, end: $0 + 0.4, text: "안녕하세요.")] } ?? []
        return Composition(id: id, videoID: "v1", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                           meta: Composition.Meta(targetDurationSec: 1.8), captionSlot: .upperBody,
                           scenes: [Scene(id: "s1", role: role, source: Scene.Source(videoID: "v1", start: 0, end: 1.8), captions: caps)],
                           revisionOf: revisionOf)
    }

    @Test("요청문 — 항목마다 수치와 고치는 방향, 지난 편집안에서 앱이 채우는 칸은 뺀다")
    func requestText() {
        let report: [String: JSONValue] = [
            "selfEval": .array([.string("G11"), .string("G8")]), "G11.ratio": .number(0.669), "G8.firstCaptionSec": .number(0.9),
        ]
        let prev = comp("d", captionAt: 0.9)
        let text = SelfEvalRequest.text(report: report, previous: prev)
        #expect(text.contains("크리에이터에게 보이지 않는다"))
        #expect(text.contains("67%") && text.contains("더하거나 늘려서"))
        #expect(text.contains("0.90초"))
        #expect(text.contains("targetDurationSec` 는 바꾸지 않는다"))
        let json = SelfEvalRequest.previousJSON(prev)
        for key in ["\"captions\"", "\"style\"", "\"reframe\"", "\"videoId\"", "\"id\" : \"d\""] { #expect(!json.contains(key), "\(key)") }
        #expect(json.contains("\"role\" : \"hook\""))
    }

    @Test("되먹임 턴은 목표 길이를 바꾸면 거절된다")
    func lockedTarget() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: "/tmp/v1", durationSec: 20, status: .ready).insert($0) }
        try db.writer.write { try DigestRecord(videoId: "v1", version: 1, sourceFingerprint: "f", text: "t", sheetPaths: [],
                                               transcript: Transcript(videoID: "v1", words: MCPTests.words),
                                               subject: SubjectTrack(source: SourceInfo(videoID: "v1", width: 1920, height: 1080, durationSec: 20, fps: 30), stepSec: 0.5, samples: []),
                                               createdAt: Date()).insert($0) }
        try db.saveComposition(comp("d"))
        let tools = MadiTools(db: db, videoID: "v1", compositionID: "r1", revisionOf: "d", origin: .selfEval,
                              style: { try StyleStore.load() })
        let body: [String: Any] = ["meta": ["targetDurationSec": 5], "captionSlot": "fullBody",
                                   "scenes": [["role": "hook", "source": ["in": 0.1, "out": 5.2]]]]
        let out = tools.call("write_composition", arguments: ["composition": body])
        #expect(out.isError)
        #expect((out.content.first?["text"] as? String)?.contains("targetDurationSec") == true)
        let ok = tools.call("write_composition", arguments: ["composition": body.merging(["meta": ["targetDurationSec": 1.8]]) { $1 }])
        #expect(!ok.isError)
        #expect(try db.writer.read { try CompositionRecord.fetchOne($0, key: "r1") }?.origin == .selfEval)
    }

    final class Box: @unchecked Sendable { var queue: JobQueue?; var prompts: [String] = []; var sheets: [String] = [] }

    @Test("루프 전체 — 첫 말이 늦은 초안(G8) → 렌더 → 되먹임 → 고친 판이 보여진다. 쓸데없는 턴은 없다")
    func loop() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "v.mp4")
        try await TestVideo.makeTwoTone(at: source, seconds: 2, switchAt: 1, size: CGSize(width: 360, height: 640))
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: source.path, localPath: source.path, status: .ready).insert($0) }
        try await AnalyzeJob(db: db, transcriber: DigestTests.FakeTranscriber(), root: dir.appending(path: "a")).run(videoId: "v1")

        let box = Box()
        let counter = Counter()
        // 가짜 AI: 첫 초안은 첫 장면이 훅이 아니다(G8 실패), 되먹임 턴은 훅으로 고친다.
        // (전에는 첫 말 0.9초로 실패시켰는데, G8 이 크리에이터 실측 2.0초로 바뀌어 통과한다 — 2초짜리 시험 영상에서는 2초 넘게 늦출 수 없다)
        let turn: AgentJob.Turn = { _, request in
            AsyncThrowingStream { c in
                let args = request.mcp.arguments
                let id = args[args.firstIndex(of: "--composition")! + 1]
                let rev = args.firstIndex(of: "--revision-of").map { args[$0 + 1] }
                box.prompts.append(request.prompt)
                if let i = args.firstIndex(of: "--feedback-sheet") { box.sheets.append(args[i + 1]) }
                do {
                    try db.saveComposition(self.comp(id, firstScene: rev == nil ? .demo : .hook, captionAt: 0.1, revisionOf: rev),
                                           origin: rev == nil ? .draft : .selfEval)
                } catch { c.finish(throwing: error); return }
                c.yield(.finished(AgentOutcome(isError: false)))
                c.finish()
            }
        }
        let agent = AgentJob(
            db: db, mcpExecutable: URL(fileURLWithPath: "/x/madi-mcp"),
            choose: { .init(kind: .claude, executable: URL(fileURLWithPath: "/x/claude"), version: nil) },
            workRoot: dir.appending(path: "agent"), turn: turn,
            makeCompositionID: { _ in "c\(counter.next())" },
            onDraft: { id in try await box.queue?.enqueue(.render, targetId: id) }
        )
        let render = RenderJob(db: db, outputs: dir.appending(path: "out"))
        let review = ReviewLoop(db: db) { id in try await box.queue?.enqueue(.selfEval, targetId: id) }
        let queue = JobQueue(db: db, handlers: [
            .agent: agent.handler, .selfEval: agent.selfEvalHandler,
            .render: { job in try await review.afterRender(try await render.run(compositionId: job.targetId)) },
        ])
        box.queue = queue
        try await queue.start()
        try await queue.enqueue(.agent, targetId: "v1")
        await queue.waitUntilIdle()

        let (comps, outputs, failed) = try await db.writer.read { db in
            (try CompositionRecord.order(Column("createdAt")).fetchAll(db),
             try OutputRecord.fetchAll(db),
             try JobRecord.filter(Column("state") == "failed").fetchAll(db))
        }
        #expect(failed.isEmpty, "\(failed.map { $0.error ?? "" })")
        #expect(comps.map(\.origin) == [.draft, .selfEval])              // 되먹임 1회, 2회째는 없다
        #expect(comps.last?.revisionOf == comps.first?.id)
        let shown = outputs.filter { $0.verdict == .shown }
        #expect(shown.count == 1 && shown.first?.compositionId == comps.last?.id)
        #expect(outputs.first { $0.compositionId == comps.first?.id }?.verdict == .hidden)
        // 되먹임 턴은 지난 결과물 시트(내보낸 파일)를 받고, 요청문에 G8 이 들어 있다
        #expect(box.sheets.count == 1)
        #expect(box.prompts.count == 2 && box.prompts[1].contains("훅:"))
    }

    final class Counter: @unchecked Sendable {
        private var n = 0
        private let lock = NSLock()
        func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }
}
