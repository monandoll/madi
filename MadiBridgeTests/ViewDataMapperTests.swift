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
        #expect(steps.map(\.state) == [.done, .running, .running, .waiting])

        // 초안은 있는데 검사 전 렌더 중 — 아직 보여 주지 않는다
        let rendering = LibrarySnapshot(videos: [video("v", at: now)], compositions: [try comp("d", at: now)],
                                        jobs: [job(.render, "d", .running)], now: now)
        guard case .preparing(let s2) = try #require(ViewDataMapper.plan(rendering, videoID: "v", ai: .claude)) else { Issue.record(""); return }
        #expect(s2.last?.state == .running)
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
}
