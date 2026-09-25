import Testing
import Foundation
import CoreGraphics
@testable import MadiKit

/// 스타일은 **데이터**라서 빌드를 안 거친다 (AGENTS.md §9).
/// 오타가 그대로 렌더까지 가므로, 코드가 못 잡는 자리를 테스트가 잡는다.
struct StyleTests {

    @Test("기본 스타일이 번들에서 읽히고 검증을 통과한다")
    func loadsDefaultStyle() throws {
        let style = try StyleStore.load()
        #expect(style.id == StyleStore.defaultID)
        // 값이 어디서 나왔는지 기록이 없으면 나중에 근거 없이 흔들린다 (docs/style-authoring.md).
        #expect(!style.measuredFrom.isEmpty)
    }

    @Test("범위를 벗어난 값은 거절한다")
    func rejectsOutOfRangeValues() throws {
        var values = try StyleStore.load().values
        // 소수점 한 자리 밀림. 이러면 자막이 화면을 덮는다.
        values.caption.inkHeightRatio = 0.359
        #expect(throws: StyleError.self) { try validate(values) }
    }

    @Test("보조 문구가 화면 밖으로 나가면 거절한다")
    func rejectsSecondaryOffScreen() throws {
        var values = try StyleStore.load().values
        values.secondary.baselineOffsetRatio = values.caption.inkBottomRatio + 0.05
        #expect(throws: StyleError.self) { try validate(values) }
    }

    @Test("보조 문구는 본문이 움직이면 같이 움직인다")
    func secondaryFollowsMainCaption() throws {
        // 공개 숏폼 10편에서 본문 위치는 0.235~0.483 으로 벌어지는데 본문↔보조 간격은
        // 0.031~0.041 로 붙어 있다. 절대 위치로 두면 본문이 움직일 때 보조가 따로 논다.
        var values = try StyleStore.load().values
        let frame = CGSize(width: 1080, height: 1920)
        let before = CaptionLayout.metrics(frameSize: frame, style: values)
        let gap = before.baselineFromBottom - before.secondaryBaselineFromBottom

        values.caption.inkBottomRatio += 0.15   // 본문을 위로 올린다
        let after = CaptionLayout.metrics(frameSize: frame, style: values)

        #expect(after.secondaryBaselineFromBottom > before.secondaryBaselineFromBottom)
        #expect(abs((after.baselineFromBottom - after.secondaryBaselineFromBottom) - gap) < 0.01)
    }

    @Test("색은 #RRGGBB 와 #RRGGBBAA 를 읽는다")
    func parsesHexColors() {
        #expect(HexColor.parse("#FFFFFF")?.r == 1)
        #expect(HexColor.parse("#000000")?.a == 1)
        let half = HexColor.parse("#0000008C")
        #expect(half != nil)
        #expect(abs((half?.a ?? 0) - 140.0 / 255) < 0.001)
        #expect(HexColor.parse("빨강") == nil)
    }
}

/// `docs/stage-0.spec.md` 통과 조건 A 를 코드로 고정한다.
///
/// 측정이 `tools/measure.mjs` 에만 있으면 아무도 안 돌릴 때 회귀를 놓친다.
/// 전작이 망한 이유 중 하나가 "렌더 결과를 아무도 다시 안 봄" 이다 (AGENTS.md §0-6).
struct CaptionGeometryTests {
    private let frame = CGSize(width: 1080, height: 1920)

    private func render(_ caption: Caption, style: StyleValues) throws -> StillRenderer.StrokeScan {
        let image = try StillRenderer.renderCaption(
            caption, size: frame, style: style, backdrop: .solid(RGBA(0, 0, 0, 1))
        )
        let scan = StillRenderer.scanStrokes(image)
        #expect(scan != nil, "그려진 흰 글자를 찾지 못했다")
        return try #require(scan)
    }

