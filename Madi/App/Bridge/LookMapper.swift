import Foundation
import MadiKit

/// 자막 모양(`§9` look) ↔ 설정 화면 `CaptionLook` (디자인 답 viewdata-map 5절 · 설정 자막 모양 탭).
///
/// - 고르는 것만 있다 — 숫자 입력이 없다. 굵기 4단계 · 색 견본 3개 · 글꼴 목록 · 기울임
/// - 굵기 대응 (디자인이 개발에 맡겼다): 보통 400 · **조금 굵게 480 (지금 기본값 — 크리에이터 원본 실측)** · 굵게 700 · 아주 굵게 900
/// - 색 견본 값: 흰색 #FFFFFF · 노란색 **#FEE374 (영문 줄 실측)** · 하늘색 #8CD1FF. 이름은 `Copy` 키가 생기면 거기서 —
///   지금은 부르는 쪽이 넘긴다 (copy-keys `swatchWhite` · `swatchYellow` · `swatchSky`)
/// - 바꾼 모양은 **새 스타일 판**으로 저장한다 — 옛 결과물은 자기 판으로 재현된다 (`§1-8`, `StyleStore.saveLook`)
enum LookMapper {

    static let weights: [(CaptionLook.Weight, Double)] = [(.regular, 400), (.medium, 480), (.bold, 700), (.heavy, 900)]

    static let swatchColors: [(id: String, rgba: RGBA)] = [
        ("white", RGBA(1, 1, 1, 1)),
        ("yellow", RGBA(254.0 / 255, 227.0 / 255, 116.0 / 255, 1)),
        ("sky", RGBA(140.0 / 255, 209.0 / 255, 1, 1)),
    ]

    static func weight(_ value: Double) -> CaptionLook.Weight {
        weights.min { abs($0.1 - value) < abs($1.1 - value) }!.0
    }

    static func value(_ w: CaptionLook.Weight) -> Double { weights.first { $0.0 == w }!.1 }

    static func swatches(order: [String], labels: [String: String]) -> [CaptionLook.Swatch] {
        order.compactMap { id in
            swatchColors.first { $0.id == id }.map {
                CaptionLook.Swatch(id: id, label: labels[id] ?? id, red: Double($0.rgba.r), green: Double($0.rgba.g), blue: Double($0.rgba.b))
            }
        }
    }

    /// 가장 가까운 견본.
    static func nearest(_ c: HexColor) -> String {
        swatchColors.min { dist($0.rgba, c.rgba) < dist($1.rgba, c.rgba) }!.id
    }

    static func dist(_ a: RGBA, _ b: RGBA) -> CGFloat {
        (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
    }

    static func look(_ l: StyleValues.LookValues, fonts: [String], labels: [String: String], preview: Thumbnail) -> CaptionLook {
        CaptionLook(
            fonts: fonts, font: l.caption.fontFamily, weight: weight(l.caption.weight), italic: l.caption.italic,
            fills: swatches(order: ["white", "yellow", "sky"], labels: labels), fill: nearest(l.caption.fill),
            secondaryFills: swatches(order: ["yellow", "white", "sky"], labels: labels), secondaryFill: nearest(l.secondary.fill),
            secondarySameAsMain: l.secondary.fontFamily == l.caption.fontFamily && l.secondary.italic == l.caption.italic,
            preview: preview,
            // 저장된 글꼴이 이 Mac 에 없다 — 조용히 대체하지 않는다 (§9)
            fontMissing: l.caption.fontFamily.map { !fonts.contains($0) } ?? false
        )
    }

    /// 사람이 고른 것 하나를 모양에 얹는다.
    static func apply(_ change: UIAction.Settings.Look, to l: StyleValues.LookValues) -> StyleValues.LookValues {
        var l = l
        let same = l.secondary.fontFamily == l.caption.fontFamily && l.secondary.italic == l.caption.italic
        func color(_ id: String) -> HexColor? { swatchColors.first { $0.id == id }.map { HexColor($0.rgba) } }
        switch change {
        case .font(let family):
            l.caption.fontFamily = family
            if same { l.secondary.fontFamily = family }
        case .weight(let w):
            l.caption.weight = value(w)
        case .italic(let on):
            l.caption.italic = on
            if same { l.secondary.italic = on }
        case .fill(let id):
            if let c = color(id) { l.caption.fill = c }
        case .secondaryFill(let id):
            if let c = color(id) { l.secondary.fill = c }
        case .secondarySameAsMain(let on):
            if on {
                l.secondary.fontFamily = l.caption.fontFamily
                l.secondary.italic = l.caption.italic
            }
        }
        return l
    }
}
