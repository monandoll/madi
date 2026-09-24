import Foundation
import CoreGraphics
import CoreText
import QuartzCore

/// 0단계의 핵심. `docs/stage-0.spec.md` 작업순서 4.
///
/// 이 파일 하나가 원본과 구분 안 되면 0단계는 사실상 통과다.
/// 반대로 여기서 다르면 영상 전체가 다르게 보인다. 다른 걸 만들기 전에 여기부터 맞춘다.
///
/// 스타일 값은 전부 `Tokens.swift` 에서 온다. `Caption` 에서 색·크기를 받지 않는다 (AGENTS.md §1-2).
///
/// ## 원본이 그려진 방식 (실측으로 확인한 것)
///
/// `reference/yt_15s.png` 에서 흰 글자 바로 위가 검은 4px 이고 그 안쪽은 온전한 흰색이다.
/// 즉 외곽선이 글자 안쪽을 깎지 않는다 → **stroke 를 먼저 깔고 fill 을 그 위에 얹었다.**
///
/// `NSAttributedString.strokeWidth` 를 음수로 주면 CoreText 가 fill → stroke 순으로 그려서
/// 획 절반이 글자 안쪽을 파먹는다. 글자 높이가 획 두께만큼 줄어들고 획도 가늘어 보인다.
/// 그래서 여기서는 **두 번 그린다**: stroke 전용 패스(양수 strokeWidth) → fill 패스.

// MARK: - 계산된 치수

/// 토큰(비율)과 CoreText 폰트 메트릭에서 나온 실제 픽셀 치수.
/// 테스트와 `madi-spike` 가 숫자를 직접 볼 수 있게 밖으로 낸다.
public struct CaptionMetrics: Sendable {
    /// 본문 폰트 포인트 크기. **토큰에 없다** — 글자 높이 목표에서 역산한 값이다.
    public let fontSize: CGFloat
    /// 목표 글자 높이(px).
    public let inkHeight: CGFloat
    /// 폰트 1pt 당 글자 높이. 폰트를 바꾸면 이 값이 바뀐다.
    public let inkHeightPerPoint: CGFloat
    /// 글자 ink 아래끝이 베이스라인에서 얼마나 아래인가(px, 음수면 아래).
    public let inkMinYAtSize: CGFloat
    /// 검은 외곽선이 바깥으로 나가는 두께(px).
    public let strokeOuter: CGFloat
    /// `NSAttributedString.strokeWidth` 에 넣을 값 (폰트 크기 대비 %).
    public let strokeWidthPercent: CGFloat
    /// 본문 마지막 줄 베이스라인의 화면 아래에서의 거리(px).
    public let baselineFromBottom: CGFloat
    /// 보조 문구 폰트 포인트 크기.
    public let secondaryFontSize: CGFloat
    /// 보조 문구 베이스라인의 화면 아래에서의 거리(px).
    public let secondaryBaselineFromBottom: CGFloat
    /// 줄 간격(px).
    public let lineStep: CGFloat
}

/// `SuhyunShortV1` 자막의 배치 규칙. 좌표는 전부 여기서만 나온다 (Layout 역할).
public enum CaptionLayout {

    /// 폰트 메트릭을 재는 기준 문자열.
    ///
    /// ★ 자막마다 다른 문자열로 재면 안 된다. 원본은 글자 수와 무관하게 **크기가 고정**이다
    ///   (`docs/findings/2026-09-23-reference-measurement.md §2`).
    ///   받침 없는 글자와 있는 글자를 같이 넣어 한글 ink 상자의 위아래 끝을 잡는다.
    public static let metricProbe = "가힣"

    /// 보조 문구 크기를 재는 기준 문자열. 라틴 어센더·베이스라인을 잡는다.
    public static let secondaryMetricProbe = "Ix"

