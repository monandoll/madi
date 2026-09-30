import AppKit
import Foundation
import Observation
import Photos
import UniformTypeIdentifiers
import MadiKit

/// 화면과 엔진 사이 (docs/stage-6.spec.md · `docs/design/viewdata-map.md` 5절).
///
/// - **값을 낸다**: DB 스냅숏 · 편집 준비 상태 · AI 연결을 `ViewDataMapper` 로 ViewData 로 바꿔 들고 있다
/// - **행동을 받는다**: 화면이 내보내는 것은 `UIAction` 하나다 (`RootView.onAction`). 무엇을 할지는 여기서 정한다
/// - 화면(`Madi/UI`)은 디자인 소유다 — 여기서는 값과 행동만 다룬다. 뷰를 새로 짜지 않는다
///   (편집안 칸 가운데 높이가 바뀌는 뷰를 띄우면 AppKit 이 멈춘다 — decisions.md "그리다 걸린 것")
@MainActor
@Observable
final class AppController {
    let pipeline: MadiPipeline

    // MARK: 화면에 내는 값
    var studio = StudioStatus(studioName: "", ai: .none, shotCount: 0, resultCount: 0, makingCount: 0)
    var gallery: GalleryState = .loading
    var plan: PlanState?
    var planMessages: [ChatMessage] = []
    var planTitle = ""
    var planChips: [String] = []
    var results: ResultsState = .loading
    var making: MakingState = .empty
    var resultsNotice: ScreenNotice?
    /// 갤러리 상태줄 한 줄 — 숨긴 뒤 "목록에서 숨겼어요 · 되돌리기". 전에는 앱이 채우지 않아 숨긴 촬영본을 되살릴 길이 없었다
    var galleryNotice: String?
    /// ⑧ 결과물 칸에서 고른 것을 이전 판과 나란히
    var resultDetail: ResultDetail?
    private var selectedResultID: String?
    /// 내보낼 곳 — 사진 앱 · Mac 에 저장 · AirDrop (§2 — 아이폰에서 보려면 사진 앱으로)
    let exportTargets: [ExportTarget] = [
        ExportTarget(title: Copy.Results.Export.photos, detail: Copy.Results.Export.photosDetail, symbol: "photo.on.rectangle"),
        ExportTarget(title: Copy.Results.Export.files, detail: Copy.Results.Export.filesDetail, symbol: "folder"),
        ExportTarget(title: Copy.Results.Export.airdrop, detail: Copy.Results.Export.airdropDetail, symbol: "wifi"),
    ]
    var settings = SettingsValues(ai: .notPicked, activeAI: .none, studioName: "", keepDays: AppSettings.defaultKeepDays, photos: .notAsked)
    var onboarding = OnboardingState(step: .photos)
    var showsOnboarding = !UserDefaults.standard.bool(forKey: AppController.onboardedKey)
    /// 설정 창을 열어 달라는 요청 — 바뀌면 창이 `openSettings` 를 부른다 (macOS 14 는 selector 로 안 열린다)
    var settingsRequest = 0

    static let onboardedKey = "madi.onboarded"

    // MARK: 엔진 쪽 상태
    /// 가장 최근 스냅숏 — 새 스냅숏과 진행률 칠하기가 서로 덮지 않게 상자 하나로만 바꾼다 (`SnapshotBox`).
    @ObservationIgnored private let box = SnapshotBox()
    private var snapshot: LibrarySnapshot? { box.current }
    private var openShotID: String?
    private var viewingVersionID: String?
    private var ai: AIConnection = .none
    private var photos: PhotoAccess = .notAsked
    /// 사진 보관함과 맞추는 중이면 그 진행 — 갤러리 아랫줄 "맞추는 중 · 237개 중 120개". 다 맞췄으면 nil.
    private var librarySync: LibrarySync?
    private var prep: EnginePrep?
    private var modelReady = false
    private let thumbnails = Thumbnails()
    private let isSlowMac = MachineArch.current == "x86_64"

    init(pipeline: MadiPipeline) { self.pipeline = pipeline }

    // MARK: - 시작

    func start() async {
        photos = Self.photoAccess()
        // 보관함 목록 · 미리보기 그림이 늘면 다시 그린다 (그림 파일은 DB 관측에 안 잡힌다)
        pipeline.onLibrarySync = { [weak self] sync in
            Task { @MainActor in
                guard let self else { return }
                self.librarySync = sync
                // 스냅숏을 다시 넣지 않는다 — 지금 것의 그림만 다시 고른다 (새 스냅숏을 옛 것으로 덮지 않게)
                self.box.reattachThumbnails(self.thumbnails)
                self.recompute()
            }
        }
        await pipeline.start()
        Task { await refreshAI() }
        guard let db = pipeline.db else { return }
        Task.detached(priority: .utility) { [weak self] in await self?.backfillThumbnails(db) }
        if let preparer = pipeline.preparer {
            Task { [weak self] in
                for await state in await preparer.states() { self?.apply(state) }
            }
        }
        Task { [weak self] in
            do {
                for try await snap in db.snapshots() { await self?.receive(snap) }
            } catch {}
        }
    }

    private func receive(_ snap: LibrarySnapshot) async {
        var s = snap
        s.attach(thumbnails: thumbnails, progress: [:])
        await box.receive(s) { await self.readProgress() }
        recompute()
        startProgressTicker()
    }

    /// 메모리 게시판의 진행률 — 만드는 중 · 원본 받기 · 분석 · 맥 식히는 중.
    private func readProgress() async -> ProgressReading {
        ProgressReading(render: await pipeline.progress.snapshot(), imports: await pipeline.importProgress.snapshot(),
                        analysis: await pipeline.analysisProgress.snapshot(), cooling: LoadGovernor.shared.isCooling)
    }

