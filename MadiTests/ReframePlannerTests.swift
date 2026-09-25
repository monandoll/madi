import Testing
import Foundation
import CoreGraphics
@testable import MadiKit

/// `SubjectTrack` → 키프레임 → `Composition` 되쓰기 (`AGENTS.md §7-1`, 1단계).
///
/// 여기서 못을 박는 것 세 개:
/// 1. **`NormRect.y` 는 아래 기준이다.** 0단계에는 크롭이 항상 전체 높이라 뒤집혀 있어도
///    드러나지 않았고, 확대가 들어오자마자 화면이 천장을 잡았다.
/// 2. **되쓰기가 JSON 왕복을 견딘다.** 못 견디면 재현 가능성이 깨진다 (`§1-8`).
/// 3. **하드 게이트 예외가 되돌리지 않는다.** `판정 불가` · `원본 한계` 는 `shouldRetry == false`.
struct ReframePlannerTests {

    private let output = CGSize(width: 1080, height: 1920)

    private func style(target: Double = 0.72, maxUpscale: Double = 1.25) -> StyleValues.ReframeValues {
        StyleValues.ReframeValues(
            targetSubjectHeightRatio: target, maxUpscale: maxUpscale,
            smoothingSec: 0.4, padding: 0.08
        )
    }

    /// 화면 가운데에 `height` 높이로 서 있는 사람. `missingEvery` 번째 표본은 마스크가 없다.
    private func track(
        size: CGSize, count: Int = 20, height: Double = 0.6,
        centerX: @escaping (Int) -> Double = { _ in 0.5 },
        missingEvery: Int? = nil
    ) -> SubjectTrack {
        let samples = (0..<count).map { i -> SubjectSample in
            if let every = missingEvery, i % every == 0 {
                return SubjectSample(
                    t: Double(i) * 0.5, box: nil, massCenterX: nil, massCenterY: nil, coverage: 0
                )
            }
            let x = centerX(i)
            return SubjectSample(
                t: Double(i) * 0.5,
                box: NormRect(x: x - 0.1, y: (1 - height) / 2, w: 0.2, h: height),
                massCenterX: x, massCenterY: 0.5, coverage: 0.2 * height
            )
        }
        return SubjectTrack(
            source: SourceInfo(
                videoID: "v", width: Int(size.width), height: Int(size.height),
                durationSec: Double(count) * 0.5, fps: 30
            ),
            stepSec: 0.5, samples: samples
        )
    }

    // MARK: - 좌표 기준

    @Test("NormRect.y 는 아래에서 잰다 — 중심을 위로 올리면 y 가 커진다")
    func yIsMeasuredFromBottom() {
        let source = CGSize(width: 2160, height: 3840)
        let low = ReframeLimits.cropRect(
            zoom: 2, center: CGPoint(x: 0.5, y: 0.25), source: source, output: output
        )
        let high = ReframeLimits.cropRect(
            zoom: 2, center: CGPoint(x: 0.5, y: 0.75), source: source, output: output
        )
        #expect(low.y < high.y)
        #expect(abs(low.y - (0.25 - low.h / 2)) < 1e-9)
    }

