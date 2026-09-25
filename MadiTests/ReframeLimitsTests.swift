import Testing
import CoreGraphics
@testable import MadiKit

/// 확대 상한은 **원본 해상도가 정한다.** 코드가 아니라 스타일 값(`maxUpscale`)과
/// 원본 크기의 조합이다. 실측 근거: `docs/findings/2026-09-25-zoom-design.md §2`.
struct ReframeLimitsTests {
    private let output = CGSize(width: 1080, height: 1920)

    @Test(
        "배율 1 크롭 폭은 원본 해상도와 방향으로 정해진다",
        arguments: [
            (CGSize(width: 2160, height: 3840), 2160.0),   // 세로 4K
            (CGSize(width: 1080, height: 1920), 1080.0),   // 세로 1080p
            (CGSize(width: 3840, height: 2160), 1215.0),   // 가로 4K — 높이가 한계
            (CGSize(width: 1920, height: 1080), 607.5),    // 가로 1080p — 출력보다 좁다
        ]
    )
    func baseCropWidth(source: CGSize, expected: Double) {
        let width = ReframeLimits.baseCropWidth(source: source, output: output)
        #expect(abs(width - expected) < 0.5)
    }

    @Test("가로 1080p 는 확대하기 전에 이미 업스케일이다")
    func landscape1080AlreadyUpscales() {
        // 9:16 크롭 폭이 607.5px 뿐인데 출력은 1080px 다.
        let u = ReframeLimits.upscale(
            zoom: 1, source: CGSize(width: 1920, height: 1080), output: output
        )
        #expect(abs(u - 1.778) < 0.01)
    }

    @Test("세로 1080p 의 무손실 상한은 배율 1.00 이다")
    func portrait1080LosslessLimit() {
        // zoomtest 실측과 같은 값이어야 한다.
        let source = CGSize(width: 1080, height: 1920)
        #expect(abs(ReframeLimits.upscale(zoom: 1.0, source: source, output: output) - 1.0) < 0.01)
        #expect(abs(ReframeLimits.upscale(zoom: 1.5, source: source, output: output) - 1.5) < 0.01)
        #expect(abs(ReframeLimits.maxZoom(source: source, output: output, maxUpscale: 1.0) - 1.0) < 0.01)
    }

    @Test("세로 4K 는 maxUpscale 1.25 에서 배율 2.5 까지 쓴다")
    func portrait4KAllowance() {
        let z = ReframeLimits.maxZoom(
            source: CGSize(width: 2160, height: 3840), output: output, maxUpscale: 1.25
        )
        #expect(abs(z - 2.5) < 0.01)
    }

    @Test("목표에 닿으면 reachedTarget 이 참이다 — 세로 4K")
    func planReachesTarget() {
        // IMG_6022 실측: 사람 높이 0.32 · 필요 배율 2.25 · 허용 2.50
        let p = ReframeLimits.plan(
            subjectHeight: 0.32, target: 0.72,
            source: CGSize(width: 2160, height: 3840), output: output, maxUpscale: 1.25
        )
        #expect(abs(p.zoom - 2.25) < 0.01)
        #expect(p.reachedTarget)
    }

    @Test("원본 한계면 상한에서 자르고 못 닿았다고 알린다 — 저해상도 세로")
    func planHitsSourceLimit() {
        // NOCXAZE8XdQ 실측: 608x1080 · 사람 높이 0.31 · 필요 배율 2.31
        let p = ReframeLimits.plan(
            subjectHeight: 0.31, target: 0.72,
            source: CGSize(width: 608, height: 1080), output: output, maxUpscale: 1.25
        )
        // 허용 배율이 1 보다 작아도 배율 1(확대 없음)은 쓴다.
        #expect(p.zoom == 1)
        #expect(!p.reachedTarget)
        #expect(abs(p.resultingHeight - 0.31) < 0.001)
    }

    @Test("이미 목표보다 크면 확대하지 않는다")
    func planDoesNotZoomOut() {
        // 6U6Qp35FQaM 실측: 사람 높이 1.0 (클로즈업)
        let p = ReframeLimits.plan(
            subjectHeight: 1.0, target: 0.72,
            source: CGSize(width: 1920, height: 1080), output: output, maxUpscale: 1.25
        )
        #expect(p.zoom == 1, "축소는 G1 을 떨어뜨린다 — 하지 않는다")
        #expect(p.reachedTarget)
    }

    @Test("스타일이 상한을 정한다 — 코드에 박혀 있지 않다")
    func maxUpscaleComesFromStyle() throws {
        let style = try StyleStore.load().values
        #expect(style.reframe.maxUpscale == 1.25)
        let tight = ReframeLimits.maxZoom(
            source: CGSize(width: 2160, height: 3840), output: output, maxUpscale: 1.0
        )
        #expect(abs(tight - 2.0) < 0.01, "1.0 으로 조이면 무손실 상한만 쓴다")
    }
}
