import Foundation
import MadiKit

/// DB 스냅숏 → ViewData (docs/stage-6.spec.md 6번). **값을 내는 쪽만** — 행동 받기는 `RootView` 입구가 생긴 뒤
/// (`docs/design/viewdata-map.md` 요청 ⑦).
///
/// - 순수 함수다. 같은 스냅숏이면 같은 값을 낸다 — 테스트가 DB 상태마다 화면 값을 확인한다
/// - 문장은 `Copy`(디자인 소유)에서 읽기만 한다. 문구 키가 아직 없는 줄(채팅 선택지 · 알림)은 **내지 않는다** — 목록에 넘겼다
/// - 칸마다의 규칙은 `viewdata-map.md` 1절과 같다
enum ViewDataMapper {

    /// 그림 자리. 파일이 있으면 그 경로, 없으면 자리표시.
    static func thumb(_ url: URL, _ s: LibrarySnapshot) -> Thumbnail {
        s.thumbnails.contains(url.path) ? Thumbnail(fileURL: url) : .none
    }

    // MARK: - 사이드바

    static func studio(_ s: LibrarySnapshot, studioName: String, ai: AIConnection) -> StudioStatus {
        StudioStatus(
            studioName: studioName, ai: ai,
            shotCount: s.videos.count,
            resultCount: s.outputs.filter { $0.verdict == .shown }.count,
            makingCount: s.videos.filter { !s.liveJobs(of: $0.id).isEmpty }.count
        )
    }

    // MARK: - 갤러리

    static func gallery(_ s: LibrarySnapshot, photos: PhotoAccess) -> GalleryState {
        if s.videos.isEmpty { return photos == .denied ? .noPhotoAccess : .empty }
        let groups = shotGroups(s)
        let importing = s.videos.filter { $0.status == .importing }.count
        if importing > 0 {
            return .importing(done: s.videos.count - importing, total: s.videos.count, groups: groups)
        }
        return .loaded(groups)
    }

    static func shotAt(_ v: VideoRecord) -> Date { v.capturedAt ?? v.importedAt }

