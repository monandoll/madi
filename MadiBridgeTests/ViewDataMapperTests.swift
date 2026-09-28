import Testing
import Foundation
@testable import MadiKit
@testable import MadiBridgeTests

/// 바꾸는 층 — DB 상태마다 화면 값 (docs/stage-6.spec.md 6번 · `docs/design/viewdata-map.md` 1절).
struct ViewDataMapperTests {

    let now = ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")!

    func video(_ id: String, at: Date, status: VideoRecord.Status = .ready) -> VideoRecord {
        VideoRecord(id: id, source: .photos, sourceRef: id, durationSec: 60, capturedAt: at, status: status)
    }

    func comp(_ id: String, video: String = "v", title: String = "골반 스트레칭", scenes: [(Double, Double)] = [(0, 3), (3.5, 6)],
              origin: CompositionRecord.Origin = .draft, revisionOf: String? = nil, at: Date) throws -> CompositionRecord {
        let c = Composition(
            id: id, videoID: video, templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(title: title, targetDurationSec: 6), captionSlot: .lowerBody,
            scenes: scenes.enumerated().map { i, r in
                Scene(id: "s\(i + 1)", role: i == 0 ? .hook : .demo, source: Scene.Source(videoID: video, start: r.0, end: r.1),
                      captions: [Caption(id: "c\(i)a", start: 0, end: 1, text: "첫 덩어리\(i)", secondary: "first\(i)"),
                                 Caption(id: "c\(i)b", start: 1, end: 2, text: "둘째\(i)")])
            },
            revisionOf: revisionOf
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601      // 엔진(saveComposition)과 같은 꼴
        let json = String(decoding: try encoder.encode(c), as: UTF8.self)
        return CompositionRecord(id: id, videoId: video, json: json, revisionOf: revisionOf, createdAt: at, origin: origin)
    }

    func output(_ id: String, comp: String, verdict: OutputRecord.Verdict, at: Date) -> OutputRecord {
        OutputRecord(id: id, compositionId: comp, path: "/tmp/\(id).mp4", reviewReport: nil, arch: "arm64", createdAt: at, verdict: verdict)
    }

    func job(_ kind: JobRecord.Kind, _ target: String, _ state: JobRecord.State) -> JobRecord {
        var j = JobRecord(kind: kind, targetId: target, createdAt: now)
        j.state = state
        j.id = Int64.random(in: 1...1_000_000)
        return j
    }

    @Test("갤러리 — 비면 empty, 사진 권한이 없고 비면 noPhotoAccess, 받는 중이면 importing")
    func galleryStates() {
        #expect(ViewDataMapper.gallery(LibrarySnapshot(now: now), photos: .granted) == .empty)
        #expect(ViewDataMapper.gallery(LibrarySnapshot(now: now), photos: .denied) == .noPhotoAccess)
        let s = LibrarySnapshot(videos: [video("a", at: now), video("b", at: now, status: .importing)], now: now)
        guard case .importing(let done, let total, _) = ViewDataMapper.gallery(s, photos: .granted) else { Issue.record("importing 아님"); return }
        #expect(done == 1 && total == 2)
    }

    @Test("갤러리 묶음 — 오늘 · 이번 주 · 지난주 · 그 전, 최근 먼저")
    func groups() {
        let day: TimeInterval = 86400
        let s = LibrarySnapshot(videos: [
            video("old", at: now - 40 * day), video("today", at: now - 3600), video("lastweek", at: now - 8 * day),
        ], now: now)
        let g = ViewDataMapper.shotGroups(s)
        #expect(g.map(\.title).first == Copy.Gallery.Group.today)
        #expect(g.first?.shots.map(\.id) == ["today"])
        #expect(g.last?.title == Copy.Gallery.Group.earlier)
    }

    @Test("숨김 · 끝내 실패한 결과물은 어디에도 안 나온다 — 보여 준 것만 (§10 검사한 결과만)")
    func onlyShown() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("d", at: now - 60), try comp("r1", origin: .selfEval, revisionOf: "d", at: now - 30)],
            outputs: [output("o_d", comp: "d", verdict: .hidden, at: now - 50), output("o_r1", comp: "r1", verdict: .shown, at: now - 20)],
            now: now
        )
        let refs = ViewDataMapper.results(of: "v", s)
        #expect(refs.map(\.id) == ["o_r1"])
        // 되먹임 판의 결과물은 그 판이 나온 사람이 본 판(편집안 1)의 이름을 쓴다
        #expect(refs.first?.planLabel == Copy.Plan.version(1))
        #expect(ViewDataMapper.studio(s, studioName: "스튜디오", ai: .claude).resultCount == 1)
    }

    @Test("편집안 — 되먹임 판은 번호를 받지 않고, 장면 카드는 첫 덩어리 · 나머지 · 영문 · 쉬는 구간")
    func planReady() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("d", at: now - 60), try comp("r1", origin: .selfEval, revisionOf: "d", at: now - 30)],
            outputs: [output("o_r1", comp: "r1", verdict: .shown, at: now - 20)],
            now: now
        )
        guard case .ready(let plan) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else { Issue.record("ready 아님"); return }
        #expect(plan.versionLabel == Copy.Plan.version(1) && plan.versionCount == 1)
        #expect(plan.shotTitle == "골반 스트레칭")
        #expect(plan.captionSlot == .lowerBody)
        let first = try #require(plan.scenes.first)
        #expect(first.caption == "첫 덩어리0" && first.secondary == "first0" && first.moreCaptions == ["둘째0"])
        #expect(first.role == .hook)
        #expect(abs((first.removedGapAfter ?? 0) - 0.5) < 0.001)     // 3.0 → 3.5
    }

    @Test("편집안 — 보여 줄 판이 없으면 짜는 중(단계), AI 도 없고 판도 없으면 noAI")
    func planPreparing() throws {
        let only = LibrarySnapshot(videos: [video("v", at: now)], now: now)
        #expect(ViewDataMapper.plan(only, videoID: "v", ai: .none) == .noAI)

        let drafting = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.agent, "v", .running)], now: now)
        guard case .preparing(let steps) = try #require(ViewDataMapper.plan(drafting, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        // 단계는 엔진 순서 (디자인 답 2026-09-28): 말 받아적기 → 사람 찾기 → 장면 나누기
        #expect(steps.map(\.title) == [Copy.Plan.Preparing.transcribe, Copy.Plan.Preparing.findPerson, Copy.Plan.Preparing.split])
        #expect(steps.map(\.state) == [.done, .done, .running])

        let analyzing = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.analyze, "v", .running)], now: now)
        guard case .preparing(let a) = try #require(ViewDataMapper.plan(analyzing, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(a.map(\.state) == [.running, .running, .waiting])
        // 편집 준비가 안 끝났으면 맨 앞에 "편집 준비", 나머지는 기다린다
        let first = ViewDataMapper.prepareSteps([job(.analyze, "v", .running)], modelReady: false)
        #expect(first.first?.title == Copy.Plan.Preparing.prepare && first.dropFirst().allSatisfy { $0.state == .waiting })

        // 초안은 있는데 검사 전 렌더 중 — 아직 보여 주지 않는다
        let rendering = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now)],
                                        jobs: [job(.render, "d", .running)], now: now)
        guard case .preparing(let s2) = try #require(ViewDataMapper.plan(rendering, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(s2.allSatisfy { $0.state == .done })      // 짜기는 끝났다 — 검사 전 렌더 중
    }

    @Test("채팅 — 크리에이터 · AI 말, 고친 판이 보여지면 결과물 카드. 선택지 · 알림은 문구가 생길 때까지 안 낸다")
    func chat() throws {
        let rows = [
            ChatRecord(id: "m1", videoId: "v", kind: .creator, text: "줄여 줘", createdAt: now - 40),
            ChatRecord(id: "m2", videoId: "v", kind: .assistant, text: "줄였어요", compositionId: "c1", createdAt: now - 30),
            ChatRecord(id: "m3", videoId: "v", kind: .choices, payload: ["ask": .string("askRemember")], createdAt: now - 29),
        ]
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("d", at: now - 60), try comp("c1", origin: .chat, revisionOf: "d", at: now - 30)],
            outputs: [output("o", comp: "c1", verdict: .shown, at: now - 10)],
            chats: rows, now: now
        )
        let kinds = ViewDataMapper.chat(s, videoID: "v").map(\.kind)
        #expect(kinds.count == 3)
        #expect(kinds[0] == .user("줄여 줘") && kinds[1] == .assistant("줄였어요"))
        guard case .result(let ref) = kinds[2] else { Issue.record("결과물 카드 아님"); return }
        #expect(ref.planLabel == Copy.Plan.version(2))
    }

    @Test("만드는 중 — 도는 것 먼저, 기다리는 것은 메모, 오늘 보여 준 결과물")
    func making() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("a", at: now - 60), try comp("b", at: now - 50)],
            outputs: [output("o", comp: "a", verdict: .shown, at: now - 5)],
            jobs: [job(.render, "b", .queued), job(.render, "a", .running)],
            now: now
        )
        guard case .loaded(let jobs, let done) = ViewDataMapper.making(s) else { Issue.record(""); return }
        guard case .running = jobs.first?.state else { Issue.record("도는 것이 먼저가 아니다"); return }
        guard case .queued = jobs.last?.state else { Issue.record(""); return }
        #expect(done.map(\.id) == ["o"])
    }

    @Test("그림 · 진행률 — 있는 그림만 넘기고, 도는 렌더에 진행률을 붙인다")
    func thumbsAndProgress() throws {
        var s = LibrarySnapshot(
            videos: [video("v", at: now)], compositions: [try comp("a", at: now - 60)],
            jobs: [job(.render, "a", .running)], now: now
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: "thumbs-\(UUID().uuidString)")
        let store = Thumbnails(root: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: store.video("v"))
        s.attach(thumbnails: store, progress: ["a": 0.4])
        let shot = ViewDataMapper.shot(s.videos[0], s)
        #expect(shot.thumbnail.fileURL == store.video("v"))
        guard case .loaded(let jobs, _) = ViewDataMapper.making(s), case .running(let p) = jobs.first?.state else { Issue.record(""); return }
        #expect(p.fraction == 0.4)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("결과물 — 안 본 것은 새 것, 사진 앱으로 보낸 이력 한 줄")
    func seenAndExported() throws {
        var o = output("o", comp: "d", verdict: .shown, at: now - 10)
        let s1 = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], outputs: [o], now: now)
        #expect(ViewDataMapper.results(of: "v", s1).first?.isNew == true)
        o.seenAt = now
        let s2 = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], outputs: [o], now: now,
                                 exports: [ExportRecord(outputId: "o", target: .photos, location: "x", createdAt: now)])
        let ref = try #require(ViewDataMapper.results(of: "v", s2).first)
        #expect(ref.isNew == false)
        #expect(ref.exportedNote == Copy.Results.Export.historyLine(target: Copy.Results.Export.photos, when: Copy.time(now)))
    }

    @Test("멈춘 편집안 — 짜다 실패(편집안 없음) · 로그인 필요 · 두 번 다듬어도 안 됨(isFinal)")
    func stoppedStates() throws {
        var failed = job(.agent, "v", .failed)
        failed.error = "AI 턴 실패: You've hit your usage limit."
        failed.finishedAt = now
        let s1 = LibrarySnapshot(videos: [video("v", at: now)], jobs: [failed], now: now)
        guard case .stopped(let p, let reason, let actions, let isFinal) = try #require(ViewDataMapper.plan(s1, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(p == nil && !isFinal)
        #expect(reason.contains(Copy.AI.reasonLimit))
        #expect(actions.first?.title == Copy.Plan.Stopped.tryAgain)

        let s2 = LibrarySnapshot(videos: [video("v", at: now)], now: now)
        #expect(ViewDataMapper.plan(s2, videoID: "v", ai: .notLoggedIn(.codex)) == .notLoggedIn(.codex))

        let s3 = LibrarySnapshot(videos: [video("v", at: now)],
                                 compositions: [try comp("d", at: now - 60), try comp("r", origin: .selfEval, revisionOf: "d", at: now - 30)],
                                 outputs: [output("o1", comp: "d", verdict: .hidden, at: now - 50), output("o2", comp: "r", verdict: .failed, at: now - 20)],
                                 now: now)
        guard case .stopped(let plan, _, _, let final) = try #require(ViewDataMapper.plan(s3, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(final && plan?.id == "d")
    }

    @Test("고른 판을 보여 준다 — 사람이 직접 고친 판(결과물 없음)도 ready")
    func viewing() throws {
        let s = LibrarySnapshot(videos: [video("v", at: now)],
                                compositions: [try comp("d", at: now - 60), try comp("e", origin: .chat, revisionOf: "d", at: now - 10)],
                                outputs: [output("o", comp: "d", verdict: .shown, at: now - 50)], now: now)
        guard case .ready(let def) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(def.id == "d")
        guard case .ready(let edited) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude, viewing: "e")) else { Issue.record(""); return }
        #expect(edited.id == "e" && edited.versionLabel == Copy.Plan.version(2))
    }

    @Test("채팅 '앞으로도?' — 규칙 문장은 버튼 설명에, 답하면 사라진다 · 받기 실패 · 원본 한계 안내")
    func remembersAndNotices() throws {
        let ask = ChatRecord(id: "q", videoId: "v", kind: .choices, payload: ["ask": .string("askRemember"), "rule": .string("영상은 15초 안팎으로")], createdAt: now)
        let s = LibrarySnapshot(videos: [video("v", at: now, status: .failed)], chats: [ask], now: now)
        let msgs = ViewDataMapper.chat(s, videoID: "v").map(\.kind)
        #expect(msgs.first == .assistant(Copy.Remember.askRemember))
        guard case .choices(let c) = msgs.last else { Issue.record(""); return }
        #expect(c.first?.title == Copy.Remember.rememberYes && c.first?.detail == "영상은 15초 안팎으로")
        var answered = ask
        answered.payload = #"{"ask":"askRemember","rule":"x","answered":true}"#
        #expect(ViewDataMapper.chat(LibrarySnapshot(videos: [video("v", at: now)], chats: [answered], now: now), videoID: "v").isEmpty)

        #expect(ViewDataMapper.shot(s.videos[0], s).problem == Copy.Photos.importFailedShort)

        var o = output("o", comp: "d", verdict: .shown, at: now)
        o.reviewReport = #"{"G1":"sourceLimited:subjectTooSmallLowResolution"}"#
        #expect(ViewDataMapper.gateTip(o) == Copy.Gate.tipResolution)
    }

    @Test("숨긴 촬영본은 목록 · 개수에서 빠진다 · 받는 중 진행률 · 아쉬운 점 한 줄")
    func hiddenProgressSoft() throws {
        var hidden = video("h", at: now)
        hidden.hiddenAt = now
        var s = LibrarySnapshot(videos: [video("v", at: now, status: .importing), hidden], now: now)
        s.importProgress = ["v": 0.3]
        guard case .importing(_, _, let groups) = ViewDataMapper.gallery(s, photos: .granted) else { Issue.record(""); return }
        #expect(groups.flatMap(\.shots).map(\.id) == ["v"])
        #expect(groups.first?.shots.first?.fetchProgress == 0.3)
        #expect(ViewDataMapper.studio(s, studioName: "", ai: .claude).shotCount == 1)

        var o = output("o", comp: "d", verdict: .shown, at: now)
        o.reviewReport = #"{"selfEval":["G11"],"G11.ratio":0.7}"#
        let s2 = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], outputs: [o], now: now)
        #expect(ViewDataMapper.chat(s2, videoID: "v").first?.kind == .assistant(Copy.Review.reviewSoftNote(Copy.Review.softShort)))
    }

    @Test("자막 모양 — 굵기 4단계 대응(480 = 조금 굵게), 가까운 견본, 고른 것 얹기, 영문 줄 같이 바꾸기")
    func look() throws {
        var l = try StyleStore.load().values.look
        let cl = LookMapper.look(l, fonts: ["나눔고딕"], labels: ["white": "흰색"], preview: .none)
        #expect(cl.weight == .medium && cl.fill == "white" && cl.secondaryFill == "yellow" && cl.secondarySameAsMain)
        l = LookMapper.apply(.font("나눔고딕"), to: l)
        #expect(l.caption.fontFamily == "나눔고딕" && l.secondary.fontFamily == "나눔고딕")   // 같이 쓰는 중이라 영문도
        l = LookMapper.apply(.weight(.heavy), to: l)
        #expect(l.caption.weight == 900)
        l = LookMapper.apply(.fill("sky"), to: l)
        #expect(LookMapper.nearest(l.caption.fill) == "sky")
        #expect(LookMapper.look(l, fonts: [], labels: [:], preview: .none).fontMissing)   // 이 Mac 에 없는 글꼴
    }

    @Test("⑧ 고른 결과물 — 바로 앞에 보여 준 결과물과 나란히, 달라진 점(AI 말 · 길이 · 장면 수). ⑨ 판의 가장 최근 결과물 id")
    func resultDetail() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("d", at: now - 60), try comp("c", scenes: [(0, 3)], origin: .chat, revisionOf: "d", at: now - 30)],
            outputs: [output("o1", comp: "d", verdict: .shown, at: now - 50), output("o2", comp: "c", verdict: .shown, at: now - 20)],
            chats: [ChatRecord(videoId: "v", kind: .assistant, text: "마지막 장면을 뺐어요", compositionId: "c", createdAt: now - 25)],
            now: now
        )
        let d = try #require(ViewDataMapper.resultDetail(s, outputID: "o2"))
        #expect(d.current.id == "o2" && d.previous?.id == "o1")
        #expect(d.changes.first?.label == "마지막 장면을 뺐어요")
        #expect(d.changes.contains { $0.label == Copy.Plan.Info.scenes && $0.value == Copy.Plan.Info.lengthChange(from: "2", to: "1") })
        #expect(ViewDataMapper.resultDetail(s, outputID: "o1")?.previous == nil)   // 첫 결과물

        guard case .ready(let plan) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(plan.latestResultID == "o2")
    }

    @Test("AI 말의 마크다운 기호를 걷는다 — 말풍선에 ** · - 가 보이지 않는다")
    func plainStripsMarkdown() {
        let said = "헬스장 영상이에요.\n\n- **말소리:** 거의 없어요.\n## 화면\n작게 나와요."
        #expect(ViewDataMapper.plain(said) == "헬스장 영상이에요.\n\n· 말소리: 거의 없어요.\n화면\n작게 나와요.")
    }

    @Test("달라진 점에는 AI 말의 첫 문장만")
    func firstSentenceOnly() {
        #expect(ViewDataMapper.firstSentence("쉬는 구간 2곳을 뺐어요. 나머지는 그대로예요.") == "쉬는 구간 2곳을 뺐어요.")
        let long = String(repeating: "가", count: 80)
        #expect(ViewDataMapper.firstSentence(long).count == 60)
    }

    @Test("AI 가 제목을 안 적었으면 첫 자막으로 이름을 짓는다 — 촬영 시각보다 먼저")
    func titleFallsBackToCaptions() throws {
        let s = LibrarySnapshot(videos: [video("v", at: now)],
                                compositions: [try comp("c1", title: "", at: now)], now: now)
        #expect(ViewDataMapper.title(of: "v", s) == "첫 덩어리0 둘째0 첫 덩어리1 둘째1")
    }
}
