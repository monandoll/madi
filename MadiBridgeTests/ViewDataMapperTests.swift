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
        // 아직 연결 전이면 "찍으면 자동으로 들어와요" 가 아니라 먼저 연결하라고 한다
        #expect(ViewDataMapper.gallery(LibrarySnapshot(now: now), photos: .notAsked) == .connectPhotos)
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

        // 넣자마자 도는 분석만 있고 요청이 없으면 — 묻는다 (짜는 중이 아니다). 요청이 오면 그때부터 짜는 중
        let prepOnly = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.analyze, "v", .running)], now: now)
        // (사진 보관함 영상은 원본 받기가 앞 3할 — 분석이 막 시작했으면 0.3)
        #expect(ViewDataMapper.plan(prepOnly, videoID: "v", ai: .claude) == .asking(preparing: 0.3))
        let asked = ChatRecord(id: "q", videoId: "v", kind: .creator, text: "알아서 만들어줘", createdAt: now)
        let analyzing = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.analyze, "v", .running)], chats: [asked], now: now)
        guard case .preparing(let a) = try #require(ViewDataMapper.plan(analyzing, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        // 받아적기 · 사람 찾기는 같이 돈다
        #expect(a.map(\.state) == [.running, .running, .waiting])
        // 진행률이 있으면 도는 단계마다 퍼센트
        var withProgress = analyzing
        withProgress.analysisProgress["v"] = AnalysisProgress(transcribe: 0.42, findPerson: 0.1)
        guard case .preparing(let p1) = try #require(ViewDataMapper.plan(withProgress, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(p1[0].progress == 0.42 && p1[1].progress == 0.1)
        withProgress.analysisProgress["v"] = AnalysisProgress(transcribe: 1, findPerson: 0.5)
        guard case .preparing(let p2) = try #require(ViewDataMapper.plan(withProgress, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(p2.map(\.state) == [.done, .running, .waiting] && p2[1].progress == 0.5)
        #expect(Copy.Plan.Preparing.percent(0.427) == "42%")
        // AI 가 장면을 나누는 중 — 퍼센트 대신 지난 시간
        var agentJob = job(.agent, "v", .running); agentJob.startedAt = now - 32
        let ai = ViewDataMapper.prepareSteps([agentJob], now: now)
        #expect(ai[2].state == .running && ai[2].elapsed == "32초째" && ai[2].progress == nil)
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

    @Test("채팅으로 새 판이 생기면 AI 말 밑에 달라진 점 카드 — 편집안 번호 · 길이 · 장면 수 · 되돌리기")
    func chatEditSummary() throws {
        let rows = [
            ChatRecord(id: "m1", videoId: "v", kind: .creator, text: "줄여 줘", createdAt: now - 40),
            ChatRecord(id: "m2", videoId: "v", kind: .assistant, text: "줄였어요", compositionId: "c1", createdAt: now - 30),
        ]
        let s = LibrarySnapshot(
            videos: [video("v", at: now)],
            compositions: [try comp("d", scenes: [(0, 3), (3.5, 6), (7, 10)], at: now - 60),
                           try comp("c1", scenes: [(0, 3), (3.5, 6)], origin: .chat, revisionOf: "d", at: now - 30)],
            chats: rows, now: now
        )
        let kinds = ViewDataMapper.chat(s, videoID: "v").map(\.kind)
        #expect(kinds.count == 3)
        guard case .summary(let card) = kinds[2] else { Issue.record("달라진 점 카드 아님"); return }
        #expect(card.canUndo)
        #expect(card.versionLabel == Copy.Plan.version(2))
        #expect(card.lines.map(\.label) == [Copy.Plan.Info.length, Copy.Plan.Info.scenes])
        #expect(card.lines.last?.value == Copy.Plan.Info.lengthChange(from: "3", to: "2"))
    }

    @Test("채팅 날짜 줄 — 대화가 끊겼다 이어질 때만 (첫 말 · 30분 넘게 쉼 · 날이 바뀜). '오늘 오후 2:20' 꼴")
    func chatStamps() throws {
        let rows = [
            ChatRecord(id: "a", videoId: "v", kind: .creator, text: "하나", createdAt: now - 3 * 3600),
            ChatRecord(id: "b", videoId: "v", kind: .assistant, text: "둘", createdAt: now - 3 * 3600 + 20),
            ChatRecord(id: "c", videoId: "v", kind: .creator, text: "셋", createdAt: now - 60),
        ]
        let s = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 4 * 3600)], chats: rows, now: now)
        let stamps = ViewDataMapper.chat(s, videoID: "v").map(\.stamp)
        #expect(stamps[0] == Copy.chatStamp(now - 3 * 3600, now: now))
        #expect(stamps[1] == nil)                      // 20초 뒤 답 — 줄 없음
        #expect(stamps[2] != nil)                      // 3시간 쉼
        #expect(Copy.chatStamp(now, now: now).hasPrefix(Copy.Gallery.Group.today + " "))
    }

    @Test("결과물 묶음 — 같은 제목의 촬영본 둘은 따로 묶인다 (겹쳐서 한쪽 줄이 사라지지 않는다)")
    func sameTitleGroups() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now), video("w", at: now - 60)],
            compositions: [try comp("d", video: "v", at: now - 50), try comp("e", video: "w", at: now - 40)],
            outputs: [output("o1", comp: "d", verdict: .shown, at: now - 30), output("o2", comp: "e", verdict: .shown, at: now - 20)],
            now: now
        )
        guard case .loaded(let groups) = ViewDataMapper.results(s) else { Issue.record("비었다"); return }
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)).count == 2)
        #expect(groups.flatMap(\.items).count == 2)
    }

    @Test("결과물을 다 휴지통으로 보낸 판 — '준비 중' 에 갇히지 않고 그 판을 보여 준다")
    func trashedResultsShowPlan() throws {
        // 휴지통 결과물은 스냅숏에서 빠진다 → 판은 있고 결과물 · 도는 작업은 없다
        let s = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], now: now)
        guard case .ready(let plan) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else {
            Issue.record("준비 중에 갇혔다"); return
        }
        #expect(plan.id == "d" && plan.previewURL == nil)
    }

    @Test("촬영본 출처 — 폴더로 들어온 것은 사진 앱에 없다 (우클릭 'Finder에서 보기')")
    func shotSource() {
        let photos = video("p", at: now)
        let folder = VideoRecord(id: "f", source: .folder, sourceRef: "/tmp/f.mov", durationSec: 60, capturedAt: now, status: .ready)
        let s = LibrarySnapshot(videos: [photos, folder], now: now)
        #expect(ViewDataMapper.shot(photos, s).isFromPhotos)
        #expect(!ViewDataMapper.shot(folder, s).isFromPhotos)
    }

    @Test("만드는 중 — 오늘 다 만든 것에 결과물 그림을 넘긴다")
    func doneThumbnail() throws {
        var s = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)],
                                outputs: [output("o", comp: "d", verdict: .shown, at: now - 10)], now: now)
        let dir = FileManager.default.temporaryDirectory.appending(path: "thumbs-\(UUID().uuidString)")
        let store = Thumbnails(root: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: store.output("o"))
        s.attach(thumbnails: store, progress: [:])
        guard case .loaded(_, let done) = ViewDataMapper.making(s) else { Issue.record(""); return }
        #expect(done.first?.thumbnail.fileURL == store.output("o"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("만드는 중 — 도는 것 먼저, 기다리는 것은 메모, 오늘 보여 준 결과물")
    func making() throws {
        let s = LibrarySnapshot(
            videos: [video("v", at: now), video("w", at: now)],
            compositions: [try comp("a", at: now - 60), try comp("b", video: "w", at: now - 50)],
            outputs: [output("o", comp: "a", verdict: .shown, at: now - 5)],
            jobs: [job(.render, "b", .queued), job(.render, "a", .running)],
            now: now
        )
        guard case .loaded(let jobs, let done) = ViewDataMapper.making(s) else { Issue.record(""); return }
        #expect(jobs.count == 2)                                  // 촬영본마다 한 줄
        guard case .running = jobs.first?.state else { Issue.record("도는 것이 먼저가 아니다"); return }
        guard case .queued = jobs.last?.state else { Issue.record(""); return }
        #expect(done.map(\.id) == ["o"])
    }

    @Test("편집안은 있는데 만들다(렌더) 멈췄으면 '준비 중' 으로 계속 돌리지 않고 멈췄다고 말한다")
    func renderFailedStops() throws {
        var failed = job(.render, "d", .failed); failed.error = "원본 영상은 60.00초인데 60.08초 지점을 달라고 했습니다"
        let s = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now)], jobs: [failed], now: now)
        guard case .stopped(let plan, let reason, _, _) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else {
            Issue.record("멈춤으로 안 보인다"); return
        }
        #expect(plan?.id == "d" && reason == Copy.AI.renderFailed)
    }

    @Test("만드는 중 — 숏폼 만들기를 누른 순간(분석 · AI 초안)부터 촬영본이 목록에 뜬다. 분석 진행률이 전체 퍼센트에 들어간다")
    func makingFromTheStart() throws {
        // 넣자마자 도는 분석은 편집 준비다 — 만드는 중 목록 · 개수에 안 든다. 칸에는 "편집 준비 중"
        let prep = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.analyze, "v", .running)], now: now)
        #expect(ViewDataMapper.making(prep) == .empty)
        #expect(ViewDataMapper.studio(prep, studioName: "", ai: .claude).makingCount == 0)
        let cell = ViewDataMapper.shot(prep.videos[0], prep)
        #expect(cell.isPreparing && !cell.isMaking)

        // 크리에이터가 요청하면 그때부터 만드는 중
        let asked = ChatRecord(id: "q", videoId: "v", kind: .creator, text: "알아서 만들어줘", createdAt: now)
        var s = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.analyze, "v", .running)], chats: [asked], now: now)
        s.analysisProgress["v"] = AnalysisProgress(transcribe: 1, findPerson: 0.5)
        #expect(ViewDataMapper.shot(s.videos[0], s).isMaking)
        guard case .loaded(let jobs, _) = ViewDataMapper.making(s), case .running(let p) = jobs.first?.state else {
            Issue.record("분석 중인 촬영본이 목록에 없다"); return
        }
        #expect(jobs[0].planLabel == Copy.Plan.Preparing.title)
        #expect(abs(p.fraction - 0.5 * (0.1 + 0.9 * 0.5)) < 1e-9)
        #expect(p.steps.map(\.state) == [.done, .running, .waiting, .waiting])   // 받아적기 · 사람 찾기 · 장면 나누기 · 만들기
        // AI 초안 중 — 반쯤
        let drafting = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.agent, "v", .running)], now: now)
        guard case .loaded(let d, _) = ViewDataMapper.making(drafting), case .running(let p2) = d.first?.state else { Issue.record(""); return }
        #expect(p2.fraction == 0.5)
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
        #expect(abs(p.fraction - (0.65 + 0.25 * 0.4)) < 1e-9)     // 전체 진행률 — 만들기 단계 안에서 0.4
        #expect(p.steps.last?.progress == 0.4)
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

        // Mac 에 저장한 것도 줄에 남는다 — 저장한 폴더 이름으로 (전에는 아무 표시가 없었다)
        let folder = FileManager.default.temporaryDirectory.appending(path: "올릴 영상", directoryHint: .isDirectory)
        let s3 = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], outputs: [o], now: now,
                                 exports: [ExportRecord(outputId: "o", target: .photos, location: "x", createdAt: now - 60),
                                           ExportRecord(outputId: "o", target: .folder, location: folder.appending(path: "a.mp4").path, createdAt: now)])
        let saved = try #require(ViewDataMapper.results(of: "v", s3).first)
        #expect(saved.exportedNote == Copy.Results.Export.historyLine(target: "올릴 영상", when: Copy.time(now)))
    }

    @Test("멈춘 편집안 — 짜다 실패(편집안 없음) · 로그인 필요 · 두 번 다듬어도 안 됨(isFinal)")
    func stoppedStates() throws {
        // 요청은 받았는데 분석이 죽었다 — 멈췄다고 말하고 다시 해 보기를 준다
        let asked = ChatRecord(id: "q", videoId: "v", kind: .creator, text: "알아서 만들어줘", createdAt: now - 60)
        var failed = job(.analyze, "v", .failed)
        failed.error = "읽지 못했다"
        failed.finishedAt = now
        let s1 = LibrarySnapshot(videos: [video("v", at: now)], jobs: [failed], chats: [asked], now: now)
        guard case .stopped(let p, let reason, let actions, let isFinal) = try #require(ViewDataMapper.plan(s1, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(p == nil && !isFinal)
        #expect(reason == Copy.AI.analyzeFailed)
        #expect(actions.first?.title == Copy.Plan.Stopped.tryAgain)

        // AI 초안이 막혔다 — 쓴 말은 "보내지 못함", 까닭은 대화에. 화면은 다시 묻는다 (다시 보내기)
        var limit = job(.agent, "v", .failed)
        limit.error = "AI 턴 실패: You've hit your usage limit."
        limit.finishedAt = now
        let rows = [
            ChatRecord(id: "q", videoId: "v", kind: .creatorNotSent, text: "알아서 만들어줘", createdAt: now - 60),
            ChatRecord(id: "n", videoId: "v", kind: .notice,
                       payload: ["key": .string(Chat.Key.aiDraftFailed), "detail": .string("AI 턴 실패: You've hit your usage limit.")], createdAt: now - 30),
        ]
        let s1b = LibrarySnapshot(videos: [video("v", at: now)], jobs: [limit], chats: rows, now: now)
        #expect(ViewDataMapper.plan(s1b, videoID: "v", ai: .claude) == .asking(preparing: nil))
        let said = ViewDataMapper.chat(s1b, videoID: "v", ai: .claude).map(\.kind)
        #expect(said.contains(.userNotSent("알아서 만들어줘")))
        #expect(said.last == .assistant(Copy.AI.aiDraftFailed + " " + Copy.AI.reasonLimit))

        let s2 = LibrarySnapshot(videos: [video("v", at: now)], now: now)
        #expect(ViewDataMapper.plan(s2, videoID: "v", ai: .notLoggedIn(.codex)) == .notLoggedIn(.codex))

        let s3 = LibrarySnapshot(videos: [video("v", at: now)],
                                 compositions: [try comp("d", at: now - 60), try comp("r", origin: .selfEval, revisionOf: "d", at: now - 30)],
                                 outputs: [output("o1", comp: "d", verdict: .hidden, at: now - 50), output("o2", comp: "r", verdict: .failed, at: now - 20)],
                                 now: now)
        guard case .stopped(let plan, _, _, let final) = try #require(ViewDataMapper.plan(s3, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(final && plan?.id == "d")
    }

    @Test("사람이 멈췄다(■) — 빈 '준비 중' 이 아니라 '멈췄어요 · 다시 해 보기'. 초안 전이든 영상 만들다든")
    func stoppedByYou() throws {
        var stopped = job(.analyze, "v", .failed)
        stopped.error = "멈춤"
        stopped.finishedAt = now
        // 요청 없이 넣자마자 돌던 분석을 멈췄다 — 멈춘 화면이 아니라 그냥 묻는다
        let s0 = LibrarySnapshot(videos: [video("v", at: now)], jobs: [stopped], now: now)
        #expect(ViewDataMapper.plan(s0, videoID: "v", ai: .claude) == .asking(preparing: nil))
        let asked = ChatRecord(id: "q", videoId: "v", kind: .creator, text: "알아서 만들어줘", createdAt: now - 60)
        let s1 = LibrarySnapshot(videos: [video("v", at: now)], jobs: [stopped], chats: [asked], now: now)
        guard case .stopped(let p1, let r1, let a1, _) = try #require(ViewDataMapper.plan(s1, videoID: "v", ai: .claude)) else {
            Issue.record("준비 중으로 남았다"); return
        }
        #expect(p1 == nil && r1 == Copy.AI.stoppedByYou && a1.first?.title == Copy.Plan.Stopped.tryAgain)

        // 초안은 나왔는데 영상 만들기(렌더)를 멈췄다 — 보여 준 결과물이 아직 없다
        var render = job(.render, "d", .failed)
        render.error = "멈춤"
        render.finishedAt = now
        let s2 = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)], jobs: [render], now: now)
        guard case .stopped(let p2, let r2, _, _) = try #require(ViewDataMapper.plan(s2, videoID: "v", ai: .claude)) else {
            Issue.record("멈춘 렌더가 멈췄다고 안 나온다"); return
        }
        #expect(p2?.id == "d" && r2 == Copy.AI.stoppedByYou)
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

    @Test("결과 길이는 장면 길이의 합 — AI 가 적은 목표 길이가 아니다. 장면을 빼면 줄어든다")
    func lengthIsActual() throws {
        // 목표 6초 · 장면 3초 + 2.5초 = 5.5초, 사람이 한 장면을 뺀 판은 3초
        let s = LibrarySnapshot(videos: [video("v", at: now)],
                                compositions: [try comp("d", at: now - 60),
                                               try comp("e", scenes: [(0, 3)], origin: .chat, revisionOf: "d", at: now - 10)],
                                outputs: [output("o", comp: "d", verdict: .shown, at: now - 50)], now: now)
        guard case .ready(let draft) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(draft.targetDuration == 5.5)
        guard case .ready(let edited) = try #require(ViewDataMapper.plan(s, videoID: "v", ai: .claude, viewing: "e")) else { Issue.record(""); return }
        #expect(edited.targetDuration == 3)
        #expect(edited.versions.map(\.duration) == [5.5, 3])   // 판 목록과 같은 값
    }

    @Test("채팅 '앞으로도?' — 규칙 문장은 버튼 설명에, 답하면 사라진다 · 받기 실패 · 원본 한계 안내")
    func remembersAndNotices() throws {
        let ask = ChatRecord(id: "q", videoId: "v", kind: .choices, payload: ["ask": .string("askRemember"), "rule": .string("영상은 15초 안팎으로")], createdAt: now)
        let s = LibrarySnapshot(videos: [video("v", at: now, status: .failed)], compositions: [try comp("d", at: now - 60)], chats: [ask], now: now)
        let msgs = ViewDataMapper.chat(s, videoID: "v").map(\.kind)
        #expect(msgs.first == .assistant(Copy.Remember.askRemember))
        guard case .choices(let c) = msgs.last else { Issue.record(""); return }
        #expect(c.first?.title == Copy.Remember.rememberYes && c.first?.detail == "영상은 15초 안팎으로")
        var answered = ask
        answered.payload = #"{"ask":"askRemember","rule":"x","answered":true}"#
        #expect(ViewDataMapper.chat(LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 60)],
                                                    chats: [answered], now: now), videoID: "v").isEmpty)

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
        #expect(cl.weight == .medium && cl.fill == "fav0" && cl.secondaryFill == "fav0" && cl.secondarySameAsMain)   // 흰색 · 노란색 칸
        l = LookMapper.apply(.font("나눔고딕"), to: l)
        #expect(l.caption.fontFamily == "나눔고딕" && l.secondary.fontFamily == "나눔고딕")   // 같이 쓰는 중이라 영문도
        l = LookMapper.apply(.weight(.heavy), to: l)
        #expect(l.caption.weight == 900)
        l = LookMapper.apply(.fill("sky"), to: l)
        #expect(LookMapper.matching(l.caption.fill) == "sky")
        #expect(LookMapper.look(l, fonts: [], labels: [:], preview: .none).fontMissing)   // 이 Mac 에 없는 글꼴
    }

    @Test("자막 모양 — 컬러 피커로 고른 색은 견본이 아니라 '직접 고른 색'. 견본 색을 다시 고르면 견본으로 돌아간다")
    func customColor() throws {
        var l = try StyleStore.load().values.look
        l = LookMapper.apply(.fillColor(red: 1, green: 0.3, blue: 0.5), to: l)
        l = LookMapper.apply(.secondaryFillColor(red: 0.2, green: 0.8, blue: 0.4), to: l)
        let cl = LookMapper.look(l, fonts: [], labels: [:], preview: .none)
        #expect(cl.fill == CaptionLook.customID && cl.secondaryFill == CaptionLook.customID)
        #expect(abs(cl.fillColor.green - 0.3) < 0.01 && abs(cl.secondaryFillColor.green - 0.8) < 0.01)
        l = LookMapper.apply(.fillColor(red: 1, green: 1, blue: 1), to: l)
        #expect(LookMapper.matching(l.caption.fill) == "white")
        // 미리보기 문장 · 자주 쓰는 색은 모양이 아니다
        #expect(LookMapper.apply(.previewText("아무 말"), to: l) == l)
        #expect(LookMapper.apply(.setFavorite(.main, index: 1), to: l) == l)
    }

    @Test("자주 쓰는 색 3칸은 사람이 바꾼 색으로 나오고, 지금 색이 그 칸이면 그 칸이 골라진다")
    func favorites() throws {
        var l = try StyleStore.load().values.look
        let pink = HexColor(RGBA(1, 0.2, 0.6, 1))
        l.caption.fill = pink
        let favs = [LookMapper.defaultFavorites[0], pink, LookMapper.defaultFavorites[2]]
        let cl = LookMapper.look(l, fonts: [], labels: [:], preview: .none, favorites: favs)
        #expect(cl.fills.map(\.id) == ["fav0", "fav1", "fav2"])
        #expect(abs(cl.fills[1].blue - 0.6) < 0.01)
        #expect(cl.fill == "fav1")
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

    @Test("내보내기 실패 안내 — 버튼이 할 일로 이어진다. Mac 저장이 막히면 'Mac에 저장' 을 또 권하지 않는다")
    func exportFailedNotice() {
        let photos = ExportTarget(title: Copy.Results.Export.photos, detail: "", symbol: "")
        let files = ExportTarget(title: Copy.Results.Export.files, detail: "", symbol: "")
        let targets = [photos, files]

        let p = ViewDataMapper.exportFailed(photos)
        #expect(p.actions.map(\.title) == [Copy.Results.Export.retry, Copy.Results.Export.saveToMac])
        #expect(ViewDataMapper.exportRetry(p.actions[0], failed: photos, targets: targets) == photos)
        #expect(ViewDataMapper.exportRetry(p.actions[1], failed: photos, targets: targets) == files)

        let f = ViewDataMapper.exportFailed(files)
        #expect(f.actions.map(\.title) == [Copy.Results.Export.retry])
        #expect(f.message.hasPrefix("Mac에 저장하지 못했어요."))
        #expect(!f.message.contains("Mac에 저장에"))
        #expect(ViewDataMapper.exportRetry(f.actions[0], failed: files, targets: targets) == files)
    }

    @Test("사진 권한을 상태줄에 넘긴다 — 권한이 없는데 'iCloud 사진과 맞춰져 있음' 이라고 하지 않게")
    func studioCarriesPhotoAccess() {
        let s = LibrarySnapshot(now: now)
        #expect(ViewDataMapper.studio(s, studioName: "", ai: .none, photos: .notAsked).photos == .notAsked)
        #expect(ViewDataMapper.studio(s, studioName: "", ai: .none, photos: .granted).photos == .granted)
        // 맞추는 중의 진행도 넘긴다 — 아랫줄 "사진 보관함과 맞추는 중 · 237개 중 120개". 다 맞췄으면 nil
        let syncing = ViewDataMapper.studio(s, studioName: "", ai: .none, photos: .granted, syncing: PhotoSync(done: 120, total: 237))
        #expect(syncing.syncing == PhotoSync(done: 120, total: 237))
        #expect(ViewDataMapper.studio(s, studioName: "", ai: .none, photos: .granted).syncing == nil)
        #expect(Copy.Gallery.Status.syncing(done: 120, total: 237) == "사진 보관함과 맞추는 중 · 237개 중 120개")
        #expect(Copy.Gallery.Status.syncing(done: 0, total: 0) == "사진 보관함과 맞추는 중…")
    }

    @Test("편집안이 없으면 AI 가 먼저 묻는다 — 요구 없이 만들지 않는다. 말하면 답하는 중, 초안이 나오면 AI 말 밑에 결과")
    func asksBeforeMaking() throws {
        // 넣기만 했다 (분석도 끝남) — 묻는 화면, 대화 첫 줄은 AI 의 물음
        let fresh = LibrarySnapshot(videos: [video("v", at: now)], now: now)
        #expect(ViewDataMapper.plan(fresh, videoID: "v", ai: .claude) == .asking(preparing: nil))
        #expect(ViewDataMapper.chat(fresh, videoID: "v").map(\.kind) == [.assistant(Copy.Chat.Ask.greeting)])

        // 말했다 — AI 초안이 도는 중: 짜는 중 화면 + 답하는 중
        let asked = ChatRecord(id: "q", videoId: "v", kind: .creator, text: "어깨 부분만 20초로", createdAt: now - 60)
        let drafting = LibrarySnapshot(videos: [video("v", at: now)], jobs: [job(.agent, "v", .running)], chats: [asked], now: now)
        guard case .preparing = try #require(ViewDataMapper.plan(drafting, videoID: "v", ai: .claude)) else { Issue.record("짜는 중이 아니다"); return }
        #expect(ViewDataMapper.chat(drafting, videoID: "v").map(\.kind) == [.assistant(Copy.Chat.Ask.greeting), .user("어깨 부분만 20초로"), .typing])

        // 질문에 답만 했다 (편집안 없음) — 다시 묻는 상태
        let answer = ChatRecord(id: "a", videoId: "v", kind: .assistant, text: "어깨 스트레칭 영상이에요.", createdAt: now - 30)
        let answered = LibrarySnapshot(videos: [video("v", at: now)], chats: [asked, answer], now: now)
        #expect(ViewDataMapper.plan(answered, videoID: "v", ai: .claude) == .asking(preparing: nil))
        #expect(answered.draftRequest(of: "v").isEmpty)

        // 초안이 나왔다 — 물음은 대화 첫 줄로 남고, 요청 · AI 말이 이어진다
        let made = ChatRecord(id: "a", videoId: "v", kind: .assistant, text: "어깨 부분으로 만들었어요.", compositionId: "d", createdAt: now - 30)
        let done = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now - 30)],
                                   outputs: [output("o", comp: "d", verdict: .shown, at: now - 10)], chats: [asked, made], now: now)
        let kinds = ViewDataMapper.chat(done, videoID: "v").map(\.kind)
        #expect(kinds.prefix(3) == [.assistant(Copy.Chat.Ask.greeting), .user("어깨 부분만 20초로"), .assistant("어깨 부분으로 만들었어요.")])
        guard case .result = kinds.last else { Issue.record("결과물 카드가 없다"); return }
    }

    @Test("사진 보관함에 있던 영상(목록에만) — 갤러리에 그냥 보이고 '가져오는 중' 이 아니다. 열면 받기부터, 못 받으면 멈춤")
    func listedLibraryShots() throws {
        var old = video("old", at: now - 400 * 86400, status: .listed)
        old.durationSec = 42
        let s = LibrarySnapshot(videos: [old], now: now)
        // 갤러리 — 받는 중 막대가 아니라 목록
        guard case .loaded(let groups) = ViewDataMapper.gallery(s, photos: .granted) else { Issue.record("loaded 가 아니다"); return }
        let cell = try #require(groups.first?.shots.first)
        #expect(cell.duration == 42 && cell.fetchProgress == nil && cell.videoURL == nil && !cell.isMaking && !cell.isPreparing)
        // 살펴보기 전이라 말소리는 모른다 — "있다"(전에는 "잘 들려요")고 하지 않는다
        #expect(cell.speech == .unknown && cell.speech.label == Copy.Speech.unknown)
        // 앱 사본이 없으니 미리보기는 사진 보관함에서 바로 튼다 — 재생 버튼이 사라지지 않게
        #expect(cell.photoAssetID == "old")
        var ready = video("r", at: now); ready.localPath = "/o/r.mov"
        #expect(ViewDataMapper.shot(ready, LibrarySnapshot(videos: [ready], now: now)).photoAssetID == nil)   // 사본이 있으면 그걸 튼다
        // 열었다 — 원본을 받기 시작한다 (묻는 화면, 준비 0%)
        #expect(ViewDataMapper.plan(s, videoID: "old", ai: .claude) == .asking(preparing: 0))
        // 받는 중 — 받은 만큼이 준비의 앞 3할
        var fetching = LibrarySnapshot(videos: [video("old", at: now, status: .importing)], now: now)
        fetching.importProgress["old"] = 0.5
        #expect(ViewDataMapper.plan(fetching, videoID: "old", ai: .claude) == .asking(preparing: 0.15))
        // 못 받았다 — 멈췄다고 말하고 다시 해 보기
        let failed = LibrarySnapshot(videos: [video("old", at: now, status: .failed)], now: now)
        guard case .stopped(let plan, let reason, let actions, _) = try #require(ViewDataMapper.plan(failed, videoID: "old", ai: .claude)) else {
            Issue.record("멈춤이 아니다"); return
        }
        #expect(plan == nil && reason == Copy.Photos.importFailedShort && actions.first?.title == Copy.Plan.Stopped.tryAgain)
    }

    @Test("말소리 — 분석한 영상만 말한다: 받아적은 말이 있으면 '있어요', 0개면 '없어요', 분석 전이면 '살펴보기 전'")
    func speechSaysOnlyWhatWeKnow() {
        let v = video("v", at: now)
        func speech(_ counts: [String: Int]) -> SpeechLevel {
            ViewDataMapper.shot(v, LibrarySnapshot(videos: [v], wordCounts: counts, now: now)).speech
        }
        #expect(speech([:]) == .unknown)          // 분석 전 — 전에는 "잘 들려요" 였다
        #expect(speech(["v": 0]) == .silent)      // 분석했는데 받아적은 말이 없다
        #expect(speech(["v": 41]) == .clear)
        // 또렷함은 재지 않는다 — "잘 들려요" 라고 하지 않는다
        #expect(Copy.Speech.clear == "있어요" && Copy.Speech.silent == "없어요")
    }
}
