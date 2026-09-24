import Foundation
import CoreGraphics
import CoreText
import QuartzCore

/// 0단계의 핵심. `docs/stage-0.spec.md` 작업순서 4.
///
/// 이 파일 하나가 원본과 구분 안 되면 0단계는 사실상 통과다.
/// 반대로 여기서 다르면 영상 전체가 다르게 보인다. 다른 걸 만들기 전에 여기부터 맞춘다.
///
/// ★ 스타일 값을 **주입받는다.** 상수를 직접 참조하지 않는다 (AGENTS.md §9).
///   값은 `Resources/styles/short.v1.json` 에 있고 빌드 없이 바뀐다.
///
/// ## 원본이 그려진 방식 (실측으로 확인한 것)
///
/// `reference/yt_15s.png` 에서 흰 글자 바로 위가 검은 4px 이고 그 안쪽은 온전한 흰색이다.
/// 즉 외곽선이 글자 안쪽을 깎지 않는다 → **stroke 를 먼저 깔고 fill 을 그 위에 얹었다.**
///
/// CoreText 에 음수 `strokeWidth` 를 주면 fill → stroke 순으로 그려서 획 절반이 글자 안쪽을
/// 파먹는다. 글자 높이가 획 두께만큼 줄고 획도 가늘어 보인다 — 원본과 다르다.
/// 그래서 여기서는 **두 번 그린다**: stroke 전용 패스(양수 strokeWidth) → fill 패스.

public enum CaptionPainter {

    /// 자막 한 덩어리를 그린다. 컨텍스트는 **y 가 위로 가는** 좌표계여야 한다 (CoreGraphics 기본).
    ///
    /// - Parameter scale: 등장 애니메이션용 배율. 자막 블록 중심 기준.
    public static func draw(
        _ caption: Caption,
        in ctx: CGContext,
        frameSize: CGSize,
        style: StyleValues,
        scale: CGFloat = 1
    ) {
        let m = CaptionLayout.metrics(frameSize: frameSize, style: style)
        let font = MadiFont.pretendard(size: m.fontSize, weight: CGFloat(style.caption.weight))
        let maxWidth = CGFloat(style.caption.maxWidthRatio) * frameSize.width
        let lines = CaptionLayout.wrap(
            caption.text, font: font, maxWidth: maxWidth, style: style.caption
        )
        guard !lines.isEmpty else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        if scale != 1 {
            // 블록 중심에서 키운다. 화면 중앙 x, 본문 글자 한가운데 y.
            let cx = frameSize.width / 2
            let cy = m.baselineFromBottom + m.inkHeight / 2
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -cx, y: -cy)
        }

        // 마지막 줄이 inkBottomRatio 에 오고 나머지가 위로 쌓인다.
        for (i, text) in lines.enumerated() {
            let fromLast = CGFloat(lines.count - 1 - i)
            drawLine(
                text: text,
                emphasis: caption.emphasis,
                // 줄바꿈으로 사라진 공백 1자를 되돌려 원문 인덱스와 맞춘다.
                emphasisOffset: lines.prefix(i).reduce(0) { $0 + $1.count + 1 },
                font: font,
                fill: style.caption.fill.rgba,
                emphasisFill: style.caption.emphasisFill.rgba,
                strokePercent: m.strokeWidthPercent,
                strokeColor: style.caption.stroke.rgba,
                baselineFromBottom: m.baselineFromBottom + fromLast * m.lineStep,
                in: ctx, frameSize: frameSize, style: style
            )
        }