    static func shotGroups(_ s: LibrarySnapshot) -> [ShotGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: s.now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: s.now)?.start ?? today
        let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        func bucket(_ d: Date) -> Int {
            if d >= today { return 0 }
            if d >= weekStart { return 1 }
            if d >= lastWeekStart { return 2 }
            return 3
        }
        let titles = [Copy.Gallery.Group.today, Copy.Gallery.Group.thisWeek, Copy.Gallery.Group.lastWeek, Copy.Gallery.Group.earlier]
        let sorted = s.videos.sorted { shotAt($0) > shotAt($1) }
        return (0..<4).compactMap { b in
            let vs = sorted.filter { bucket(shotAt($0)) == b }
            guard let newest = vs.first.map(shotAt), let oldest = vs.last.map(shotAt) else { return nil }
            return ShotGroup(title: titles[b], subtitle: dayRange(oldest, newest), shots: vs.map { shot($0, s) })
        }
    }

    /// `9월 25일` · `9월 21–23일` · `8월 30일 – 9월 2일`
    static func dayRange(_ a: Date, _ b: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(a, inSameDayAs: b) { return Copy.day(a) }
        if cal.component(.month, from: a) == cal.component(.month, from: b) {
            return "\(cal.component(.month, from: a))월 \(cal.component(.day, from: a))–\(cal.component(.day, from: b))일"
        }
        return "\(Copy.day(a)) – \(Copy.day(b))"
    }

    static func shot(_ v: VideoRecord, _ s: LibrarySnapshot) -> ShotItem {
        ShotItem(
            id: v.id,
            title: title(of: v.id, s),
            shotAt: shotAt(v),
            duration: v.durationSec ?? 0,
            // 소리 측정이 "말이 있다 · 없다" 뿐이다 — noisy 는 가를 기준이 없어 내지 않는다 (viewdata-map 요청 ⑥)
            speech: s.wordCounts[v.id] == 0 ? .silent : .clear,
            isMaking: !s.liveJobs(of: v.id).isEmpty,
            thumbnail: thumb(s.thumbnailStore.video(v.id), s),
            results: results(of: v.id, s)
        )
    }

    /// 말소리에서 뽑은 제목 — AI 가 쓴 편집안 제목(가장 최근 사람이 본 판). 초안 전에는 빈 문자열.
    static func title(of videoID: String, _ s: LibrarySnapshot) -> String {
        for c in s.visibleVersions(of: videoID).reversed() {
            if let t = try? c.composition().meta.title, !t.isEmpty { return t }
        }
        return ""
    }

    // MARK: - 결과물

    static func versionNumber(_ versionID: String, _ s: LibrarySnapshot) -> Int? {
        guard let root = s.compositions.first(where: { $0.id == versionID }) else { return nil }
        return s.visibleVersions(of: root.videoId).firstIndex { $0.id == root.id }.map { $0 + 1 }
    }

    static func resultRef(_ o: OutputRecord, _ s: LibrarySnapshot) -> ResultRef? {
        guard let rec = s.compositions.first(where: { $0.id == o.compositionId }), let comp = try? rec.composition() else { return nil }
        let number = s.versionRoot(of: rec.id).flatMap { versionNumber($0.id, s) } ?? 1
        return ResultRef(
            id: o.id, platform: platform(comp.meta.platform), planLabel: Copy.Plan.version(number),
            when: Copy.shotStamp(o.createdAt, now: s.now), duration: comp.duration, sceneCount: comp.scenes.count,
            isNew: o.seenAt == nil, exportedNote: exportedNote(o.id, s), thumbnail: thumb(s.thumbnailStore.output(o.id), s)
        )
    }

    /// 내보낸 이력 한 줄 — 가장 최근 것. 폴더 저장은 문구가 없어 아직 안 낸다 (copy-keys `exportedToFolder`).
    static func exportedNote(_ outputID: String, _ s: LibrarySnapshot) -> String? {
        guard let e = s.exports.last(where: { $0.outputId == outputID && $0.target == .photos }) else { return nil }
        return Copy.Results.Export.historyLine(target: Copy.Results.Export.photos, when: Copy.time(e.createdAt))
    }

    static func results(of videoID: String, _ s: LibrarySnapshot) -> [ResultRef] {
        let comps = Set(s.compositions(of: videoID).map(\.id))
        return s.outputs.filter { $0.verdict == .shown && comps.contains($0.compositionId) }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { resultRef($0, s) }
    }

    static func results(_ s: LibrarySnapshot) -> ResultsState {
        let groups = s.videos.sorted { shotAt($0) > shotAt($1) }.compactMap { v -> ResultGroup? in
            let items = results(of: v.id, s)
            return items.isEmpty ? nil : ResultGroup(shotTitle: shotTitle(v, s), items: items)
        }
        return groups.isEmpty ? .empty : .loaded(groups)
    }

    static func shotTitle(_ v: VideoRecord, _ s: LibrarySnapshot) -> String {
        let t = title(of: v.id, s)
        return t.isEmpty ? Copy.shotStamp(shotAt(v), now: s.now) : t
    }

    static func platform(_ p: MadiKit.Platform) -> PlatformKind {
        switch p {
        case .reels: .reels
        case .shorts: .shorts
        case .tiktok: .tiktok
        }
    }

    // MARK: - 편집안

    static func plan(_ s: LibrarySnapshot, videoID: String, ai: AIConnection) -> PlanState? {
        guard let video = s.videos.first(where: { $0.id == videoID }) else { return nil }
        let versions = s.visibleVersions(of: videoID)
        let live = s.liveJobs(of: videoID)
        let shown = versions.filter { s.shownOutput(forVersion: $0.id) != nil }
        guard let current = shown.last else {
            // 아직 보여 줄 판이 없다 — 짜는 중이거나(검사 전 렌더 · 되먹임 포함) AI 가 없다.
            if live.isEmpty && versions.isEmpty && ai == .none { return .noAI }
            return .preparing(prepareSteps(live))
        }
        let view = planView(current, video: video, versions: versions, s)
        // 보여 준 판보다 새 판(채팅 수정)이 만들어지는 중이면 — 목록은 그대로, 읽기 전용
        if let newest = versions.last, newest.id != current.id, !live.isEmpty {
            let steps = [
                PrepareStep(title: Copy.Plan.Making.captions, state: .done),
                PrepareStep(title: Copy.Plan.Making.reframe, state: .running),
                PrepareStep(title: Copy.Plan.Making.encode, state: .waiting),
            ]
            return .making(view, MakingProgress(fraction: s.progress[newest.id] ?? 0, steps: steps))
        }
        return .ready(view)
    }

    /// 실제 파이프라인을 디자인이 그린 네 단계에 얹는다 (viewdata-map 1절 — 이름을 맞춰야 한다).
    /// "쉬는 구간 찾기" 는 따로 도는 단계가 없다 — AI 가 장면을 고르며 같이 한다.
    static func prepareSteps(_ live: [JobRecord]) -> [PrepareStep] {
        let running = Set(live.filter { $0.state == .running }.map(\.kind))
        let queued = Set(live.map(\.kind))
        let stage: Int = {
            if running.contains(.render) || running.contains(.selfEval) || queued.contains(.render) || queued.contains(.selfEval) { return 3 }
            if running.contains(.agent) || queued.contains(.agent) { return 1 }
            return 0
        }()
        let titles = [Copy.Plan.Preparing.transcribe, Copy.Plan.Preparing.split, Copy.Plan.Preparing.findGaps, Copy.Plan.Preparing.reframe]
        return titles.enumerated().map { i, t in
            let done = i < stage && !(stage == 1 && i == 2)
            let run = i == stage || (stage == 1 && i == 2)
            return PrepareStep(title: t, state: done ? .done : run ? .running : .waiting)
        }
    }

    static func planView(_ rec: CompositionRecord, video: VideoRecord, versions: [CompositionRecord], _ s: LibrarySnapshot) -> PlanView {
        let comp = (try? rec.composition())
        let number = versionNumber(rec.id, s) ?? 1
        return PlanView(
            id: rec.id, shotID: video.id, shotTitle: shotTitle(video, s),
            platform: platform(comp?.meta.platform ?? .reels),
            versionLabel: Copy.Plan.version(number), versionCount: versions.count,
            sourceDuration: video.durationSec ?? 0, targetDuration: comp?.meta.targetDurationSec ?? 0,
            captionSlot: captionSlot(comp?.captionSlot ?? .fullBody),
            scenes: comp.map { sceneCards($0, s) } ?? [],
            resultCount: results(of: video.id, s).count,
            versions: versions.enumerated().map { i, v in
                let c = try? v.composition()
                return PlanVersion(
                    id: v.id, label: Copy.Plan.version(i + 1), duration: c?.duration ?? 0, sceneCount: c?.scenes.count ?? 0,
                    when: Copy.shotStamp(v.createdAt, now: s.now),
                    resultCount: s.shownOutput(forVersion: v.id) == nil ? 0 : 1, isCurrent: v.id == rec.id
                )
            }
        )
    }

    static func captionSlot(_ slot: MadiKit.CaptionSlot) -> CaptionSlot {
        switch slot {
        case .upperBody: .upperBody
        case .fullBody: .fullBody
        case .lowerBody: .lowerBody
        }
    }

    static func role(_ r: SceneRole) -> SceneRoleKind {
        switch r {
        case .hook: .hook
        case .demo: .demo
        case .explain: .explain
        case .cta: .cta
        case .filler: .filler
        }
    }

    /// 장면 카드. "뺀 쉬는 구간" 은 엔진에 없는 개념이라, 원본에서 바로 이어진 두 장면 사이의 틈으로 계산한다
    /// (viewdata-map 1절 — 뜻이 맞는지 디자인 확인 필요).
    static func sceneCards(_ comp: Composition, _ s: LibrarySnapshot) -> [SceneCardItem] {
        comp.scenes.enumerated().map { i, scene in
            let next = i + 1 < comp.scenes.count ? comp.scenes[i + 1] : nil
            var gap: Double?
            if let next, next.source.videoID == scene.source.videoID {
                let g = next.source.start - scene.source.end
                if g > 0.05 && g < 10 { gap = g }
            }
            return SceneCardItem(
                id: scene.id, number: i + 1, role: role(scene.role),
                caption: scene.captions.first?.text ?? "",
                secondary: scene.captions.first?.secondary,
                moreCaptions: scene.captions.dropFirst().map(\.text),
                duration: scene.duration, thumbnail: thumb(s.thumbnailStore.scene(comp.id, scene.id), s), removedGapAfter: gap
            )
        }
    }

    // MARK: - 대화

    /// 채팅 줄. 선택지 · 알림(문구 키)은 `Copy` 에 문장이 생기면 낸다 — 지금은 내지 않는다 (copy-keys 6단계 절).
    static func chat(_ s: LibrarySnapshot, videoID: String) -> [ChatMessage] {
        var out: [ChatMessage] = []
        for row in s.chats where row.videoId == videoID {
            let stamp = Copy.shotStamp(row.createdAt, now: s.now)
            switch row.kind {
            case .creator: out.append(ChatMessage(id: row.id, kind: .user(row.text ?? ""), stamp: stamp))
            case .creatorNotSent: out.append(ChatMessage(id: row.id, kind: .userNotSent(row.text ?? ""), stamp: stamp))
            case .assistant:
                out.append(ChatMessage(id: row.id, kind: .assistant(row.text ?? ""), stamp: stamp))
                // 이 말로 생긴 판의 결과물이 보여지면 카드로 붙는다
                if let cid = row.compositionId, let o = s.shownOutput(forVersion: cid), let ref = resultRef(o, s) {
                    out.append(ChatMessage(id: row.id + ".result", kind: .result(ref)))
                }
            case .choices, .notice:
                continue
            }
        }
        let myChats = Set(s.chats.filter { $0.videoId == videoID }.map(\.id))
        if s.jobs.contains(where: { job in job.kind == .chat && job.state != .failed && myChats.contains(job.targetId) }) {
            out.append(ChatMessage(id: "typing", kind: .typing))
        }
        return out
    }

    // MARK: - 만드는 중

    static func making(_ s: LibrarySnapshot) -> MakingState {
        let renders = s.jobs.filter { $0.kind == .render && ($0.state == .running || $0.state == .queued) }
            .sorted { ($0.state == .running ? 0 : 1, $0.createdAt) < ($1.state == .running ? 0 : 1, $1.createdAt) }
        let jobs: [MakingJob] = renders.compactMap { job in
            guard let rec = s.compositions.first(where: { $0.id == job.targetId }), let comp = try? rec.composition(),
                  let video = s.videos.first(where: { $0.id == rec.videoId }) else { return nil }
            let number = s.versionRoot(of: rec.id).flatMap { versionNumber($0.id, s) } ?? 1
            let state: MakingJob.State = job.state == .running
                ? .running(MakingProgress(fraction: s.progress[rec.id] ?? 0, steps: []))
                : .queued(note: Copy.MakingScreen.queuedNote(shotTitle(video, s)))
            return MakingJob(id: String(job.id ?? 0), shotTitle: shotTitle(video, s), platform: platform(comp.meta.platform),
                             planLabel: Copy.Plan.version(number), duration: comp.duration, state: state)
        }
        let startOfDay = Calendar.current.startOfDay(for: s.now)
        let done: [DoneItem] = s.outputs.filter { $0.verdict == .shown && $0.createdAt >= startOfDay }.compactMap { o in
            guard let rec = s.compositions.first(where: { $0.id == o.compositionId }),
                  let video = s.videos.first(where: { $0.id == rec.videoId }), let comp = try? rec.composition() else { return nil }
            return DoneItem(id: o.id, shotTitle: shotTitle(video, s), platform: platform(comp.meta.platform),
                            when: Copy.time(o.createdAt))
        }
        return jobs.isEmpty && done.isEmpty ? .empty : .loaded(jobs: jobs, doneToday: done)
    }
}