    public static func metrics(frameSize: CGSize) -> CaptionMetrics {
        let H = frameSize.height
        let targetInk = CGFloat(SuhyunShortV1.Caption.inkHeightRatio) * H

        // 글자 높이 ≠ 폰트 크기. 1pt 당 실제 글자 높이를 재서 역산한다.
        let probeSize: CGFloat = 1000  // 크게 재야 반올림 오차가 안 섞인다
        let probeFont = MadiFont.pretendard(size: probeSize, weight: SuhyunShortV1.Caption.weight)
        let probeInk = inkBounds(metricProbe, font: probeFont)
        let perPoint = probeInk.height / probeSize
        let fontSize = targetInk / perPoint
        let inkMinYAtSize = probeInk.minY / probeSize * fontSize

        let strokeOuter = CGFloat(SuhyunShortV1.Caption.strokeOuterRatio) * H
        // stroke 는 경로 가운데 기준으로 그려진다. 바깥으로 strokeOuter 만큼 나가게 하려면 2배.
        // NSAttributedString.strokeWidth 는 px 가 아니라 폰트 크기 대비 백분율이다.
        let strokeWidthPercent = (2 * strokeOuter) / fontSize * 100

        // 본문: ink 아래끝을 목표에 맞춘다 → 베이스라인 = 목표 - ink 아래끝 오프셋
        let inkBottom = CGFloat(SuhyunShortV1.Caption.inkBottomRatio) * H
        let baselineFromBottom = inkBottom - inkMinYAtSize

        let secondaryFontSize = fontSize * SuhyunShortV1.Secondary.scale
        let secondaryBaseline = CGFloat(SuhyunShortV1.Secondary.baselineBottomRatio) * H

        return CaptionMetrics(
            fontSize: fontSize,
            inkHeight: targetInk,
            inkHeightPerPoint: perPoint,
            inkMinYAtSize: inkMinYAtSize,
            strokeOuter: strokeOuter,
            strokeWidthPercent: strokeWidthPercent,
            baselineFromBottom: baselineFromBottom,
            secondaryFontSize: secondaryFontSize,
            secondaryBaselineFromBottom: secondaryBaseline,
            lineStep: targetInk * CGFloat(SuhyunShortV1.Caption.lineGapRatio)
        )
    }

    /// 실제로 그려지는 글자 상자. 타이포그래피 상자(ascent/descent)가 아니라 **잉크** 상자다.
    /// 글자 높이 ≠ 폰트 크기 이므로 크기 역산은 전부 이 값에서 출발한다.
    public static func inkBounds(_ text: String, font: CTFont) -> CGRect {
        CTLineGetBoundsWithOptions(line(text, font: font), .useGlyphPathBounds)
    }

    /// 어절 단위 줄바꿈. 한글은 공백에서만 끊는다 (CSS `word-break: keep-all` 과 같은 규칙).
    /// 품질 게이트 G5: 한 줄 13자, 2줄 이내.
    public static func wrap(_ text: String, font: CTFont, maxWidth: CGFloat) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            let tooManyChars = candidate.count > SuhyunShortV1.Caption.maxChars
            let tooWide = advanceWidth(candidate, font: font) > maxWidth
            if !current.isEmpty && (tooManyChars || tooWide) {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }

        // 넘치면 마지막 줄에 몰아넣는다. 잘라서 뜻이 사라지는 것보다 낫다.
        if lines.count > SuhyunShortV1.Caption.maxLines {
            let head = Array(lines.prefix(SuhyunShortV1.Caption.maxLines - 1))
            let tail = lines.dropFirst(SuhyunShortV1.Caption.maxLines - 1).joined(separator: " ")
            lines = head + [tail]
        }
        return lines
    }

    public static func advanceWidth(_ text: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, font: font), nil, nil, nil))
    }

    private static func line(_ text: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineCreateWithAttributedString(attributed)
    }
}

// MARK: - 그리기

public enum CaptionPainter {

    /// 자막 한 덩어리를 그린다. 컨텍스트는 **y 가 위로 가는** 좌표계여야 한다 (CoreGraphics 기본).
    ///
    /// - Parameter scale: 등장 애니메이션용 배율. 자막 블록 중심 기준.
    public static func draw(
        _ caption: Caption,
        in ctx: CGContext,
        frameSize: CGSize,
        scale: CGFloat = 1
    ) {
        let m = CaptionLayout.metrics(frameSize: frameSize)
        let font = MadiFont.pretendard(size: m.fontSize, weight: SuhyunShortV1.Caption.weight)
        let maxWidth = CGFloat(SuhyunShortV1.Caption.maxWidthRatio) * frameSize.width
        let lines = CaptionLayout.wrap(caption.text, font: font, maxWidth: maxWidth)
        guard !lines.isEmpty else { return }

        ctx.saveGState()
        if scale != 1 {
            // 블록 중심에서 키운다. 화면 중앙 x, 본문 베이스라인 근처 y.
            let cx = frameSize.width / 2
            let cy = m.baselineFromBottom + m.inkHeight / 2
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -cx, y: -cy)
        }

