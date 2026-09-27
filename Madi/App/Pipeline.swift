import Foundation
import MadiKit
import os

/// 앱이 켜지면 조립하는 파이프라인 (AGENTS.md §2 · docs/stage-3.spec.md).
///
/// ```
/// 사진 보관함 · 폴더 → Importer → [분석 작업] → 다이제스트
///                                   편집안 → [렌더 작업] → 결과물 · 리포트
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
            let queue = JobQueue(db: db, handlers: [.analyze: analyze.handler, .render: render.handler])
            try await queue.start()

            let importer = Importer(db: db, queue: queue)
            let folder = FolderWatcher(importer: importer, folder: Self.inbox)
            try folder.start()
            let photos = PhotoLibraryWatcher(importer: importer, since: Self.importSince)

            self.db = db; self.queue = queue; self.preparer = preparer
            self.folder = folder; self.photos = photos

            // 첫 실행이 끝나자마자 모델을 받기 시작한다 — 첫 영상이 기다리지 않게 (결정 A).
            Task.detached(priority: .utility) { await preparer.prepare() }
            if await !photos.start() { Self.log.notice("사진 보관함 없이 폴더 감시만 쓴다: \(Self.inbox.path, privacy: .public)") }
            try db.log("app.started")
        } catch {
            Self.log.fault("파이프라인을 시작하지 못했다: \(String(describing: error), privacy: .public)")
        }
    }
}
