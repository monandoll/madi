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

    static func studio(_ s: LibrarySnapshot, studioName: String, ai: AIConnection, preparing: EnginePrep? = nil) -> StudioStatus {
        StudioStatus(
            studioName: studioName, ai: ai,
            shotCount: s.videos.filter { $0.hiddenAt == nil && $0.deletedAt == nil }.count,
            resultCount: s.outputs.filter { $0.verdict == .shown }.count,
            makingCount: s.videos.filter { !s.liveJobs(of: $0.id).isEmpty }.count,
            preparing: preparing
        )
    }

    // MARK: - 갤러리

    static func gallery(_ s: LibrarySnapshot, photos: PhotoAccess) -> GalleryState {
        // 숨긴 촬영본은 목록에서만 뺀다 (사진 앱 원본 · 결과물은 그대로)
        var s = s
        s.videos = s.videos.filter { $0.hiddenAt == nil && $0.deletedAt == nil }
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
            results: results(of: v.id, s),
            // iCloud 원본 받는 중 — 받는 동안만 (§2 "저장 공간 최적화")
            fetchProgress: v.status == .importing ? s.importProgress[v.id] : nil,
            problem: v.status == .failed ? Copy.Photos.importFailedShort : nil,
            // 정보 칸에서 그 자리에서 튼다 — 다 받은 앱 사본만
            videoURL: v.status == .ready ? v.localPath.map { URL(fileURLWithPath: $0) } : nil
        )
    }

    /// 말소리에서 뽑은 제목 — AI 가 쓴 편집안 제목(가장 최근 사람이 본 판). 초안 전에는 빈 문자열.
    static func title(of videoID: String, _ s: LibrarySnapshot) -> String {
        let versions = s.visibleVersions(of: videoID).reversed().compactMap { try? $0.composition() }
        for c in versions where !c.meta.title.isEmpty { return c.meta.title }
        // AI 가 제목을 안 적은 옛 판 — 첫 자막(훅)을 이어 붙여 이름으로 쓴다. 촬영 시각보다 알아보기 쉽다.
        if let c = versions.first {
            let captions = c.scenes.flatMap(\.captions).map(\.text)
            var t = ""
            for text in captions {
                let next = t.isEmpty ? text : t + " " + text
                if next.count > 25 { break }
                t = next
            }
            if !t.isEmpty { return t }
        }
        return ""
    }

    /// AI 말을 말풍선에 맞게 — 마크다운 기호를 걷는다 (`**굵게**`, `- 목록`, `# 제목`).
    /// 지침(playbook)으로 막지만, 새어 나와도 기호가 보이지 않게 여기서 한 번 더 거른다.
    static func plain(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            var l = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            let trimmed = l.drop(while: { $0 == " " })
            if trimmed.hasPrefix("#") { l = String(trimmed.drop(while: { $0 == "#" || $0 == " " })) }
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { l = "· " + trimmed.dropFirst(2) }
            return l
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\n\n\n", with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 첫 문장 — 결과물 "달라진 점" 한 줄. 긴 답을 통째로 넣지 않는다.
    static func firstSentence(_ text: String) -> String {
        let flat = plain(text).replacingOccurrences(of: "\n", with: " ")
        let end = flat.firstIndex(where: { ".!?。".contains($0) })
        let sentence = end.map { String(flat[...$0]) } ?? flat
        return sentence.count > 60 ? String(sentence.prefix(59)) + "…" : sentence
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
            isNew: o.seenAt == nil, exportedNote: exportedNote(o.id, s), thumbnail: thumb(s.thumbnailStore.output(o.id), s),
            notice: gateTip(o),
            fileURL: FileManager.default.fileExists(atPath: o.path) ? URL(fileURLWithPath: o.path) : nil
        )
    }

    /// 원본 한계 · 판정 불가 안내 — 결과물 옆 짧은 꼴 (viewdata-map 3절 ⑤). 리포트의 G1 에서.
    static func gateTip(_ o: OutputRecord) -> String? {
        guard let json = o.reviewReport,
              let report = try? JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8)),
              case .string(let g1)? = report["G1"] else { return nil }
        switch g1 {
        case "sourceLimited:subjectTooSmallLowResolution": return Copy.Gate.tipResolution
        case let x where x.hasPrefix("sourceLimited"): return Copy.Gate.tipCloser
        case "cannotJudge:subjectNotFound": return Copy.Gate.tipBackground
        case "cannotJudge:subjectAlreadyCropped": return Copy.Gate.tipWholeBody
        default: return nil
        }
    }

    /// ⑧ 고른 결과물을 이전 판과 나란히 — 같은 촬영본에서 **바로 앞에 보여 준** 결과물과 견준다.
    /// 달라진 점: 그 판을 만든 AI 의 말(채팅 수정) · 길이 · 장면 수 · 자막 자리. 이전이 없으면 첫 결과물이다.
    static func resultDetail(_ s: LibrarySnapshot, outputID: String) -> ResultDetail? {
        guard let o = s.outputs.first(where: { $0.id == outputID && $0.verdict == .shown }),
              let rec = s.compositions.first(where: { $0.id == o.compositionId }),
              let video = s.videos.first(where: { $0.id == rec.videoId }),
              let current = resultRef(o, s) else { return nil }
        let comps = Set(s.compositions(of: video.id).map(\.id))
        let earlier = s.outputs.filter { $0.verdict == .shown && comps.contains($0.compositionId) && $0.createdAt < o.createdAt }
            .max { $0.createdAt < $1.createdAt }
        guard let earlier, let previous = resultRef(earlier, s),
              let a = try? s.compositions.first(where: { $0.id == earlier.compositionId })?.composition(),
              let b = try? rec.composition() else {
            return ResultDetail(shotTitle: shotTitle(video, s), current: current)
        }
        var lines: [EditSummary.Line] = []
        // 이 판을 만든 채팅 수정에서 AI 가 한 말 — "무엇을 바꿨는지" 를 사람 말로 가장 잘 적은 것
        let version = s.versionRoot(of: rec.id)?.id ?? rec.id
        if let said = s.chats.last(where: { $0.kind == .assistant && $0.compositionId == version })?.text, !said.isEmpty {
            lines.append(.init(label: firstSentence(said), value: ""))
        }
        if Copy.duration(a.duration) != Copy.duration(b.duration) {
            lines.append(.init(label: Copy.Plan.Info.length,
                               value: Copy.Plan.Info.lengthChange(from: Copy.duration(a.duration), to: Copy.duration(b.duration))))
        }
        if a.scenes.count != b.scenes.count {
            lines.append(.init(label: Copy.Plan.Info.scenes,
                               value: Copy.Plan.Info.lengthChange(from: "\(a.scenes.count)", to: "\(b.scenes.count)")))
        }
        if a.captionSlot != b.captionSlot {
            lines.append(.init(label: Copy.Plan.Info.caption, value: captionSlot(b.captionSlot).label))
        }
        return ResultDetail(shotTitle: shotTitle(video, s), current: current, previous: previous, changes: lines)
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

    /// 편집안 화면. `viewing` 은 사람이 고른 판(판 고르기 · 직접 고친 판) — 없으면 가장 최근에 보여 준 판.
    static func plan(_ s: LibrarySnapshot, videoID: String, ai: AIConnection, viewing: String? = nil,
                     modelReady: Bool = true) -> PlanState? {
        guard let video = s.videos.first(where: { $0.id == videoID }) else { return nil }
        let versions = s.visibleVersions(of: videoID)
        let live = s.liveJobs(of: videoID)
        let shown = versions.filter { s.shownOutput(forVersion: $0.id) != nil }
        let current = viewing.flatMap { id in versions.first { $0.id == id } } ?? shown.last

        if let current {
            let view = planView(current, video: video, versions: versions, s)
            // 이 판(또는 그 뒤 새 판)을 만드는 중 — 목록은 그대로, 읽기 전용
            let makingIDs = live.filter { $0.kind == .render || $0.kind == .selfEval }.compactMap { s.versionRoot(of: $0.targetId)?.id }
            let newer = versions.last.flatMap { $0.id != current.id && viewing == nil ? $0 : nil }
            if let target = makingIDs.contains(current.id) ? current : (newer.flatMap { n in makingIDs.contains(n.id) || live.contains { $0.kind == .chat } ? n : nil }) {
                let reviewing = live.contains { $0.kind == .selfEval } || s.outputs.contains { s.versionRoot(of: $0.compositionId)?.id == target.id }
                let steps = [
                    PrepareStep(title: Copy.Plan.Making.encode, state: reviewing ? .done : .running),
                    PrepareStep(title: Copy.Plan.Making.review, state: reviewing ? .running : .waiting),
                ]
                let fraction = s.progress.first { s.versionRoot(of: $0.key)?.id == target.id }?.value ?? 0
                return .making(view, MakingProgress(fraction: fraction, steps: steps))
            }
            if s.shownOutput(forVersion: current.id) == nil, gaveUp(current.id, s) {
                return gaveUpState(current.id, view: view, s)
            }
            return .ready(view)
        }

        if versions.isEmpty && live.isEmpty {
            // 짜다가 멈췄다 — 오늘 실패한 작업 (viewdata-map 3절 ②)
            let failed = s.jobs.filter { $0.state == .failed && $0.targetId == videoID && $0.error != "멈춤" }.last
            if let failed, failed.kind == .agent {
                return .stopped(plan: nil, reason: Copy.AI.aiDraftFailed + " " + failureReason(failed.error, ai: ai),
                                actions: stoppedActions, isFinal: false)
            }
            if let failed, failed.kind == .analyze {
                return .stopped(plan: nil, reason: Copy.AI.analyzeFailed, actions: stoppedActions, isFinal: false)
            }
            switch ai {
            case .none: return .noAI
            case .notLoggedIn(let product): return .notLoggedIn(product)
            default: break
            }
        }
        // 판은 있는데 보여 준 것이 없고 더 도는 것도 없다 — 두 번 다듬어도 안 됐다
        if let newest = versions.last, live.isEmpty, gaveUp(newest.id, s) {
            return gaveUpState(newest.id, view: planView(newest, video: video, versions: versions, s), s)
        }
        return .preparing(prepareSteps(live, fetchingOriginal: video.status == .importing, modelReady: modelReady,
                                       fetchProgress: s.importProgress[video.id],
                                       analysis: live.contains { $0.kind == .analyze } ? s.analysisProgress[video.id] : nil,
                                       now: s.now))
    }

    static var stoppedActions: [ChatChoice] {
        [ChatChoice(title: Copy.Plan.Stopped.tryAgain, detail: Copy.Plan.Stopped.tryAgainDetail, isPrimary: true),
         ChatChoice(title: Copy.Plan.Stopped.pickAnother, detail: Copy.Plan.Stopped.pickAnotherDetail)]
    }

    /// 사람이 본 판 하나에서 나온 결과물이 전부 끝내 실패(verdict failed)인가.
    static func gaveUp(_ versionID: String, _ s: LibrarySnapshot) -> Bool {
        let outs = s.outputs.filter { s.versionRoot(of: $0.compositionId)?.id == versionID }
        return !outs.isEmpty && outs.contains { $0.verdict == .failed } && !outs.contains { $0.verdict == .shown }
    }

    /// 끝내 기준 미달 — **붉은색은 여기뿐** (`isFinal`). 이유는 인물 크기(하드 G1) 기준으로 말한다.
    static func gaveUpState(_ versionID: String, view: PlanView, _ s: LibrarySnapshot) -> PlanState {
        .stopped(plan: view,
                 reason: Copy.Review.reviewGaveUp(reason: Copy.Review.gaveUpReasonSmall, tip: Copy.Review.gaveUpTipCloser),
                 actions: [ChatChoice(title: Copy.Plan.Stopped.pickAnother, detail: Copy.Plan.Stopped.pickAnotherDetail)],
                 isFinal: true)
    }

    /// 작업 실패 문장(개발자 말)을 사람 말 이유로 — 한도 · 로그인 · 모름.
    static func failureReason(_ error: String?, ai: AIConnection) -> String {
        let e = (error ?? "").lowercased()
        if e.contains("limit") || e.contains("한도") || e.contains("quota") { return Copy.AI.reasonLimit }
        if e.contains("login") || e.contains("로그인") || e.contains("auth") {
            let product: AIProduct = { if case .codex = ai { return .codex }; if case .notLoggedIn(let p) = ai { return p }; return .claude }()
            return Copy.AI.reasonLoggedOut(product.name)
        }
        return Copy.AI.reasonUnknown
    }

    /// 짜는 중 단계 — **엔진이 실제로 도는 순서** (디자인 답 2026-09-28, viewdata-map 5절):
    /// 영상 받기(iCloud 원본을 받아야 할 때만) → 편집 준비(준비가 안 끝났을 때만) → 말 받아적기 → 사람 찾기 → 장면 나누기.
    /// 검사 전 렌더 · 되먹임은 "장면 나누기" 가 끝난 뒤 — 사람에게는 아직 짜는 중이다 (결정 ① 검사한 결과만 보여 준다).
    /// 준비 단계 줄. 도는 단계는 잴 수 있으면 퍼센트(받기 · 받아적기 · 사람 찾기), 못 재면 지난 시간(AI 장면 나누기).
    /// 분석은 받아적기 → 사람 찾기 → 소리 · 컷 순서로 **하나씩** 돈다 — 둘을 같이 "도는 중" 으로 그리지 않는다.
    static func prepareSteps(_ live: [JobRecord], fetchingOriginal: Bool = false, modelReady: Bool = true,
                             fetchProgress: Double? = nil, analysis: AnalysisProgress? = nil,
                             now: Date = Date()) -> [PrepareStep] {
        let kinds = Set(live.map(\.kind))
        let rendering = kinds.contains(.render) || kinds.contains(.selfEval)
        let agent = live.first { $0.kind == .agent }
        // 몇 번째 단계인가 (0 받아적기 · 1 사람 찾기 · 2 장면 나누기 · 3 끝)
        let stage: Int = {
            if rendering { return 3 }
            if agent != nil { return 2 }
            switch analysis?.step {
            case .findPerson?, .rest?: return 1
            default: return 0
            }
        }()
        var steps: [PrepareStep] = []
        if fetchingOriginal {
            steps.append(PrepareStep(title: Copy.Plan.Preparing.fetchOriginal, state: .running, progress: fetchProgress))
        }
        if !modelReady { steps.append(PrepareStep(title: Copy.Plan.Preparing.prepare, state: fetchingOriginal ? .waiting : .running)) }
        let blocked = fetchingOriginal || !modelReady
        let titles = [Copy.Plan.Preparing.transcribe, Copy.Plan.Preparing.findPerson, Copy.Plan.Preparing.split]
        for (i, t) in titles.enumerated() {
            if blocked { steps.append(PrepareStep(title: t, state: .waiting)); continue }
            if i < stage { steps.append(PrepareStep(title: t, state: .done)); continue }
            if i > stage { steps.append(PrepareStep(title: t, state: .waiting)); continue }
            var step = PrepareStep(title: t, state: .running)
            switch i {
            case 0: step.progress = analysis?.step == .transcribe ? analysis?.fraction : (analysis == nil ? nil : 1)
            // "사람 찾기" 줄이 뒤의 소리 · 컷 찾기까지 맡는다 (7할 · 3할) — 100% 에 멈춰 있지 않게
            case 1:
                switch analysis?.step {
                case .findPerson?: step.progress = 0.7 * (analysis?.fraction ?? 0)
                case .rest?: step.progress = 0.7 + 0.3 * (analysis?.fraction ?? 0)
                default: break
                }
            default:
                if let started = agent?.startedAt { step.elapsed = Copy.Plan.Preparing.elapsed(max(0, Int(now.timeIntervalSince(started)))) }
            }
            steps.append(step)
        }
        return steps
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
            },
            // ⑨ 툴바 "결과물 n개" 가 열 결과물 — 이 판의 보여 준 결과물, 없으면 이 영상의 가장 최근 것
            latestResultID: (s.shownOutput(forVersion: rec.id) ?? results(of: video.id, s).first.flatMap { r in s.outputs.first { $0.id == r.id } })?.id,
            // 편집안 자리에서 재생 — 이 판의 보여 준 결과물 (내보낸 mp4, 자막 포함). 아직 안 만든 판이면 썸네일
            previewURL: s.shownOutput(forVersion: rec.id).flatMap { FileManager.default.fileExists(atPath: $0.path) ? URL(fileURLWithPath: $0.path) : nil }
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
    /// 두 번 다듬어도 소프트 항목이 남은 결과물 — 채팅 한 줄 (`reviewSoftNote`, viewdata-map 5절 2절 4).
    /// G11(길이) 은 짧다 · 길다를 가르고, G8(훅) 은 첫 1초. G9 는 문구가 없어 내지 않는다.
    static func softNote(_ o: OutputRecord) -> String? {
        guard let json = o.reviewReport,
              let report = try? JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8)),
              case .array(let items)? = report["selfEval"] else { return nil }
        let names = items.compactMap { if case .string(let x) = $0 { x } else { nil } }
        if names.contains("G11"), case .number(let ratio)? = report["G11.ratio"] {
            return Copy.Review.reviewSoftNote(ratio < 1 ? Copy.Review.softShort : Copy.Review.softLong)
        }
        if names.contains("G8") { return Copy.Review.reviewSoftNote(Copy.Review.softHook) }
        return nil
    }

    static func chat(_ s: LibrarySnapshot, videoID: String) -> [ChatMessage] {
        var out: [ChatMessage] = []
        // 첫 초안의 결과물에 아쉬운 점이 남았으면 대화 맨 앞에 한 줄
        if let draft = s.visibleVersions(of: videoID).first(where: { $0.origin == .draft }),
           let o = s.shownOutput(forVersion: draft.id), let note = softNote(o) {
            out.append(ChatMessage(id: o.id + ".soft", kind: .assistant(note), stamp: Copy.shotStamp(o.createdAt, now: s.now)))
        }
        for row in s.chats where row.videoId == videoID {
            let stamp = Copy.shotStamp(row.createdAt, now: s.now)
            switch row.kind {
            case .creator: out.append(ChatMessage(id: row.id, kind: .user(row.text ?? ""), stamp: stamp))
            case .creatorNotSent: out.append(ChatMessage(id: row.id, kind: .userNotSent(row.text ?? ""), stamp: stamp))
            case .assistant:
                out.append(ChatMessage(id: row.id, kind: .assistant(plain(row.text ?? "")), stamp: stamp))
                // 이 말로 생긴 판의 결과물이 보여지면 카드로 붙는다
                if let cid = row.compositionId, let o = s.shownOutput(forVersion: cid), let ref = resultRef(o, s) {
                    out.append(ChatMessage(id: row.id + ".result", kind: .result(ref)))
                    if let note = softNote(o) { out.append(ChatMessage(id: row.id + ".soft", kind: .assistant(note))) }
                }
            case .choices:
                // "앞으로도 이렇게 할까요?" — 답한 것은 다시 보이지 않는다. 버튼 설명 칸에 AI 가 다듬은 규칙 문장
                let values = row.payloadValues
                guard values["answered"] == nil, case .string(let rule)? = values["rule"] else { continue }
                out.append(ChatMessage(id: row.id + ".ask", kind: .assistant(Copy.Remember.askRemember), stamp: stamp))
                out.append(ChatMessage(id: row.id, kind: .choices([
                    ChatChoice(title: Copy.Remember.rememberYes, detail: rule, isPrimary: true),
                    ChatChoice(title: Copy.Remember.rememberNo),
                ])))
            case .notice:
                if case .string(let key)? = row.payloadValues["key"], key == Chat.Key.aiDraftFailed {
                    out.append(ChatMessage(id: row.id, kind: .assistant(Copy.AI.aiEditFailed), stamp: stamp))
                }
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