        // 마지막 줄이 inkBottomRatio 에 오고 나머지가 위로 쌓인다.
        for (i, text) in lines.enumerated() {
            let fromLast = CGFloat(lines.count - 1 - i)
            let baseline = m.baselineFromBottom + fromLast * m.lineStep
            drawLine(
                text: text,
                emphasis: caption.emphasis,
                // 줄바꿈으로 사라진 공백 1자를 되돌려서 원문 인덱스와 맞춘다.
                emphasisOffset: lines.prefix(i).reduce(0) { $0 + $1.count + 1 },
                font: font,
                fill: SuhyunShortV1.captionFill,
                strokePercent: m.strokeWidthPercent,
                strokeColor: SuhyunShortV1.captionStroke,
                baselineFromBottom: baseline,
                in: ctx,
                frameSize: frameSize
            )
        }

        if let secondary = caption.secondary, !secondary.isEmpty {
            let sFont = MadiFont.pretendard(
                size: m.secondaryFontSize,
                weight: SuhyunShortV1.Secondary.weight
            )
            drawLine(
                text: secondary,
                emphasis: [],
                emphasisOffset: 0,
                font: sFont,
                fill: SuhyunShortV1.secondaryFill,
                // 원본 보조 문구에는 외곽선이 없다 (6배 확대해서 확인).
                strokePercent: SuhyunShortV1.Secondary.hasStroke ? m.strokeWidthPercent : 0,
                strokeColor: SuhyunShortV1.captionStroke,
                baselineFromBottom: m.secondaryBaselineFromBottom,
                in: ctx,
                frameSize: frameSize
            )
        }

