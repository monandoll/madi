import Testing
import Foundation
import CoreGraphics
import CoreText
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
        values.secondary.baselineOffsetRatio = values.caption.inkBottomRatio[.upperBody] + 0.05
        #expect(throws: StyleError.self) { try validate(values) }
    }

    @Test("보조 문구는 본문이 움직이면 같이 움직인다")
    func secondaryFollowsMainCaption() throws {
        // 공개 숏폼 10편에서 본문 위치는 0.235~0.483 으로 벌어지는데 본문↔보조 간격은
        // 0.031~0.041 로 붙어 있다. 절대 위치로 두면 본문이 움직일 때 보조가 따로 논다.
        var values = try StyleStore.load().values
        let frame = CGSize(width: 1080, height: 1920)
        let before = CaptionLayout.metrics(frameSize: frame, style: values, slot: .upperBody)
        let gap = before.baselineFromBottom - before.secondaryBaselineFromBottom

        values.caption.inkBottomRatio[.upperBody] += 0.15   // 본문을 위로 올린다
        let after = CaptionLayout.metrics(frameSize: frame, style: values, slot: .upperBody)

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

    private func render(
        _ caption: Caption, style: StyleValues, slot: CaptionSlot = .upperBody
    ) throws -> StillRenderer.StrokeScan {
        let image = try StillRenderer.renderCaption(
            caption, size: frame, style: style, slot: slot, backdrop: .solid(RGBA(0, 0, 0, 1))
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
        // 통과 조건 A: 아래에서 0.2352 ±0.003 (upperBody 슬롯)
        let target = style.caption.inkBottomRatio[.upperBody]
        #expect(abs(scan.inkBottomRatio - target) <= 0.003,
                "아래끝 \(scan.inkBottomRatio) 가 목표 \(target) 와 다르다")
    }

    @Test("슬롯마다 자막이 스타일이 정한 높이에 온다", arguments: CaptionSlot.allCases)
    func slotMovesCaption(slot: CaptionSlot) throws {
        // 좌표는 스타일에만 있다. 슬롯은 이름일 뿐이다 (AGENTS.md §1-2).
        let style = try StyleStore.load().values
        let scan = try render(
            Caption(id: "t", start: 0, end: 1, text: "가능성이 높다는 겁니다"),
            style: style, slot: slot
        )
        #expect(abs(scan.inkBottomRatio - style.caption.inkBottomRatio[slot]) <= 0.003)
    }

    @Test("슬롯이 바뀌면 보조 문구도 본문을 따라 같이 움직인다")
    func slotMovesSecondaryToo() throws {
        // 본문만 움직이고 보조가 남으면 둘이 떨어진다. 공개본 10편에서 본문 위치는
        // 0.235~0.483 으로 벌어지는데 본문↔보조 간격은 0.031~0.041 로 붙어 있었다
        // (docs/findings/2026-09-25-caption-position-10.md §3).
        let style = try StyleStore.load().values
        var gaps: [CGFloat] = []
        for slot in CaptionSlot.allCases {
            let m = CaptionLayout.metrics(frameSize: frame, style: style, slot: slot)
            #expect(m.baselineFromBottom > m.secondaryBaselineFromBottom, "보조가 본문 위에 있다")
            gaps.append(m.baselineFromBottom - m.secondaryBaselineFromBottom)
        }
        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        #expect(spread < 0.5, "슬롯마다 본문↔보조 간격이 \(gaps) 로 달라진다")
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
            let font = style.captionFont(
                size: CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody).fontSize
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
        let base = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        // 목표 글자 높이를 2배로 하면 폰트 크기도 따라 2배가 되어야 한다.
        style.caption.inkHeightRatio *= 2
        let doubled = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        #expect(abs(doubled.fontSize / base.fontSize - 2) < 0.01)
    }

    @Test("어절 단위로만 줄을 바꾼다")
    func wrapsOnWordBoundaries() throws {
        let style = try StyleStore.load().values
        let m = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        let font = style.captionFont(size: m.fontSize)
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

/// 자막 **모양**(`look`)은 사용자가 바꾼다. 바꿔도 템플릿(크기 · 위치)은 그대로여야 한다.
///
/// 근거: 크리에이터가 2026-08-27 에 글꼴 · 기울임을 바꿨지만 글자 크기 · 보조 크기 · 위치는 그대로였다
/// (`docs/findings/2026-09-27-secondary-10.md`). 글꼴을 바꿨더니 자막이 커지면 그건 버그다.
struct CaptionLookTests {
    private let frame = CGSize(width: 1080, height: 1920)
    /// 모든 macOS 에 들어 있는 한글 글꼴. 이탤릭 자형이 없다.
    private let systemFamily = "Apple SD Gothic Neo"

    private func scan(_ caption: Caption, _ style: StyleValues) throws -> StillRenderer.StrokeScan {
        let image = try StillRenderer.renderCaption(
            caption, size: frame, style: style, slot: .upperBody, backdrop: .solid(RGBA(0, 0, 0, 1))
        )
        return try #require(StillRenderer.scanStrokes(image))
    }

    @Test("글꼴을 바꿔도 본문 글자 높이와 아래끝은 그대로다")
    func fontChangeKeepsGeometry() throws {
        var style = try StyleStore.load().values
        style.look.caption.fontFamily = systemFamily
        try validate(style)
        let s = try scan(Caption(id: "t", start: 0, end: 1, text: "가능성이 높다는 겁니다"), style)
        #expect(abs(s.inkHeightRatio - style.caption.inkHeightRatio) <= 0.001)
        #expect(abs(s.inkBottomRatio - style.caption.inkBottomRatio[.upperBody]) <= 0.003)
    }

    @Test("본문 글꼴을 바꿔도 보조 문구 크기는 그대로다")
    func bodyFontDoesNotResizeSecondary() throws {
        var style = try StyleStore.load().values
        let before = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        style.look.caption.fontFamily = systemFamily
        style.look.caption.weight = 800
        let after = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        // 본문 폰트 크기는 글꼴마다 다르게 역산된다. 그래야 글자 높이가 같다.
        #expect(abs(before.fontSize - after.fontSize) > 0.5)
        #expect(abs(before.secondaryFontSize - after.secondaryFontSize) < 0.0001)
    }

    @Test("보조 글꼴을 바꾸면 그 글꼴로 같은 어센더 높이가 나온다")
    func secondaryFontKeepsInkHeight() throws {
        var style = try StyleStore.load().values
        style.look.secondary.fontFamily = systemFamily
        let m = CaptionLayout.metrics(frameSize: frame, style: style, slot: .upperBody)
        let ink = CaptionLayout.inkBounds(
            CaptionLayout.secondaryMetricProbe, font: style.secondaryFont(size: m.secondaryFontSize)
        )
        #expect(abs(ink.height / frame.height - style.secondary.inkHeightRatio) < 0.0002)
    }

    @Test("이탤릭 자형이 없는 글꼴은 템플릿 각도만큼 기울여 그린다")
    func syntheticItalicUsesTemplateSlant() throws {
        var style = try StyleStore.load().values
        style.look.caption.fontFamily = systemFamily
        style.look.caption.italic = true
        let font = style.captionFont(size: 100)
        let m = CTFontGetMatrix(font)
        #expect(abs(Double(m.c) - tan(style.caption.italicSlantDeg * .pi / 180)) < 1e-6)
        // 기울여도 글자 높이는 그대로다 (전단은 세로를 바꾸지 않는다).
        let s = try scan(Caption(id: "t", start: 0, end: 1, text: "가능성이 높다는 겁니다"), style)
        #expect(abs(s.inkHeightRatio - style.caption.inkHeightRatio) <= 0.001)
    }

    @Test("설치되지 않은 글꼴은 조용히 대체하지 않고 거절한다")
    func rejectsMissingFont() throws {
        var style = try StyleStore.load().values
        style.look.caption.fontFamily = "없는 글꼴 이름 7f3a"
        #expect(throws: StyleError.self) { try validate(style) }
    }

    @Test("글꼴 목록에는 한글을 그릴 수 있는 설치 글꼴이 나온다")
    func listsHangulFamilies() {
        let families = MadiFont.hangulFamilies()
        #expect(families.contains(systemFamily))
        // 라틴 전용 글꼴은 고르면 한글이 다른 글꼴로 대신 그려진다. 목록에 없어야 한다.
        #expect(!families.contains("Helvetica"))
    }
}

/// 사용자가 자막 모양을 바꾸면 **새 버전**이 생기고 옛 버전은 남는다 (AGENTS.md §1-8 · §9).
struct StyleVersionTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "madi-style-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("모양을 저장하면 새 버전이 되고, 옛 버전은 그대로 읽힌다")
    func saveLookMakesNewVersion() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = try StyleStore.load()
        #expect(try StyleStore.latest(in: dir) == StyleRef(id: base.id, version: base.version))

        var look = base.values.look
        look.caption.italic = true
        let v2 = try StyleStore.saveLook(look, basedOn: base, in: dir)
        #expect(v2.version == base.version + 1)
        #expect(try StyleStore.latest(in: dir).version == v2.version)

        // 옛 버전으로 만든 편집안은 옛 모양으로 다시 그려진다.
        let old = try StyleStore.load(StyleRef(id: base.id, version: base.version), in: dir)
        #expect(old.values.look.caption.italic == false)
        let new = try StyleStore.load(StyleRef(id: base.id, version: v2.version), in: dir)
        #expect(new.values.look.caption.italic == true)
        // 템플릿 값은 건드리지 않는다.
        #expect(new.values.caption == base.values.caption)
        #expect(new.values.secondary == base.values.secondary)
    }

    @Test("저장할 때마다 번호가 올라가고 덮어쓰지 않는다")
    func neverOverwrites() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = try StyleStore.load()
        var look = base.values.look
        look.caption.weight = 700
        let a = try StyleStore.saveLook(look, basedOn: base, in: dir)
        look.caption.weight = 800
        let b = try StyleStore.saveLook(look, basedOn: a, in: dir)
        #expect(b.version == a.version + 1)
        #expect(try StyleStore.load(StyleRef(id: base.id, version: a.version), in: dir)
            .values.look.caption.weight == 700)
    }

    @Test("설치 안 된 글꼴은 저장하지 않는다")
    func rejectsMissingFontOnSave() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = try StyleStore.load()
        var look = base.values.look
        look.caption.fontFamily = "없는 글꼴 이름 7f3a"
        #expect(throws: StyleError.self) { try StyleStore.saveLook(look, basedOn: base, in: dir) }
        #expect(try StyleStore.latest(in: dir).version == base.version)
    }

    @Test("없는 버전은 조용히 최신으로 대신하지 않는다")
    func missingVersionFails() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: StyleStore.Failure.self) {
            try StyleStore.load(StyleRef(id: StyleStore.defaultID, version: 99), in: dir)
        }
    }
}