    @Test("그려진 글자 높이가 스타일이 요구한 비율과 맞는다")
    func inkHeightMatchesStyle() throws {
        let style = try StyleStore.load().values
        let scan = try render(
            Caption(id: "t", start: 0, end: 1, text: "가능성이 높다는 겁니다"), style: style
        )
        // 통과 조건 A: 프레임 높이의 3.59% ±0.1%
        #expect(abs(scan.inkHeightRatio - style.caption.inkHeightRatio) <= 0.001,
                "글자 높이 \(scan.inkHeightRatio) 가 목표 \(style.caption.inkHeightRatio) 와 다르다")
    }

    @Test("글자 아래끝이 스타일이 요구한 위치에 온다")
    func inkBottomMatchesStyle() throws {
        let style = try StyleStore.load().values
        let scan = try render(
            Caption(id: "t", start: 0, end: 1, text: "가능성이 높다는 겁니다"), style: style
        )
        // 통과 조건 A: 아래에서 0.2352 ±0.003
        #expect(abs(scan.inkBottomRatio - style.caption.inkBottomRatio) <= 0.003,
                "아래끝 \(scan.inkBottomRatio) 가 목표 \(style.caption.inkBottomRatio) 와 다르다")
    }

    @Test("자막 길이가 달라도 글자 크기는 고정이다")
    func sizeIsFixedNotFitToWidth() throws {
        // 원본 판정: 글자 수 6~15자에서 폭은 변해도 글자 높이는 일정했다
        // (docs/findings/2026-09-23-reference-measurement.md §2).
        // 폭에 맞춰 키우는 코드(fit-to-width)가 들어오면 여기서 깨진다.
        //
        // ★ 목표치와 비교하지 않고 **문자열끼리** 비교한다. 임계값(>230)으로 행을 세면
        //   글자마다 안티에일리어싱이 달라 1~2px 흔들리는데, 그건 크기가 변한 게 아니다.
        //   절대값은 `inkHeightMatchesStyle` 이 골든 문자열로 검사한다.
        let style = try StyleStore.load().values
        var heights: [CGFloat] = []
        var widths: [CGFloat] = []
        for text in ["어깨가", "골반 틀어졌으면", "가능성이 높다는 겁니다"] {
            let scan = try render(Caption(id: "t", start: 0, end: 1, text: text), style: style)
            heights.append(scan.inkHeight)
            let font = MadiFont.pretendard(
                size: CaptionLayout.metrics(frameSize: frame, style: style).fontSize,
                weight: CGFloat(style.caption.weight)
            )
            widths.append(CaptionLayout.advanceWidth(text, font: font))
        }
        let spread = (heights.max() ?? 0) - (heights.min() ?? 0)
        #expect(spread <= 2, "글자 높이가 \(heights) 로 흔들린다 — 크기가 고정이 아니다")
        // 폭은 실제로 크게 달라야 한다. 안 그러면 위 검사가 의미 없다.
        #expect((widths.max() ?? 0) / (widths.min() ?? 1) > 2)
    }

    @Test("폰트 크기는 스타일 값이 아니라 글자 높이에서 역산된다")
    func fontSizeIsDerivedNotStored() throws {
        var style = try StyleStore.load().values
        let base = CaptionLayout.metrics(frameSize: frame, style: style)
        // 목표 글자 높이를 2배로 하면 폰트 크기도 따라 2배가 되어야 한다.
        style.caption.inkHeightRatio *= 2
        let doubled = CaptionLayout.metrics(frameSize: frame, style: style)
        #expect(abs(doubled.fontSize / base.fontSize - 2) < 0.01)
    }

    @Test("어절 단위로만 줄을 바꾼다")
    func wrapsOnWordBoundaries() throws {
        let style = try StyleStore.load().values
        let m = CaptionLayout.metrics(frameSize: frame, style: style)
        let font = MadiFont.pretendard(size: m.fontSize, weight: CGFloat(style.caption.weight))
        let lines = CaptionLayout.wrap(
            "어깨가 앞으로 말려 있으면", font: font,
            maxWidth: frame.width * CGFloat(style.caption.maxWidthRatio),
            style: style.caption
        )
        #expect(lines.count <= style.caption.maxLines)
        // 글자 한복판에서 끊기면 그 순간 자동 생성 자막처럼 보인다 (G5).
        #expect(lines.joined(separator: " ") == "어깨가 앞으로 말려 있으면")
    }

    @Test("Pretendard 가 등록되고 wght 축이 실제로 먹는다")
    func variableWeightAxisWorks() {
        #expect(MadiFont.postScriptName != nil, "Pretendard 를 번들에서 못 찾았다")
        // 축을 지정하지 않으면 기본 웨이트로 그려진다 (docs/stage-0.spec.md 알려진 함정).
        // 굵기를 바꿨는데 글자 모양이 그대로면 축이 안 먹은 것이다.
        let light = CaptionLayout.inkBounds("가힣", font: MadiFont.pretendard(size: 100, weight: 300))
        let heavy = CaptionLayout.inkBounds("가힣", font: MadiFont.pretendard(size: 100, weight: 900))
        #expect(light.height != heavy.height)
    }
}