        ctx.restoreGState()
    }

    /// 한 줄. stroke 패스를 먼저 깔고 fill 패스를 그 위에 얹는다.
    private static func drawLine(
        text: String,
        emphasis: [Caption.EmphasisRange],
        emphasisOffset: Int,
        font: CTFont,
        fill: RGBA,
        strokePercent: CGFloat,
        strokeColor: RGBA,
        baselineFromBottom: CGFloat,
        in ctx: CGContext,
        frameSize: CGSize
    ) {
        let width = CaptionLayout.advanceWidth(text, font: font)
        let x = (frameSize.width - width) / 2
        let y = baselineFromBottom

        // 1) 그림자. 외곽선 실루엣이 그림자를 만들도록 stroke 패스에만 건다.
        //    fill 패스에도 걸면 글자 안쪽에서 두 번 겹쳐 진해진다.
        if SuhyunShortV1.Shadow.enabled {
            let H = frameSize.height
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(
                    width: SuhyunShortV1.Shadow.offsetRatio.width * H,
                    height: SuhyunShortV1.Shadow.offsetRatio.height * H
                ),
                blur: CGFloat(SuhyunShortV1.Shadow.blurRatio) * H,
                color: SuhyunShortV1.Shadow.color.cgColor
            )
            drawPass(
                text: text, font: font, at: CGPoint(x: x, y: y), in: ctx,
                attributes: strokePercent > 0
                    ? strokeOnlyAttributes(font: font, percent: strokePercent, color: strokeColor)
                    : fillAttributes(font: font, color: fill)
            )
            ctx.restoreGState()
        }

        // 2) 외곽선. 양수 strokeWidth = 획만 그린다.
        if strokePercent > 0 {
            drawPass(
                text: text, font: font, at: CGPoint(x: x, y: y), in: ctx,
                attributes: strokeOnlyAttributes(font: font, percent: strokePercent, color: strokeColor)
            )
        }

        // 3) 채우기. 외곽선 안쪽 절반을 덮어서 글자가 깎이지 않게 한다.
        drawFill(
            text: text, font: font, color: fill,
            emphasis: emphasis, emphasisOffset: emphasisOffset,
            at: CGPoint(x: x, y: y), in: ctx
        )
    }

    /// ★ CoreText 속성 키를 직접 쓴다. AppKit 의 `NSAttributedString.Key.strokeWidth` 를 거치면
    ///   "양수 = 외곽선만, 음수 = 외곽선 + 채우기" 라는 규칙이 AppKit 것처럼 읽히는데,
    ///   실제로 그 규칙을 구현하는 건 CoreText 다. 읽는 사람이 헷갈리지 않게 원본 키를 쓴다.
    private static func strokeOnlyAttributes(
        font: CTFont, percent: CGFloat, color: RGBA
    ) -> [NSAttributedString.Key: Any] {
        [
            key(kCTFontAttributeName): font,
            // 양수 = 외곽선만. 음수면 채우기까지 같이 그려서 글자 안쪽이 획 절반만큼 깎인다.
            key(kCTStrokeWidthAttributeName): percent,
            key(kCTStrokeColorAttributeName): color.cgColor,
            key(kCTLigatureAttributeName): 0,
        ]
    }

    private static func fillAttributes(
        font: CTFont, color: RGBA
    ) -> [NSAttributedString.Key: Any] {
        [
            key(kCTFontAttributeName): font,
            key(kCTForegroundColorAttributeName): color.cgColor,
            key(kCTLigatureAttributeName): 0,
        ]
    }

    /// 채우기 패스. 강조 구간만 색을 바꾼다. **크기는 바꾸지 않는다** — 바꾸면 줄바꿈이 흔들린다.
    private static func drawFill(
        text: String, font: CTFont, color: RGBA,
        emphasis: [Caption.EmphasisRange], emphasisOffset: Int,
        at point: CGPoint, in ctx: CGContext
    ) {
        let attributed = NSMutableAttributedString(
            string: text, attributes: fillAttributes(font: font, color: color)
        )
        let chars = Array(text)
        for e in emphasis {
            let from = e.from - emphasisOffset
            let to = e.to - emphasisOffset
            guard from >= 0, to <= chars.count, from < to else { continue }
            let start = String(chars[0..<from]).utf16.count
            let length = String(chars[from..<to]).utf16.count
            attributed.addAttribute(
                key(kCTForegroundColorAttributeName),
                value: SuhyunShortV1.captionEmphasis.cgColor,
                range: NSRange(location: start, length: length)
            )
        }
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private static func key(_ name: CFString) -> NSAttributedString.Key {
        NSAttributedString.Key(name as String)
    }

    private static func drawPass(
        text: String, font: CTFont, at point: CGPoint, in ctx: CGContext,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

}

// MARK: - CALayer

/// 자막을 그리는 레이어. **자막을 이미지로 미리 굽지 않는다** (AGENTS.md §14).
/// CoreText 로 매번 그린다. 미리 구우면 그 순간 수정이 막힌다.
///
/// 프리뷰(`AVPlayer`)와 최종 렌더가 이 같은 레이어를 쓴다 (AGENTS.md §7).
public final class CaptionLayer: CALayer {
    private var caption: Caption?
    private var frameSize: CGSize = .zero

    public convenience init(caption: Caption, frameSize: CGSize) {
        self.init()
        self.caption = caption
        self.frameSize = frameSize
        self.frame = CGRect(origin: .zero, size: frameSize)
        self.contentsScale = 1
        self.isOpaque = false
        self.needsDisplayOnBoundsChange = true
        setNeedsDisplay()
    }

    public override init() { super.init() }

    public override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? CaptionLayer {
            caption = other.caption
            frameSize = other.frameSize
        }
    }

    public required init?(coder: NSCoder) { fatalError("스토리보드에서 만들지 않는다") }

    public override func draw(in ctx: CGContext) {
        guard let caption else { return }
        // CALayer 가 주는 컨텍스트는 macOS 에서 y 가 위로 가는 좌표계다.
        // 혹시 뒤집혀 오면 자막이 화면 위쪽에 그려지므로 StillRenderer 출력에서 바로 보인다.
        CaptionPainter.draw(caption, in: ctx, frameSize: frameSize)
    }

    /// 자막이 뜨고 사라지는 타이밍과 등장 애니메이션.
    ///
    /// `beginTime` 은 `AVCoreAnimationBeginTimeAtZero` 기준이어야 한다. 0 을 그대로 쓰면
    /// CoreAnimation 이 "지금"으로 해석해서 무시된다 (docs/stage-0.spec.md 알려진 함정).
    public func applyTiming(start: Double, end: Double, beginTimeAtZero: Double) {
        let appear = max(start, 0) + beginTimeAtZero
        opacity = 0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = appear
        fade.duration = max(SuhyunShortV1.Caption.popInSec * 0.6, 1.0 / 60)
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false

        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = SuhyunShortV1.Caption.popInScaleFrom
        pop.toValue = 1
        pop.beginTime = appear
        pop.duration = SuhyunShortV1.Caption.popInSec
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pop.fillMode = .both
        pop.isRemovedOnCompletion = false

        let hide = CABasicAnimation(keyPath: "opacity")
        hide.fromValue = 1
        hide.toValue = 0
        hide.beginTime = end + beginTimeAtZero
        hide.duration = 1.0 / 60
        hide.fillMode = .both
        hide.isRemovedOnCompletion = false

        add(fade, forKey: "madi.fadeIn")
        add(pop, forKey: "madi.popIn")
        add(hide, forKey: "madi.fadeOut")
    }
}
