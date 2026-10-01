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
    /// 만드는 중 진행률 — 바꾸는 층이 읽는다 (메모리).
    let progress = RenderProgressBoard()
    /// iCloud 원본 받는 중 진행률 (메모리).
    let importProgress = ImportProgressBoard()
    let analysisProgress = AnalysisProgressBoard()

    /// "다시 가져오기" — 받기에 실패한 영상을 다시 받게 한 번 더 훑는다.
    func rescan() {
        photos?.rescan()
        folder?.rescan()
    }
    private var photos: PhotoLibraryWatcher?
    private var folder: FolderWatcher?

    /// 사진 보관함과 맞추는 진행 (목록 · 미리보기 그림이 늘 때마다, 끝나면 nil) — 화면이 다시 그리고 아랫줄에 보인다 (바꾸는 층이 건다).
    var onLibrarySync: (@Sendable (LibrarySync?) -> Void)?

    /// 목록에만 있던 사진 보관함 영상의 원본을 받는다 (`숏폼 만들기` 를 눌렀을 때). 받으면 분석이 걸린다.
    func fetchOriginal(sourceRef: String) {
        guard let photos else { return }
        Task.detached(priority: .userInitiated) { await photos.fetch(localIdentifier: sourceRef) }
    }

    /// 이 시각(앱을 처음 켠 시각) **이후에 찍은** 영상은 바로 받아 분석해 둔다. 그 전부터 보관함에 있던 영상은
    /// 목록에만 올리고 고를 때 받는다 (`PhotoLibraryWatcher`).
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

    /// 첫 실행 창의 "사진 접근 허용" — 권한을 묻고, 허용되면 감시를 시작한다. 돌려주는 값은 허용 여부.
    @discardableResult
    func startPhotos() async -> Bool {
        guard let photos else { return false }
        return await photos.start(ask: true)
    }

    func start() async {
        do {
            let db = try AppDatabase.openDefault()
            let catalog = try DownloadCatalog.bundled()
            FontLibrary.registerDownloaded(catalog: catalog)

            let preparer = try ModelPreparer(catalog: catalog)
            let analyze = AnalyzeJob(db: db, transcriber: PreparedTranscriber(preparer: preparer, db: db),
                                     progressBoard: analysisProgress)
            let thumbnails = Thumbnails()
            let render = RenderJob(db: db, progress: progress, thumbnails: thumbnails)
            // 분석(넣자마자) · 요청이 오면 → AI 초안 → 렌더 → 검사 → (되먹임 → 렌더 → 검사)… → 검사한 결과만 보여 준다
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
                // 갤러리 칸 그림 (캐시 — 못 만들어도 진행한다)
                if let path = try? await db.writer.read({ try VideoRecord.fetchOne($0, key: job.targetId)?.localPath }) ?? nil {
                    try? await thumbnails.makeVideo(job.targetId, from: URL(fileURLWithPath: path))
                }
                // 분석은 **편집 준비**다 — 넣자마자 해 두지만 AI 초안은 크리에이터가 요청했을 때만 건다
                // (2026-10-01 결정. 전에는 분석이 끝나면 늘 초안 → 영상 만들기까지 저절로 돌았다).
                if try !db.pendingDraftRequest(videoID: job.targetId).isEmpty {
                    try await queueBox.queue?.enqueue(.agent, targetId: job.targetId)
                }
            }
            let renderThenReview: JobQueue.Handler = { job in
                try await review.afterRender(try await render.run(compositionId: job.targetId))
            }
            let queue = JobQueue(db: db, handlers: [
                .analyze: analyzeThenDraft, .agent: agent.handler,
                .render: renderThenReview, .selfEval: agent.selfEvalHandler,
                .chat: agent.chatHandler,
            ], loadLevel: { LoadGovernor.shared.level })
            queueBox.queue = queue
            try await queue.start()

            let importer = Importer(db: db, queue: queue, progressBoard: importProgress)
            let folder = FolderWatcher(importer: importer, folder: Self.inbox)
            try folder.start()
            let photos = PhotoLibraryWatcher(importer: importer, since: Self.importSince, thumbnails: thumbnails,
                                             onSync: onLibrarySync)

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
            // 켤 때는 권한을 묻지 않는다 — 이미 허용됐을 때만 감시한다 (묻는 것은 첫 실행 창)
            if await !photos.start(ask: false) { Self.log.notice("사진 보관함 없이 폴더 감시만 쓴다: \(Self.inbox.path, privacy: .public)") }
            try db.log("app.started")
            // 보관 기간이 지난 촬영본의 앱 사본만 지운다 (사진 앱 원본 · 결과물은 그대로). 켤 때마다 한 번.
            Task.detached(priority: .background) { try? await Retention.sweep(db, keepDays: AppSettings().keepDays) }
        } catch {
            Self.log.fault("파이프라인을 시작하지 못했다: \(String(describing: error), privacy: .public)")
        }
    }
}

/// 분석 처리기가 큐를 늦게 참조하려고 쓰는 상자 (큐를 만들기 전에 처리기를 넘겨야 해서).
private final class QueueBox: @unchecked Sendable {
    var queue: JobQueue?
}