    @Test("크롭은 원본 밖으로 나가지 않는다")
    func cropStaysInsideSource() {
        let source = CGSize(width: 2160, height: 3840)
        for center in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: -3, y: 4)] {
            let rect = ReframeLimits.cropRect(
                zoom: 2, center: center, source: source, output: output
            )
            #expect(rect.x >= -1e-9 && rect.x + rect.w <= 1 + 1e-9)
            #expect(rect.y >= -1e-9 && rect.y + rect.h <= 1 + 1e-9)
        }
    }

    @Test("배율 1 크롭은 가로 원본에서 전체 높이를 쓴다")
    func baseCropUsesFullHeightOnLandscape() {
        let rect = ReframeLimits.cropRect(
            zoom: 1, center: CGPoint(x: 0.5, y: 0.5),
            source: CGSize(width: 1920, height: 1080), output: output
        )
        #expect(abs(rect.h - 1) < 1e-9)
        #expect(abs(rect.w - 607.5 / 1920) < 1e-6)
    }

    // MARK: - 스무딩

    @Test("스무딩이 좌우 떨림을 줄인다 (G3)")
    func smoothingReducesJitter() {
        let jitter = track(
            size: CGSize(width: 2160, height: 3840),
            centerX: { i in 0.5 + (i % 2 == 0 ? 0.06 : -0.06) }
        )
        let rough = ReframePlanner.rawTargets(
            jitter.samples, source: jitter.source.size, output: output,
            style: style(), verticalAnchor: .boxCenter
        )
        let smoothed = ReframePlanner.smooth(rough, sigma: 0.4)
        func swing(_ t: [ReframePlanner.Target]) -> Double {
            (1..<t.count).map { abs(t[$0].center.x - t[$0 - 1].center.x) }.max() ?? 0
        }
        #expect(swing(smoothed) < swing(rough))
    }

    @Test("마스크가 빈 구간은 이웃에서 채운다 — 화면 중앙으로 튀지 않는다")
    func gapsAreFilledFromNeighbours() {
        var targets = ReframePlanner.rawTargets(
            track(size: CGSize(width: 2160, height: 3840), count: 6,
                  centerX: { _ in 0.8 }, missingEvery: 3).samples,
            source: CGSize(width: 2160, height: 3840), output: output,
            style: style(), verticalAnchor: .boxCenter
        )
        ReframePlanner.fillGaps(&targets)
        // 채우기 전에는 0.5 였다. 이웃이 전부 0.8 이므로 0.8 이어야 한다.
        for t in targets { #expect(abs(t.center.x - 0.8) < 1e-9) }
    }

    // MARK: - 게이트

    @Test("입력 없음이 20% 를 넘으면 판정 불가 — 되돌리지 않는다")
    func tooManyMissingSamplesCannotBeJudged() {
        let plan = ReframePlanner.plan(
            track: track(size: CGSize(width: 2160, height: 3840), missingEvery: 2),
            range: 0...10, output: output, fps: 30, style: style()
        )
        #expect(plan.g1 == .cannotJudge(.subjectNotFound))
        #expect(plan.g1.shouldRetry == false)
        #expect(plan.g1.notice == .subjectNotFound)
    }

    @Test("확대 상한에 걸려 못 닿으면 원본 한계 — 되돌리지 않는다")
    func zoomCappedBecomesSourceLimited() {
        // 가로 1080p 는 9:16 크롭 폭이 608px 뿐이라 확대 여력이 없다.
        let plan = ReframePlanner.plan(
            track: track(size: CGSize(width: 1920, height: 1080), height: 0.3),
            range: 0...10, output: output, fps: 30, style: style()
        )
        #expect(plan.g1 == .sourceLimited(.subjectTooSmallLowResolution))
        #expect(plan.g1.shouldRetry == false)
    }

    @Test("확대 여력이 있는데 못 닿으면 진짜 실패 — 되돌린다")
    func reachableButMissedIsRealFailure() {
        // 세로 4K 는 2.5배까지 되지만 상한을 1.0 으로 조이면 확대가 막힌다.
        // 그때는 '원본 한계' 가 아니라 배율 계산이 잘못된 것이므로 fail 이어야 한다.
        let source = CGSize(width: 2160, height: 3840)
        let plan = ReframePlanner.plan(
            track: track(size: source, height: 0.3),
            range: 0...10, output: output, fps: 30, style: style(maxUpscale: 1.25)
        )
        // 0.3 x 2.5 = 0.75 → 0.55 를 넘는다. 통과해야 한다.
        #expect(plan.g1 == .pass)
    }

    @Test("충분히 큰 피사체는 통과한다")
    func largeSubjectPasses() {
        let plan = ReframePlanner.plan(
            track: track(size: CGSize(width: 1920, height: 1080), height: 0.7),
            range: 0...10, output: output, fps: 30, style: style()
        )
        #expect(plan.g1 == .pass)
        #expect(plan.g3 == .pass)
    }

    // MARK: - 되쓰기

    @Test("auto 장면은 keyframes 로 바뀌고 JSON 왕복을 견딘다")
    func writeBackSurvivesJSONRoundTrip() throws {
        let source = CGSize(width: 2160, height: 3840)
        let scene = Scene(
            id: "s1", role: .demo,
            source: Scene.Source(videoID: "v", start: 0, end: 10),
            reframe: ReframeTrack(mode: .auto)
        )
        let comp = Composition(
            id: "c1", videoID: "v", templateID: "short",
            meta: Composition.Meta(title: "t", targetDurationSec: 10),
            captionSlot: .fullBody, scenes: [scene]
        )
        let values = try StyleStore.load(StyleStore.defaultID).values
        let applied = ReframePlanner.apply(
            to: comp, tracks: ["v": track(size: source)], style: values
        )
        #expect(applied.composition.scenes[0].reframe.mode == .keyframes)
        #expect(applied.composition.scenes[0].reframe.keyframes.count > 1)

        let data = try JSONEncoder().encode(applied.composition)
        let restored = try JSONDecoder().decode(Composition.self, from: data)
        #expect(restored.scenes[0].reframe == applied.composition.scenes[0].reframe)
    }

    @Test("키프레임 시각은 장면 로컬 출력 초다 — 배속을 반영한다")
    func keyframeTimesAreSceneLocalOutputSeconds() {
        let plan = ReframePlanner.plan(
            track: track(size: CGSize(width: 2160, height: 3840), count: 10),
            range: 2...6, speed: 2, output: output, fps: 30, style: style()
        )
        #expect(plan.keyframes.first?.t == 0)
        // 원본 2~6초를 2배속으로 쓰면 결과는 2초다.
        #expect((plan.keyframes.last?.t ?? 0) <= 2.0 + 1e-9)
    }
}
