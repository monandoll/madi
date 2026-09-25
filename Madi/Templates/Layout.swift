import Foundation
import CoreGraphics
import CoreText

/// 자막 배치 규칙. **좌표는 전부 여기서만 나온다.**
///
/// 비율(스타일 값) → 픽셀(실제 좌표) 변환이 한 곳에 모여 있어야
/// "자막이 2px 위로 떠 있다" 를 한 파일에서 고칠 수 있다.
///
/// ★ 글자 높이 ≠ 폰트 크기. 폰트 크기는 스타일 값에 없다 —
///   `CTLineGetBoundsWithOptions(.useGlyphPathBounds)` 로 실제 글자 높이를 재서 역산한다.
///   웹(CSS)에서는 0.889 배였지만 CoreText 는 다르고, 폰트를 바꾸면 또 다르다.

/// 스타일 값과 CoreText 폰트 메트릭에서 나온 실제 픽셀 치수.
/// 테스트와 `madi-spike` 가 숫자를 직접 볼 수 있게 밖으로 낸다.
public struct CaptionMetrics: Sendable {
    /// 본문 폰트 포인트 크기. **스타일 값에 없다** — 글자 높이 목표에서 역산한 값이다.
    public let fontSize: CGFloat
    /// 목표 글자 높이(px).
    public let inkHeight: CGFloat
    /// 폰트 1pt 당 글자 높이. 폰트나 웨이트를 바꾸면 이 값이 바뀐다.
    public let inkHeightPerPoint: CGFloat
    /// 글자 ink 아래끝이 베이스라인에서 얼마나 떨어져 있나(px, 음수면 베이스라인 아래).
    public let inkMinYAtSize: CGFloat
    /// 검은 외곽선이 바깥으로 나가는 두께(px).
    public let strokeOuter: CGFloat
    /// CoreText `kCTStrokeWidthAttributeName` 에 넣을 값 (폰트 크기 대비 %).
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

public enum CaptionLayout {

    /// 폰트 메트릭을 재는 기준 문자열.
    ///
    /// ★ 자막마다 다른 문자열로 재면 안 된다. 원본은 글자 수와 무관하게 **크기가 고정**이다
    ///   (`docs/findings/2026-09-23-reference-measurement.md §2`).
    ///   받침 없는 글자와 받침이 큰 글자를 같이 넣어 한글 ink 상자의 위아래 끝을 잡는다.
    public static let metricProbe = "가힣"

    /// 보조 문구 크기를 재는 기준 문자열. 라틴 어센더 위끝 ~ 베이스라인.
    public static let secondaryMetricProbe = "Ilk"

    /// - Parameter slot: 이 영상(또는 장면)의 자막 위치. `Composition.captionSlot(for:)` 이 준다.
    public static func metrics(
        frameSize: CGSize, style: StyleValues, slot: CaptionSlot
    ) -> CaptionMetrics {
        let H = frameSize.height
        let caption = style.caption
        let targetInk = CGFloat(caption.inkHeightRatio) * H

        // 1pt 당 실제 글자 높이를 재서 폰트 크기를 역산한다.
        // 큰 크기로 재야 힌팅·반올림이 비율에 덜 섞인다.
        let probeSize: CGFloat = 1000
        let probeFont = MadiFont.pretendard(size: probeSize, weight: CGFloat(caption.weight))
        let probeInk = inkBounds(metricProbe, font: probeFont)
        let perPoint = probeInk.height / probeSize
        let fontSize = targetInk / perPoint
        let inkMinYAtSize = probeInk.minY / probeSize * fontSize

        let strokeOuter = CGFloat(caption.strokeOuterRatio) * H
        // 획은 경로 **가운데** 기준으로 그려진다. 바깥으로 strokeOuter 만큼 나가게 하려면 2배.
        // CoreText 의 strokeWidth 는 px 가 아니라 폰트 크기 대비 백분율이다.
        let strokeWidthPercent = fontSize > 0 ? (2 * strokeOuter) / fontSize * 100 : 0

        // 본문은 ink 아래끝을 목표에 맞춘다 (measure.mjs 가 재는 값과 같은 정의).
        let inkBottom = CGFloat(caption.inkBottomRatio[slot]) * H
        let baselineFromBottom = inkBottom - inkMinYAtSize

        return CaptionMetrics(
            fontSize: fontSize,
            inkHeight: targetInk,
            inkHeightPerPoint: perPoint,
            inkMinYAtSize: inkMinYAtSize,
            strokeOuter: strokeOuter,
            strokeWidthPercent: strokeWidthPercent,
            baselineFromBottom: baselineFromBottom,
            secondaryFontSize: fontSize * CGFloat(style.secondary.scale),
            // 보조는 **본문 아래끝에서 상대로** 잡는다. 본문이 움직이면 같이 움직여야 한다
            // (`docs/findings/2026-09-25-caption-position-10.md §3`).
            // 베이스라인으로 잡는 이유는 디센더 유무로 ink 아래끝이 흔들리기 때문이다.
            secondaryBaselineFromBottom: inkBottom
                - CGFloat(style.secondary.baselineOffsetRatio) * H,
            lineStep: targetInk * CGFloat(caption.lineGapRatio)
        )
    }

    /// 실제로 그려지는 글자 상자. 타이포그래피 상자(ascent/descent)가 아니라 **잉크** 상자다.
    public static func inkBounds(_ text: String, font: CTFont) -> CGRect {
        CTLineGetBoundsWithOptions(line(text, font: font), .useGlyphPathBounds)
    }

    public static func advanceWidth(_ text: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, font: font), nil, nil, nil))
    }

    /// 어절 단위 줄바꿈. 한글은 공백에서만 끊는다 (CSS `word-break: keep-all` 과 같은 규칙).
    /// 글자 한복판에서 끊기면 그 순간 자동 생성 자막처럼 보인다. 품질 게이트 G5.
    public static func wrap(
        _ text: String, font: CTFont, maxWidth: CGFloat, style: StyleValues.CaptionValues
    ) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            let tooManyChars = candidate.count > style.maxChars
            let tooWide = advanceWidth(candidate, font: font) > maxWidth
            if !current.isEmpty && (tooManyChars || tooWide) {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }

        // 줄 수를 넘으면 마지막 줄에 몰아넣는다. 잘라서 뜻이 사라지는 것보다 낫다.
        if lines.count > style.maxLines {
            let head = Array(lines.prefix(style.maxLines - 1))
            let tail = lines.dropFirst(style.maxLines - 1).joined(separator: " ")
            lines = head + [tail]
        }
        return lines
    }

    private static func line(_ text: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineCreateWithAttributedString(attributed)
    }
}