    /// 진행률은 DB 가 아니라 메모리 게시판에 있어서, DB 가 안 바뀌면 화면이 따라오지 않는다 (퍼센트가 멈춰 보였다).
    /// 작업이 도는 동안만 0.5초마다 게시판을 다시 읽는다. 작업이 끝나면 멈춘다 — 끝났는지는 **가장 최근** 스냅숏으로 본다.
    @ObservationIgnored private var progressTicker: Task<Void, Never>?

    private func startProgressTicker() {
        guard progressTicker == nil, box.isBusy else { return }
        progressTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, await self.box.refresh(reading: { await self.readProgress() }) else { return }
                self.recompute()
                if !self.box.isBusy { self.progressTicker = nil; return }
            }
        }
    }

    private func apply(_ state: ModelPreparer.State) {
        switch state {
        case .notStarted, .ready: prep = nil
        case .downloading(let p): prep = .downloading(p)
        case .paused: prep = .paused
        case .warming: prep = .warming
        case .failed: prep = .failed
        case .diskFull: prep = .diskFull
        }
        modelReady = state == .ready
        recompute()
    }

    /// 쓰는 AI 와 그 상태 — 설정값(`madi.agent`), 없으면 연결된 쪽. 설치됐지만 로그인이 풀렸으면 `notLoggedIn`.
    func refreshAI() async {
        if UserDefaults.standard.string(forKey: "madi.agent") == AgentJob.disabledValue {
            ai = .none
            recompute()
            return
        }
        let preferred = UserDefaults.standard.string(forKey: "madi.agent").flatMap(AgentKind.init(rawValue:))
        var found: AIConnection = .none
        for kind in preferred.map({ [$0] }) ?? [.claude, .codex] {
            switch await CLILocator.connection(kind) {
            case .ready: found = kind == .claude ? .claude : .codex
            case .notLoggedIn: if found == .none { found = .notLoggedIn(kind == .claude ? .claude : .codex) }
            case .notInstalled: continue
            }
            if found == .claude || found == .codex { break }
        }
        ai = found
        recompute()
    }

    static func photoAccess() -> PhotoAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: .granted
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    // MARK: - 값 다시 계산

    private func recompute() {
        let appSettings = AppSettings()
        studio = ViewDataMapper.studio(snapshot ?? LibrarySnapshot(), studioName: appSettings.studioName, ai: ai, preparing: prep,
                                       photos: photos, syncing: librarySync.map { PhotoSync(done: $0.done, total: $0.total) })
        settings = SettingsValues(
            ai: setup(for: ai), activeAI: ai, studioName: appSettings.studioName, keepDays: appSettings.keepDays,
            albumName: UserDefaults.standard.string(forKey: PhotoLibraryWatcher.albumNameKey),
            photos: photos, look: cachedLook(), isSlowMac: isSlowMac
        )
        onboarding.photos = photos
        onboarding.isSlowMac = isSlowMac
        guard let s = snapshot else { return }
        gallery = ViewDataMapper.gallery(s, photos: photos)
        results = ViewDataMapper.results(s)
        resultDetail = selectedResultID.flatMap { ViewDataMapper.resultDetail(s, outputID: $0) }
        making = ViewDataMapper.making(s)
        if let id = openShotID {
            plan = ViewDataMapper.plan(s, videoID: id, ai: ai, viewing: viewingVersionID, modelReady: modelReady)
            planMessages = ViewDataMapper.chat(s, videoID: id, ai: ai)
            planTitle = s.videos.first { $0.id == id }.map { ViewDataMapper.shotTitle($0, s) } ?? ""
            // 편집안이 아직 없으면 첫 요청 칩 — 누르면 그 말로 AI 가 시작한다 (㉗). 있으면 고치는 칩
            if case .asking? = plan {
                planChips = [Copy.Chat.Chips.auto, Copy.Chat.Chips.coreOnly, Copy.Chat.Chips.demoFirst]
            } else {
                planChips = [Copy.Chat.Chips.cutGaps, Copy.Chat.Chips.shorter, Copy.Chat.Chips.hookFirst]
            }
        } else {
            plan = nil
            planMessages = []
        }
    }

    private func setup(for ai: AIConnection) -> AISetup {
        switch ai {
        case .claude: .connected(.claude, account: "")
        case .codex: .connected(.codex, account: "")
        case .notLoggedIn(let p): .notLoggedIn(p)
        case .none: .notPicked
        }
    }

    // MARK: - 행동

    func handle(_ action: UIAction) {
        Task { await perform(action) }
    }

    private func perform(_ action: UIAction) async {
        guard let db = pipeline.db, let queue = pipeline.queue else { return }
        do {
            switch action {
            case .gallery(let a): try await gallery(a, db, queue)
            case .plan(let a): try await plan(a, db, queue)
            case .chat(let a): try await chat(a, db, queue)
            case .scene(let id, let a): try await scene(id, a, db)
            case .results(let a): try await results(a, db)
            case .making(let a): try await making(a, queue)
            case .onboarding(let a): await onboarding(a)
            case .settings(let a): await settings(a)
            case .openSettings: settingsRequest += 1
            }
        } catch {
            MadiPipeline.log.error("행동 실패 \(String(describing: action), privacy: .public): \(String(describing: error), privacy: .public)")
        }
        recompute()
    }

    // MARK: 갤러리

    private func gallery(_ a: UIAction.Gallery, _ db: AppDatabase, _ queue: JobQueue) async throws {
        switch a {
        case .makeShort(let id):
            openShotID = id
            viewingVersionID = nil
            try await ensureDraft(videoID: id, db, queue)
        case .play(let id):
            // 정보 칸에서 그 자리에서 튼다 (QuickTime 을 열지 않는다)
            NotificationCenter.default.post(name: .madiShotPlay, object: nil, userInfo: ["id": id])
        case .revealInPhotos(let id):
            // 전에는 앱 사본 파일을 기본 앱으로 열어 사진 앱 대신 QuickTime 이 떴다 (2026-09-30 실제 앱).
            // 폴더로 들어온 것은 사진 앱에 없다 — 원본 파일을 Finder 에서 고른 채로 보여 준다 (메뉴도 "Finder에서 보기").
            // 사진 보관함에서 온 것은 사진 앱을 앞으로 (그 항목을 골라 여는 공개 방법은 없다)
            guard let video = snapshot?.videos.first(where: { $0.id == id }) else { return }
            if video.source == .folder {
                let original = URL(fileURLWithPath: video.sourceRef)
                if FileManager.default.fileExists(atPath: original.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([original])
                } else {
                    NSWorkspace.shared.open(MadiPipeline.inbox)
                }
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
            }
        case .retryImport(let id):
            // 받기에 실패한 영상은 다시 훑으면 다시 받는다 (Importer 는 준비 안 된 영상을 건너뛰지 않는다).
            // 사진 보관함에 전부터 있던 영상은 훑기가 목록만 올리므로 그 영상을 짚어서 받는다
            if let v = snapshot?.videos.first(where: { $0.id == id }), v.source == .photos {
                pipeline.fetchOriginal(sourceRef: v.sourceRef)
            } else {
                pipeline.rescan()
            }
        case .addFromMac:
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.movie]
            guard panel.runModal() == .OK else { return }
            // 폴더 입구(보조 경로)로 복사하면 FolderWatcher 가 들인다 (§2)
            try FileManager.default.createDirectory(at: MadiPipeline.inbox, withIntermediateDirectories: true)
            for url in panel.urls { try? FileManager.default.copyItem(at: url, to: MadiPipeline.inbox.appending(path: url.lastPathComponent)) }
        case .openSystemSettings:
            Self.openPhotosPrivacy()
        case .allowPhotos:
            await allowPhotos()
        case .hide(let id):
            try await db.writer.write { db in
                try db.execute(sql: "UPDATE video SET hiddenAt = ? WHERE id = ?", arguments: [Date(), id])
            }
            galleryNotice = Copy.Gallery.Hidden.notice
        case .delete(let id):
            // 마디에서 삭제 — 도는 작업부터 멈추고(분석 · AI 턴 — 전에는 지운 영상의 AI 턴이 끝까지 돌았다),
            // DB 를 지우고(편집안 · 결과물 · 분석 · 채팅), 파일은 그다음. 사진 앱 원본은 그대로다.
            let video = snapshot?.videos.first { $0.id == id }
            if let s = snapshot {
                var targets: Set<String> = [id]
                targets.formUnion(s.compositions(of: id).map(\.id))
                targets.formUnion(s.chats.filter { $0.videoId == id }.map(\.id))
                try await queue.cancel(targetIds: targets)
            }
            let files = try db.deleteVideo(id, analysisRoot: AnalyzeJob.defaultRoot)
            for url in files { try? FileManager.default.removeItem(at: url) }
            // 폴더로 들어온 영상은 입구 폴더의 파일을 휴지통으로 (되살릴 수 있게). 입구 밖 파일은 건드리지 않는다
            if let video, video.source == .folder {
                let file = URL(fileURLWithPath: video.sourceRef)
                if file.deletingLastPathComponent().standardizedFileURL.path == MadiPipeline.inbox.standardizedFileURL.path {
                    try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
                }
            }
            if openShotID == id { openShotID = nil; viewingVersionID = nil }
            try? db.log("video.deleted", subject: id, payload: ["files": .number(Double(files.count))])
        case .undoHide:
            galleryNotice = nil
            // 가장 최근에 숨긴 것을 되살린다
            try await db.writer.write { db in
                try db.execute(sql: """
                    UPDATE video SET hiddenAt = NULL
                    WHERE id = (SELECT id FROM video WHERE hiddenAt IS NOT NULL ORDER BY hiddenAt DESC LIMIT 1)
                    """)
            }
        }
    }

    /// 촬영본을 열 때 · 다시 해 보기 · AI 가 연결됐을 때 — **이어서 할 일이 있으면** 건다.
    /// - 편집안이 없으면: 크리에이터가 남긴 첫 요청이 있을 때만 AI 초안을 건다 (분석이 안 됐으면 분석부터 — 끝나면 파이프라인이 초안을 건다).
    ///   요청이 없으면 **AI 는 걸지 않는다** — 화면이 무엇을 만들지 묻는다 (2026-10-01 결정: 요구도 없이 멋대로 만들지 않는다).
    ///   분석(편집 준비)만 안 돼 있으면 그것만 건다 — 구독을 쓰지 않는다.
    /// - 판은 있는데 결과물도 도는 작업도 없으면(자동 렌더 전에 만든 판) 가장 최근 판을 렌더에 건다 — 검사한 결과만 보여 준다.
    private func ensureDraft(videoID: String, _ db: AppDatabase, _ queue: JobQueue) async throws {
        guard let s = snapshot, s.liveJobs(of: videoID).isEmpty else { return }
        // 사진 보관함에 있던 영상 — 아직 원본을 안 받았다. 지금 받는다 (받으면 가져오기가 분석을 건다)
        if let video = s.videos.first(where: { $0.id == videoID }), video.status != .ready {
            // 목록에만 있거나, 받다가 실패했으면 (다시 해 보기) 받는다. 받는 중이면 기다린다
            if video.source == .photos, video.status == .listed || video.status == .failed {
                pipeline.fetchOriginal(sourceRef: video.sourceRef)
            }
            return   // 분석 · 초안은 원본이 온 뒤에
        }
        let versions = s.visibleVersions(of: videoID)
        if let newest = versions.last {
            // 휴지통으로 보낸 결과물도 "있었던 것" 이다 — 사람이 버린 것을 열자마자 몰래 다시 만들지 않는다
            // (2026-09-30 실제 앱: 결과물을 다 버린 촬영본을 열자 렌더가 걸려 버린 결과물이 되살아났다)
            if try !db.hasEverMadeOutput(videoID: videoID) { try await queue.enqueue(.render, targetId: newest.id) }
            return
        }
        let hasDigest = try await db.writer.read { try DigestRecord.fetchOne($0, key: videoID) } != nil
        if !hasDigest {
            try await queue.enqueue(.analyze, targetId: videoID)
        } else if try !db.pendingDraftRequest(videoID: videoID).isEmpty {
            try await queue.enqueue(.agent, targetId: videoID)
        }
    }

    /// 그림이 생기기 전에 들어온 촬영본 · 결과물의 그림을 채운다 (캐시 — 못 만들어도 괜찮다).
    private func backfillThumbnails(_ db: AppDatabase) async {
        guard let (videos, outputs) = try? await db.writer.read({ db in (try VideoRecord.fetchAll(db), try OutputRecord.fetchAll(db)) }) else { return }
        for v in videos where !FileManager.default.fileExists(atPath: thumbnails.video(v.id).path) {
            if let p = v.localPath { try? await thumbnails.makeVideo(v.id, from: URL(fileURLWithPath: p)) }
        }
        for o in outputs where o.trashedAt == nil && !FileManager.default.fileExists(atPath: thumbnails.output(o.id).path) {
            try? await thumbnails.makeOutput(o.id, from: URL(fileURLWithPath: o.path))
        }
        // 그림만 다시 고른다 — 스냅숏을 다시 넣으면 그사이 들어온 새 스냅숏을 옛 것으로 덮는다
        box.reattachThumbnails(thumbnails)
        recompute()
    }

    // MARK: 편집안

    private func currentVersionID() -> String? {
        if case .ready(let p)? = plan { return p.id }
        if case .making(let p, _)? = plan { return p.id }
        if case .stopped(let p?, _, _, _)? = plan { return p.id }
        return nil
    }

    private func plan(_ a: UIAction.Plan, _ db: AppDatabase, _ queue: JobQueue) async throws {
        switch a {
        case .close:
            openShotID = nil
            viewingVersionID = nil
        case .make:
            // 보고 있는 판에 결과물이 없으면 만든다 (사람이 고친 판). 있으면 이미 검사한 결과가 있다.
            guard let id = currentVersionID(), let s = snapshot, s.shownOutput(forVersion: id) == nil,
                  !s.outputs.contains(where: { s.versionRoot(of: $0.compositionId)?.id == id }) else { return }
            try await queue.enqueue(.render, targetId: id)
        case .stop:
            guard let videoID = openShotID, let s = snapshot else { return }
            var targets: Set<String> = [videoID]
            targets.formUnion(s.compositions(of: videoID).map(\.id))
            targets.formUnion(s.chats.filter { $0.videoId == videoID }.map(\.id))
            try await queue.cancel(targetIds: targets)
        case .pickVersion(let id):
            viewingVersionID = id
        case .moveScenes(let from, let to):
            try await edit(.move(from: from, to: to), db)
        case .choice(let c):
            if c.title == Copy.Plan.Stopped.tryAgain, let id = openShotID {
                if let s = snapshot, !s.visibleVersions(of: id).isEmpty {
                    // 판은 있다 — 만들다(렌더) 멈춘 것. 가장 최근 판을 다시 만든다
                    try await ensureDraft(videoID: id, db, queue)
                } else {
                    try await queue.enqueue(.analyze, targetId: id)   // 다이제스트는 캐시다 — 분석 뒤 초안이 다시 걸린다
                }
            } else if c.title == Copy.Plan.Stopped.pickAnother {
                openShotID = nil
                viewingVersionID = nil
            }
        case .connectAI:
            await connect(ai == .codex ? .codex : .claude)
        case .login(let product):
            await connect(product == .codex ? .codex : .claude)
        case .openResults(let id):
            // ⑨ 편집안에서 결과물을 열었다 — 그 결과물은 "봤다" (길 찾기는 화면이 한다)
            if let id { try await Exporter.markSeen(db, outputID: id) }
        case .play:
            playCurrent()
        }
    }

    /// 사람이 고친 판을 새 편집안으로 저장하고 그 판을 보여 준다 (`SceneEdits`).
    private func edit(_ e: SceneEdit, _ db: AppDatabase) async throws {
        guard let id = currentVersionID(), let rec = try await db.writer.read({ try CompositionRecord.fetchOne($0, key: id) }) else { return }
        let comp = try rec.composition()
        let (words, duration) = try await db.writer.read { db in
            (try LibrarySnapshot.words(db, videoID: rec.videoId), try VideoRecord.fetchOne(db, key: rec.videoId)?.durationSec)
        }
        let style = try StyleStore.load(comp.style).values.caption
        let edited = try SceneEdits.apply(e, to: comp, newID: "edit_\(rec.videoId)_\(UUID().uuidString.prefix(8))",
                                          words: words, style: style, sourceDuration: duration)
        // 장면 그림은 렌더할 때만 뽑아서, 사람이 고친 판(아직 안 만든 판)은 카드 · 미리보기가 전부 빈 칸이었다 (2026-09-30).
        // 저장 **전에** 원본에서 뽑는다 — 저장이 화면을 다시 그릴 때 그림 파일이 이미 있어야 한다
        if let path = snapshot?.videos.first(where: { $0.id == rec.videoId })?.localPath {
            try? await thumbnails.makeScenes(edited, sources: [rec.videoId: URL(fileURLWithPath: path)])
        }
        try db.saveComposition(edited, origin: .chat)
        viewingVersionID = edited.id
    }

    // MARK: 장면

    private func scene(_ id: SceneCardItem.ID, _ a: UIAction.Scene, _ db: AppDatabase) async throws {
        switch a {
        case .remove: try await edit(.remove(sceneID: id), db)
        case .extend: try await edit(.extend(sceneID: id, seconds: 1), db)
        case .shorten: try await edit(.shorten(sceneID: id, seconds: 1), db)
        case .restoreGap: try await edit(.restoreGap(sceneID: id), db)
        case .editCaption(let text, let secondary): try await edit(.editCaption(sceneID: id, text: text, secondary: secondary), db)
        case .playFromHere: playCurrent(sceneID: id)
        case .select: break   // 화면이 한다
        }
    }

    // MARK: 대화

    private func chat(_ a: UIAction.Chat, _ db: AppDatabase, _ queue: JobQueue) async throws {
        guard let videoID = openShotID else { return }
        switch a {
        case .send(let text), .chip(let text):
            try await send(text, videoID: videoID, db, queue)
        case .retrySend(let text):
            // 보내지 못한 줄은 지우고 다시 보낸다 — 같은 말이 두 번 남지 않게
            try await db.writer.write { db in
                try db.execute(sql: "DELETE FROM chat WHERE videoId = ? AND kind = 'creatorNotSent' AND text = ?", arguments: [videoID, text])
            }
            try await send(text, videoID: videoID, db, queue)
        case .choice(let c):
            guard let ask = snapshot?.chats.last(where: { $0.videoId == videoID && $0.kind == .choices && $0.payloadValues["answered"] == nil }) else { return }
            if c.title == Copy.Remember.rememberYes || c.title == Copy.Remember.rememberNo {
                try await Chat.answerRemember(db: db, choicesID: ask.id, yes: c.title == Copy.Remember.rememberYes)
            }
        case .undo:
            // 되돌리기 — 보고 있는 판의 이전 판을 본다 (새 판은 지우지 않는다, §1-8)
            if let id = currentVersionID(), let prev = snapshot?.compositions.first(where: { $0.id == id })?.revisionOf {
                viewingVersionID = snapshot?.versionRoot(of: prev)?.id ?? prev
            }
        case .openResult(let id):
            try await Exporter.markSeen(db, outputID: id)
        case .playFromStart:
            playCurrent()
        }
    }

    /// 재생 — 편집안 자리의 앱 안 플레이어를 이 위치로 옮겨 튼다 (`PlanVideo` 가 알림을 받는다).
    /// 위치는 결과물 타임라인의 초 — 장면이면 그 장면이 시작하는 곳.
    private func playCurrent(sceneID: String? = nil) {
        var seconds = 0.0
        if let sceneID, let id = currentVersionID(),
           let comp = try? snapshot?.compositions.first(where: { $0.id == id })?.composition(),
           let i = comp.scenes.firstIndex(where: { $0.id == sceneID }) {
            seconds = comp.sceneOffsets[i]
        }
        NotificationCenter.default.post(name: .madiPlayerSeek, object: nil, userInfo: ["seconds": seconds])
    }

    private func send(_ text: String, videoID: String, _ db: AppDatabase, _ queue: JobQueue) async throws {
        if snapshot?.compositions(of: videoID).isEmpty ?? false {
            // 첫 요청 — 편집안이 아직 없다. 이 말로 AI 가 초안을 짠다 (분석이 덜 끝났으면 끝난 뒤에)
            _ = try? await Chat.sendFirstRequest(db: db, videoID: videoID, text: text) { kind, id in
                try await queue.enqueue(kind, targetId: id)
            }
        } else {
            _ = try? await Chat.send(db: db, videoID: videoID, text: text, viewing: currentVersionID()) { id in
                try await queue.enqueue(.chat, targetId: id)
            }
        }
        viewingVersionID = nil   // 고친 판이 나오면 그걸 보여 준다
    }

    // MARK: 결과물

    private func results(_ a: UIAction.Results, _ db: AppDatabase) async throws {
        switch a {
        case .export(let id, let target):
            await export(id, to: target, db)
        case .trash(let id):
            try await Exporter.trash(db, outputID: id)
        case .openPlan(let id):
            guard let s = snapshot, let o = s.outputs.first(where: { $0.id == id }),
                  let rec = s.compositions.first(where: { $0.id == o.compositionId }) else { return }
            openShotID = rec.videoId
            viewingVersionID = s.versionRoot(of: rec.id)?.id
            try await Exporter.markSeen(db, outputID: id)
        case .noticeChoice(let choice):
            // 실패 안내의 버튼 — 누르면 그 일을 한다 (전에는 안내만 닫았다)
            resultsNotice = nil
            guard let failed = failedExport else { return }
            failedExport = nil
            if let target = ViewDataMapper.exportRetry(choice, failed: failed.target, targets: exportTargets) {
                await export(failed.id, to: target, db)
            }
        case .dismissNotice:
            resultsNotice = nil
            failedExport = nil
        case .showShots:
            break
        case .select(let id):
            // ⑧ 고른 결과물 — 이전 판과 나란히 (resultDetail). 고른 것은 "봤다"
            selectedResultID = id
            if let id { try await Exporter.markSeen(db, outputID: id) }
        }
    }

    /// 막힌 내보내기 — 실패 안내의 "다시 내보내기" · "Mac에 저장" 이 이어서 한다.
    private var failedExport: (id: String, target: ExportTarget)?

    private func export(_ id: String, to target: ExportTarget, _ db: AppDatabase) async {
        do {
            // 결과물 이름 — "스튜디오 · 제목" (첫 실행 · 설정이 이렇게 저장된다고 말한다)
            let title = snapshot.flatMap { s in s.outputs.first { $0.id == id }.flatMap { o in
                s.compositions.first { $0.id == o.compositionId }.flatMap { try? $0.composition().meta.title } } } ?? ""
            let studio = AppSettings().studioName
            let name = Exporter.fileName(studio: studio.isEmpty ? Copy.Onboarding.Studio.defaultName : studio, title: title)
            if target.title == Copy.Results.Export.photos {
                try await Exporter.toPhotos(db, outputID: id, name: name)
            } else if target.title == Copy.Results.Export.files {
                // macOS 의 저장 창 — 이름과 자리를 고르고 "저장". 전에는 폴더 고르는 "열기" 창이라 무엇을 하는지 알 수 없었다
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(name).mp4"
                panel.allowedContentTypes = [.mpeg4Movie]
                panel.canCreateDirectories = true
                panel.message = Copy.Results.Export.saveMessage
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try await Exporter.toFile(db, outputID: id, url: url)
            } else if let path = snapshot?.outputs.first(where: { $0.id == id })?.path {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [URL(fileURLWithPath: path)])
            }
            resultsNotice = nil
            failedExport = nil
        } catch {
            failedExport = (id, target)
            resultsNotice = ViewDataMapper.exportFailed(target)
        }
    }

    // MARK: 만드는 중

    private func making(_ a: UIAction.Making, _ queue: JobQueue) async throws {
        switch a {
        case .stop(let jobID), .cancel(let jobID):
            // MakingJob.id 는 작업 번호다 — 그 작업의 대상을 멈춘다
            guard let db = pipeline.db, let n = Int64(jobID),
                  let job = try await db.writer.read({ try JobRecord.fetchOne($0, key: n) }) else { return }
            try await queue.cancel(targetIds: [job.targetId])
        case .openResult(let id):
            if let db = pipeline.db { try await Exporter.markSeen(db, outputID: id) }
        case .choice:
            break
        }
    }

    // MARK: AI 연결 (첫 실행 · 설정 · 편집안)

    /// 설치가 안 됐으면 공식 방법으로 설치하고(결정 ②), 로그인을 띄워 기다린다. 사람은 브라우저에서 승인만 한다 (§1-9).
    private func connect(_ kind: AgentKind) async {
        let product: AIConnection = kind == .claude ? .claude : .codex
        onboarding.ai = .waiting(product)
        recompute()
        do {
            var exe = await CLILocator.locate(kind)
            if exe == nil { exe = try await CLIInstaller.install(kind) }
            if let exe, !(await CLILocator.connection(kind)).isReady {
                try await CLIInstaller.login(kind, executable: exe)
            }
            UserDefaults.standard.set(kind.rawValue, forKey: "madi.agent")
        } catch {
            MadiPipeline.log.error("AI 연결 실패: \(String(describing: error), privacy: .public)")
        }
        await refreshAI()
        if case .claude = ai { onboarding.ai = .connected(.claude, account: "") }
        else if case .codex = ai { onboarding.ai = .connected(.codex, account: "") }
        else { onboarding.ai = .picked(product) }
        // 연결이 되면 열려 있는 촬영본의 초안을 건다
        if ai == .claude || ai == .codex, let id = openShotID, let db = pipeline.db, let queue = pipeline.queue {
            try? await ensureDraft(videoID: id, db, queue)
        }
    }

    // MARK: 첫 실행

    private func onboarding(_ a: UIAction.Onboarding) async {
        switch a {
        case .allowPhotos:
            await pipeline.startPhotos()
            photos = Self.photoAccess()
        case .openSystemSettings:
            Self.openPhotosPrivacy()
        case .pickAI(let ai):
            onboarding.ai = .picked(ai)
        case .login:
            if case .picked(let ai) = onboarding.ai { await connect(ai == .codex ? .codex : .claude) }
        case .cancelLogin:
            if case .waiting(let ai) = onboarding.ai { onboarding.ai = .picked(ai) }
        case .otherAccount:
            onboarding.ai = .notPicked
        case .studioName(let name):
            AppSettings().studioName = name
            onboarding.studioName = name
        case .next:
            onboarding.step = Self.step(after: onboarding.step)
        case .back:
            onboarding.step = Self.step(before: onboarding.step)
        case .skip:
            onboarding.step = Self.step(after: onboarding.step)
        case .start:
            UserDefaults.standard.set(true, forKey: Self.onboardedKey)
            showsOnboarding = false
        }
    }

    static func step(after s: OnboardingStep) -> OnboardingStep {
        let all = OnboardingStep.allCases
        return all[min((all.firstIndex(of: s) ?? 0) + 1, all.count - 1)]
    }

    static func step(before s: OnboardingStep) -> OnboardingStep {
        let all = OnboardingStep.allCases
        return all[max((all.firstIndex(of: s) ?? 0) - 1, 0)]
    }

    // MARK: 설정

    private func settings(_ a: UIAction.Settings) async {
        switch a {
        case .connect(let ai): await connect(ai == .codex ? .codex : .claude)
        case .login(let p): await connect(p == .codex ? .codex : .claude)
        case .disconnect:
            // CLI 로그아웃은 하지 않는다 — 크리에이터의 다른 쓰임을 깨지 않게. 이 앱에서만 쓰지 않는다
            UserDefaults.standard.set(AgentJob.disabledValue, forKey: "madi.agent")
            await refreshAI()
        case .activeAI(let ai):
            if ai == .claude || ai == .codex { UserDefaults.standard.set(ai == .codex ? "codex" : "claude", forKey: "madi.agent") }
            await refreshAI()
        case .studioName(let name): AppSettings().studioName = name
        case .keepDays(let days): AppSettings().keepDays = days
        case .openSystemSettings: Self.openPhotosPrivacy()
        case .allowPhotos: await allowPhotos()
        case .pickAlbum:
            pickAlbum()
        case .look(let change):
            lookChanged(change)
        }
    }

    /// 앨범 고르기 — 메뉴로 띄운다 (전체 보관함 + 앨범 이름들). 고르면 다음 훑기부터 그 앨범만 본다.
    private func pickAlbum() {
        let menu = NSMenu()
        let target = AlbumMenuTarget { [weak self] id, name in
            if let id {
                UserDefaults.standard.set(id, forKey: PhotoLibraryWatcher.albumKey)
                UserDefaults.standard.set(name, forKey: PhotoLibraryWatcher.albumNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: PhotoLibraryWatcher.albumKey)
                UserDefaults.standard.removeObject(forKey: PhotoLibraryWatcher.albumNameKey)
            }
            self?.pipeline.rescan()
            self?.recompute()
        }
        let all = NSMenuItem(title: Copy.Settings.Shots.albumAll, action: #selector(AlbumMenuTarget.pick(_:)), keyEquivalent: "")
        all.target = target
        menu.addItem(all)
        menu.addItem(.separator())
        for album in PhotoLibraryWatcher.albums() {
            let item = NSMenuItem(title: album.name, action: #selector(AlbumMenuTarget.pick(_:)), keyEquivalent: "")
            item.representedObject = album.id
            item.target = target
            menu.addItem(item)
        }
        albumTarget = target
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private var albumTarget: AlbumMenuTarget?

    // MARK: 자막 모양

    /// 견본 이름 — `Copy` 키(`swatchWhite` 등)가 생길 때까지 디자인 미리보기 데이터의 이름을 쓴다.
    private var swatchLabels: [String: String] {
        Dictionary((SampleData.swatchesMain + SampleData.swatchesSecondary).map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
    }

    /// 설정 화면의 자막 모양 — 가장 최근 스타일 판에서. **판이 바뀔 때만** 다시 만든다.
    /// 전에는 화면 값을 다시 계산할 때마다(분석 중 약 2초마다) 스타일 파일을 읽고 설치된 글꼴을 전부 훑었다 —
    /// 메인 스레드라 화면이 버벅였다 (6단계 실제 앱 로그: CPU 97%, 스타일 경고 2분에 54번).
    @ObservationIgnored private var lookCache: (key: LookKey, look: CaptionLook)?
    /// 설치된 한글 글꼴 — 한 번 읽는다. 글꼴을 새로 깔았으면 `refreshFonts()`.
    @ObservationIgnored private var fontsCache: [String]?
    /// 컬러 피커를 끄는 동안의 모양 — 미리보기는 바로 바뀌고, 저장(새 스타일 판)은 손을 멈춘 뒤 한 번 한다.
    /// 끌 때마다 저장하면 판이 수십 개 쌓인다.
    @ObservationIgnored private var lookDraft: StyleValues.LookValues?
    @ObservationIgnored private var lookSaveTask: Task<Void, Never>?

    /// 미리보기가 달라지는 것 전부 — 스타일 판 · 저장 전 모양 · 미리보기 문장.
    private struct LookKey: Hashable {
        var ref: StyleRef
        var look: StyleValues.LookValues
        var text: String
        var secondary: String
        var favorites: [HexColor]
        var secondaryFavorites: [HexColor]
    }

    /// 자주 쓰는 색 3칸 — 사람이 바꾼다. 모양(스타일 판)이 아니라 앱 설정이다.
    private static let favoritesKey = "madi.look.favorites.main"
    private static let secondaryFavoritesKey = "madi.look.favorites.secondary"
    private func favorites(_ row: UIAction.Settings.Look.Row) -> [HexColor] {
        let key = row == .main ? Self.favoritesKey : Self.secondaryFavoritesKey
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([HexColor].self, from: data), saved.count == 3 { return saved }
        return row == .main ? LookMapper.defaultFavorites : LookMapper.defaultSecondaryFavorites
    }
    private func setFavorites(_ colors: [HexColor], _ row: UIAction.Settings.Look.Row) {
        let key = row == .main ? Self.favoritesKey : Self.secondaryFavoritesKey
        if let data = try? JSONEncoder().encode(colors) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static let previewTextKey = "madi.look.previewMain"
    private static let previewSecondaryKey = "madi.look.previewSecondary"
    private var previewText: String {
        UserDefaults.standard.string(forKey: Self.previewTextKey) ?? Copy.Look.previewMain
    }
    private var previewSecondaryText: String {
        UserDefaults.standard.string(forKey: Self.previewSecondaryKey) ?? Copy.Look.previewSecondary
    }

    private func cachedLook() -> CaptionLook? {
        guard let ref = try? StyleStore.latest(), let style = try? StyleStore.load(ref) else { return nil }
        var values = style.values
        if let lookDraft { values.look = lookDraft }
        let key = LookKey(ref: ref, look: values.look, text: previewText, secondary: previewSecondaryText,
                          favorites: favorites(.main), secondaryFavorites: favorites(.secondary))
        if let c = lookCache, c.key == key { return c.look }
        let fonts = fontsCache ?? MadiFont.hangulFamilies()
        fontsCache = fonts
        let look = LookMapper.look(values.look, fonts: fonts, labels: swatchLabels, preview: lookPreview(values, key),
                                   previewText: key.text, previewSecondaryText: key.secondary,
                                   favorites: key.favorites, secondaryFavorites: key.secondaryFavorites)
        lookCache = (key, look)
        return look
    }

    func refreshFonts() {
        fontsCache = MadiFont.hangulFamilies()
        lookCache = nil
        recompute()
    }

    /// 지금 모양으로 그린 자막 — **자막 둘레만** 잘라 낸 가로 그림 (1080×360).
    /// 세로 한 장(1080×1920)을 통째로 주면 설정의 납작한 칸이 가운데만 보여 줘서 자막이 잘려 나갔다 (빈 검은 칸).
    /// 그리는 것은 렌더와 같은 `CaptionLayer` 다 (§7).
    private func lookPreview(_ values: StyleValues, _ key: LookKey) -> Thumbnail {
        let url = thumbnails.root.appending(path: "look-preview-\(abs(key.hashValue)).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            let text = key.text.isEmpty ? " " : key.text
            let caption = Caption(id: "look", start: 0, end: 2, text: text,
                                  secondary: key.secondary.isEmpty ? nil : key.secondary)
            let frame = CGSize(width: 1080, height: 1920)
            if let image = try? StillRenderer.renderCaption(caption, size: frame, style: values, slot: .fullBody),
               let band = StillRenderer.captionBand(image, height: 360) {
                // 옛 미리보기 파일은 지운다 (문장 · 색을 바꿀 때마다 하나씩 생긴다)
                if let old = try? FileManager.default.contentsOfDirectory(at: thumbnails.root, includingPropertiesForKeys: nil) {
                    for f in old where f.lastPathComponent.hasPrefix("look-") { try? FileManager.default.removeItem(at: f) }
                }
                try? FileManager.default.createDirectory(at: thumbnails.root, withIntermediateDirectories: true)
                try? StillRenderer.writePNG(band, to: url)
            }
        }
        return FileManager.default.fileExists(atPath: url.path) ? Thumbnail(fileURL: url) : .none
    }

    /// 자막 모양을 바꿨다. 미리보기 문장은 미리보기에만 · 컬러 피커는 멈춘 뒤 한 번 저장 · 나머지는 바로 저장.
    private func lookChanged(_ change: UIAction.Settings.Look) {
        switch change {
        case .previewText(let t):
            UserDefaults.standard.set(t, forKey: Self.previewTextKey)
        case .previewSecondaryText(let t):
            UserDefaults.standard.set(t, forKey: Self.previewSecondaryKey)
        case .setFavorite(let row, let index):
            // 그 줄의 지금 색(끄는 중이면 그 색)을 자주 쓰는 색 칸에 넣는다
            guard let look = lookDraft ?? (try? StyleStore.load(StyleStore.latest()).values.look) else { return }
            var favs = favorites(row)
            guard favs.indices.contains(index) else { return }
            favs[index] = row == .main ? look.caption.fill : look.secondary.fill
            setFavorites(favs, row)
        case .fill(let id) where LookMapper.favoriteIndex(id) != nil,
             .secondaryFill(let id) where LookMapper.favoriteIndex(id) != nil:
            // 자주 쓰는 색 칸을 눌렀다 — 그 칸의 색을 쓴다
            let row: UIAction.Settings.Look.Row = { if case .fill = change { .main } else { .secondary } }()
            let favs = favorites(row)
            guard let i = LookMapper.favoriteIndex(id), favs.indices.contains(i) else { return }
            let c = favs[i].rgba
            commitLookDraft()
            saveLook(row == .main
                     ? .fillColor(red: Double(c.r), green: Double(c.g), blue: Double(c.b))
                     : .secondaryFillColor(red: Double(c.r), green: Double(c.g), blue: Double(c.b)))
        case .fillColor, .secondaryFillColor:
            guard let base = lookDraft ?? (try? StyleStore.load(StyleStore.latest()).values.look) else { return }
            lookDraft = LookMapper.apply(change, to: base)
            lookSaveTask?.cancel()
            lookSaveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                self?.commitLookDraft()
                self?.recompute()
            }
        default:
            commitLookDraft()
            saveLook(change)
        }
    }

    /// 컬러 피커로 고르던 색을 새 스타일 판으로 저장한다.
    private func commitLookDraft() {
        lookSaveTask?.cancel()
        guard let draft = lookDraft else { return }
        lookDraft = nil
        do {
            let base = try StyleStore.load(StyleStore.latest())
            guard draft != base.values.look else { return }
            try StyleStore.saveLook(draft, basedOn: base)
        } catch {
            MadiPipeline.log.error("자막 모양 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 고른 모양을 새 스타일 판으로 저장한다 — 다음에 만드는 영상부터 (§1-8 옛 결과물은 자기 판으로).
    private func saveLook(_ change: UIAction.Settings.Look) {
        do {
            let base = try StyleStore.load(StyleStore.latest())
            let next = LookMapper.apply(change, to: base.values.look)
            guard next != base.values.look else { return }
            try StyleStore.saveLook(next, basedOn: base)
        } catch {
            // 설치 안 된 글꼴 등 — 저장하지 않는다 (조용히 대체하지 않는다, §9)
            MadiPipeline.log.error("자막 모양 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 사진 접근 켜기 — 아직 안 물었으면 권한 창, 거절했으면 시스템 설정 (묻지 않은 앱은 시스템 설정 목록에 없다).
    private func allowPhotos() async {
        if Self.photoAccess() == .notAsked { _ = await pipeline.startPhotos() } else { Self.openPhotosPrivacy() }
        photos = Self.photoAccess()
    }

    static func openPhotosPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 앨범 메뉴 항목의 대상 (NSMenu 는 selector 를 부른다).
private final class AlbumMenuTarget: NSObject {
    let onPick: (String?, String) -> Void
    init(_ onPick: @escaping (String?, String) -> Void) { self.onPick = onPick }
    @objc func pick(_ item: NSMenuItem) { onPick(item.representedObject as? String, item.title) }
}