        if let secondary = caption.secondary, !secondary.isEmpty {
            let sFont = MadiFont.pretendard(
                size: m.secondaryFontSize,
                weight: CGFloat(style.secondary.weight),
                italic: style.secondary.italic
            )
            drawLine(
                text: secondary,
                emphasis: [], emphasisOffset: 0,
                font: sFont,
                fill: style.secondary.fill.rgba,
                emphasisFill: style.secondary.fill.rgba,
                // 원본 보조 문구에는 외곽선이 없다 (6배 확대해서 확인).
                strokePercent: style.secondary.hasStroke ? m.strokeWidthPercent : 0,
                strokeColor: style.caption.stroke.rgba,
                baselineFromBottom: m.secondaryBaselineFromBottom,
                in: ctx, frameSize: frameSize, style: style
            )
        }
    }

    /// 한 줄. 그림자 → 외곽선 → 채우기 순으로 세 번 그린다.
    private static func drawLine(
        text: String,
        emphasis: [Caption.EmphasisRange],
        emphasisOffset: Int,
        font: CTFont,
        fill: RGBA,
        emphasisFill: RGBA,
        strokePercent: CGFloat,
        strokeColor: RGBA,
        baselineFromBottom: CGFloat,
        in ctx: CGContext,
        frameSize: CGSize,
        style: StyleValues
    ) {
        let width = CaptionLayout.advanceWidth(text, font: font)
        let origin = CGPoint(x: (frameSize.width - width) / 2, y: baselineFromBottom)
        let hasStroke = strokePercent > 0

        // 1) 그림자. 바깥 실루엣(외곽선이 있으면 외곽선, 없으면 글자)만 그림자를 만든다.
        //    세 패스 전부에 그림자를 걸면 글자 안쪽에서 겹쳐 진해진다.
        if style.shadow.enabled {
            let H = frameSize.height
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(
                    width: CGFloat(style.shadow.offsetXRatio) * H,
                    height: CGFloat(style.shadow.offsetYRatio) * H
                ),
                blur: CGFloat(style.shadow.blurRatio) * H,
                color: style.shadow.fill.rgba.cgColor
            )
            draw(
                text: text, at: origin, in: ctx,
                attributes: hasStroke
                    ? strokeAttributes(font: font, percent: strokePercent, color: strokeColor)
                    : fillAttributes(font: font, color: fill)
            )
            ctx.restoreGState()
        }

        // 2) 외곽선. 양수 strokeWidth = 획만 그린다.
        if hasStroke {
            draw(
                text: text, at: origin, in: ctx,
                attributes: strokeAttributes(font: font, percent: strokePercent, color: strokeColor)
            )
        }

        // 3) 채우기. 외곽선 중 글자 안쪽으로 들어온 절반을 덮는다.
        drawFill(
            text: text, font: font, color: fill, emphasisColor: emphasisFill,
            emphasis: emphasis, emphasisOffset: emphasisOffset, at: origin, in: ctx
        )
    }

    /// ★ CoreText 속성 키를 직접 쓴다. AppKit 의 `NSAttributedString.Key.strokeWidth` 를 거치면
    ///   "양수 = 외곽선만" 이라는 규칙이 AppKit 것처럼 읽히는데, 실제로 그 규칙을 구현하는 건
    ///   CoreText 다. 읽는 사람이 헷갈리지 않게 원본 키를 쓴다.
    private static func strokeAttributes(
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

    private static func fillAttributes(font: CTFont, color: RGBA) -> [NSAttributedString.Key: Any] {
        [
            key(kCTFontAttributeName): font,
            key(kCTForegroundColorAttributeName): color.cgColor,
            key(kCTLigatureAttributeName): 0,
        ]
    }

    private static func key(_ name: CFString) -> NSAttributedString.Key {
        NSAttributedString.Key(name as String)
    }

    /// 채우기 패스. 강조 구간만 **색**을 바꾼다. 크기는 바꾸지 않는다 — 바꾸면 줄바꿈이 흔들린다.
    private static func drawFill(
        text: String, font: CTFont, color: RGBA, emphasisColor: RGBA,
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
            attributed.addAttribute(
                key(kCTForegroundColorAttributeName),
                value: emphasisColor.cgColor,
                range: NSRange(
                    location: String(chars[0..<from]).utf16.count,
                    length: String(chars[from..<to]).utf16.count
                )
            )
        }
        draw(line: CTLineCreateWithAttributedString(attributed), at: point, in: ctx)
    }

    private static func draw(
        text: String, at point: CGPoint, in ctx: CGContext,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        draw(line: CTLineCreateWithAttributedString(attributed), at: point, in: ctx)
    }

    private static func draw(line: CTLine, at point: CGPoint, in ctx: CGContext) {
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
/// 둘이 다른 코드로 그리면 여기서 맞춘 숫자가 영상에서 의미가 없어진다.
public final class CaptionLayer: CALayer {
    private var caption: Caption?
    private var styleValues: StyleValues?
    private var frameSize: CGSize = .zero

    public convenience init(caption: Caption, frameSize: CGSize, style: StyleValues) {
        self.init()
        self.caption = caption
        self.styleValues = style
        self.frameSize = frameSize
        self.frame = CGRect(origin: .zero, size: frameSize)
        // 치수를 픽셀로 재기 때문에 스케일을 곱하지 않는다.
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
            styleValues = other.styleValues
            frameSize = other.frameSize
        }
    }

    public required init?(coder: NSCoder) { fatalError("스토리보드에서 만들지 않는다") }

    public override func draw(in ctx: CGContext) {
        guard let caption, let styleValues else { return }
        CaptionPainter.draw(caption, in: ctx, frameSize: frameSize, style: styleValues)
    }

    /// 자막이 뜨고 사라지는 타이밍과 등장 애니메이션.
    ///
    /// `beginTime` 은 `AVCoreAnimationBeginTimeAtZero` 기준이어야 한다. 0 을 그대로 쓰면
    /// CoreAnimation 이 "지금" 으로 해석해서 무시된다 (docs/stage-0.spec.md 알려진 함정).
    public func applyTiming(start: Double, end: Double, beginTimeAtZero: Double) {
        guard let styleValues else { return }
        let appear = max(start, 0) + beginTimeAtZero
        opacity = 0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = appear
        fade.duration = max(styleValues.caption.popInSec * 0.6, 1.0 / 60)

        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = styleValues.caption.popInScaleFrom
        pop.toValue = 1
        pop.beginTime = appear
        pop.duration = max(styleValues.caption.popInSec, 1.0 / 60)
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let hide = CABasicAnimation(keyPath: "opacity")
        hide.fromValue = 1
        hide.toValue = 0
        hide.beginTime = end + beginTimeAtZero
        hide.duration = 1.0 / 60

        for (animation, key) in [(fade, "madi.fadeIn"), (pop, "madi.popIn"), (hide, "madi.fadeOut")] {
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            add(animation, forKey: key)
        }
    }
}
