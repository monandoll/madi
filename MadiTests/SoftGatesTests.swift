import Testing
import Foundation
@testable import MadiKit

/// 되먹임을 부르는 소프트 게이트 (docs/stage-5.spec.md 결정 ②).
struct SoftGatesTests {

    private func comp(roles: [SceneRole], lengths: [Double], target: Double, firstCaption: Double? = 0.1) -> Composition {
        var start = 0.0
        let scenes = zip(roles, lengths).enumerated().map { i, pair -> Scene in
            defer { start += pair.1 }
            let caps = (i == 0 ? firstCaption : 0.2).map { [Caption(id: "c", start: $0, end: $0 + 0.5, text: "말")] } ?? []
            return Scene(id: "s\(i)", role: pair.0, source: Scene.Source(videoID: "v", start: start, end: start + pair.1), captions: caps)
        }
        return Composition(id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
                           meta: Composition.Meta(targetDurationSec: target), captionSlot: .fullBody, scenes: scenes)
    }

    @Test("G8 — 첫 장면이 훅이고 첫 자막이 0.5초 안")
    func hook() {
        #expect(SoftGates.g8(comp(roles: [.hook, .demo], lengths: [2, 2], target: 4)).0 == .pass)
        #expect(SoftGates.g8(comp(roles: [.demo, .hook], lengths: [2, 2], target: 4)).0 == .fail)
        #expect(SoftGates.g8(comp(roles: [.hook], lengths: [2], target: 2, firstCaption: 0.8)).0 == .fail)
        #expect(SoftGates.g8(comp(roles: [.hook], lengths: [2], target: 2, firstCaption: nil)).0 == .fail)
    }

    @Test("G11 — 목표 길이 ±15%")
    func length() {
        #expect(SoftGates.g11(comp(roles: [.hook], lengths: [20], target: 21)).0 == .pass)
        let (r, ratio) = SoftGates.g11(comp(roles: [.hook], lengths: [8.7], target: 13))
        #expect(r == .fail)
        #expect(abs(ratio - 0.669) < 0.01)   // 4단계 NOCXAZE8XdQ · Codex
    }

    @Test("G10 — 장면 중앙값 (리포트만)")
    func rhythm() {
        #expect(SoftGates.g10(comp(roles: [.hook, .demo, .cta], lengths: [2, 3, 5], target: 10)) == (.pass, 3))
        #expect(SoftGates.g10(comp(roles: [.hook, .demo, .cta], lengths: [1, 1, 5], target: 7)).0 == .fail)
    }

    @Test("G9 — 무음이면서 거의 멈춘 구간이 이어진 길이")
    func staticRun() {
        let step = 0.2
        // 0~2초 무음. 차분: 앞 1.4초는 멈춤, 그 뒤 움직임
        let diffs = Array(repeating: 0.001, count: 7) + Array(repeating: 0.05, count: 5)
        let run = SoftGates.longestStatic(silences: [0...2], diffs: diffs, stepSec: step, stillDiff: SoftGates.stillDiff)
        #expect(abs(run - 1.4) < 0.001)
        #expect(SoftGates.g9(longestStaticSec: run) == .fail)
        // 소리가 있으면 멈춰 있어도 정적이 아니다
        #expect(SoftGates.longestStatic(silences: [], diffs: diffs, stepSec: step, stillDiff: SoftGates.stillDiff) == 0)
    }

    @Test("되먹임 항목 — 하드 · G8 · G9 · G11 의 fail 만. G10 · 원본 한계는 부르지 않는다")
    func selfEvalItems() {
        let report: [String: JSONValue] = [
            "G1": .string("sourceLimited:subjectTooSmallLowResolution"), "G4.fullBody": .string("fail"),
            "G6": .string("pass"), "G8": .string("fail"), "G10": .string("fail"), "G11": .string("fail"),
            "G11.ratio": .number(0.6), "G2": .string("fail"),
        ]
        #expect(RenderJob.selfEvalItems(report) == ["G11", "G4.fullBody", "G8"])
    }
}
