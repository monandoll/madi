import Foundation
import MadiKit
import os

/// 앱이 켜지면 조립하는 파이프라인 (AGENTS.md §2 · docs/stage-3.spec.md).
///
/// ```
/// 사진 보관함 · 폴더 → Importer → [분석] → 다이제스트 → [AI] → 초안 → [렌더] → 검사(ReviewLoop)
///                                   ↑ 되먹임 항목이 남으면 [selfEval] → 새 편집안 ─┘  (최대 2회, §7-6)
/// 모델 준비는 첫 실행 직후부터 백그라운드로
/// ```
/// 화면은 없다 — 갤러리는 디자인 쪽이 `db` 를 관측해 그린다 (`Madi/UI` 는 디자인 소유).
@MainActor
final class MadiPipeline {
    static let log = Logger(subsystem: "app.madi", category: "pipeline")

    private(set) var db: AppDatabase?
    private(set) var queue: JobQueue?
    private(set) var preparer: ModelPreparer?
    private var photos: PhotoLibraryWatcher?
    private var folder: FolderWatcher?

    /// 사진 보관함에서 들일 영상의 시작 시각 = 앱을 처음 켠 시각. 보관함 전체를 들이지 않는다.
    static var importSince: Date {
        let key = "madi.import.since"
        if let d = UserDefaults.standard.object(forKey: key) as? Date { return d }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    /// 폴더 감시 위치 (보조 경로). `~/Movies/madi`
    static var inbox: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appending(path: "madi", directoryHint: .isDirectory)
    }

    func start() async {
        do {
            let db = try AppDatabase.openDefault()
            let catalog = try DownloadCatalog.bundled()
            FontLibrary.registerDownloaded(catalog: catalog)

            let preparer = try ModelPreparer(catalog: catalog)
            let analyze = AnalyzeJob(db: db, transcriber: PreparedTranscriber(preparer: preparer, db: db))
            let render = RenderJob(db: db)
            // 분석 → AI 초안 → 렌더 → 검사 → (되먹임 → 렌더 → 검사)… → 검사한 결과만 보여 준다
            // (§10 · §7-6 · §8, 5단계 결정 ①).
            guard let mcp = Bundle.main.url(forAuxiliaryExecutable: "madi-mcp") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Contents/MacOS/madi-mcp"])
            }
            let queueBox = QueueBox()
            let agent = AgentJob(
                db: db, mcpExecutable: mcp,
                // 사용자 규칙 (§10 컨텍스트 4번) — "앞으로도 이렇게 할까요?" 에 예라고 한 것
                userRules: { (try? db.userRules()) ?? [] },
                onDraft: { id in try await queueBox.queue?.enqueue(.render, targetId: id) }
            )
            let review = ReviewLoop(db: db) { id in try await queueBox.queue?.enqueue(.selfEval, targetId: id) }
            let analyzeThenDraft: JobQueue.Handler = { job in
                try await analyze.handler(job)
                try await queueBox.queue?.enqueue(.agent, targetId: job.targetId)
            }
            let renderThenReview: JobQueue.Handler = { job in
                try await review.afterRender(try await render.run(compositionId: job.targetId))
            }
            let queue = JobQueue(db: db, handlers: [
                .analyze: analyzeThenDraft, .agent: agent.handler,
                .render: renderThenReview, .selfEval: agent.selfEvalHandler,
                .chat: agent.chatHandler,
            ])
            queueBox.queue = queue
            try await queue.start()

            let importer = Importer(db: db, queue: queue)
            let folder = FolderWatcher(importer: importer, folder: Self.inbox)
            try folder.start()
            let photos = PhotoLibraryWatcher(importer: importer, since: Self.importSince)

            self.db = db; self.queue = queue; self.preparer = preparer
            self.folder = folder; self.photos = photos

            // 첫 실행이 끝나자마자 모델을 받기 시작한다 — 첫 영상이 기다리지 않게 (결정 A).
            Task.detached(priority: .utility) { await preparer.prepare() }
            // 모델 상태가 바뀔 때만 기록한다 (진행률 틱은 빼고) — 3분 판정 · "편집 10분" 이 읽는다.
            Task.detached(priority: .utility) {
                var last = ""
                for await state in await preparer.states() {
                    let name: String
                    switch state {
                    case .notStarted: name = "notStarted"
                    case .downloading: name = "downloading"
                    case .paused: name = "paused"
                    case .warming: name = "warming"
                    case .ready: name = "ready"
                    case .failed: name = "failed"
                    case .diskFull: name = "diskFull"
                    }
                    if name != last { try? db.log("model." + name); last = name }
                    if case .ready = state { break }
                }
            }
            if await !photos.start() { Self.log.notice("사진 보관함 없이 폴더 감시만 쓴다: \(Self.inbox.path, privacy: .public)") }
            try db.log("app.started")
        } catch {
            Self.log.fault("파이프라인을 시작하지 못했다: \(String(describing: error), privacy: .public)")
        }
    }
}

/// 분석 처리기가 큐를 늦게 참조하려고 쓰는 상자 (큐를 만들기 전에 처리기를 넘겨야 해서).
private final class QueueBox: @unchecked Sendable {
    var queue: JobQueue?
}
