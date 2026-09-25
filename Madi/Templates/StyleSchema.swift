import Foundation
import CoreGraphics

/// 스타일 **파라미터 정의 · 검증 범위**. AGENTS.md §9 · docs/style-authoring.md.
///
/// ★ 여기에 **값을 적지 않는다.** 값은 `Resources/styles/short.v1.json` 에 있다.
///   스키마는 코드(빌드 필요), 값은 데이터(빌드 불필요)다. 그래야 "자막이 좀 큰 것 같은데" 에
///   빌드 없이 답할 수 있다.
///
/// ★ 값은 전부 **프레임 높이 대비 비율**이다. 포인트 크기가 아니다.
///   "글자 높이 ≠ 폰트 크기" 이므로 폰트 크기는 `CaptionLayout` 이 CoreText 메트릭에서 역산한다.
///   JSON 에 포인트 값을 적으면 폰트를 바꾸는 순간 전부 틀어진다.
///
/// 각 파라미터 주석은 **재는 법**을 적는다. 값이 아니라 절차가 코드에 남아야
/// 다음 사람이 같은 방법으로 다시 잴 수 있다.

// MARK: - 색

/// 0..1 색. `CGColor` 로 바꿔 쓴다.
public struct RGBA: Hashable, Sendable {
    public var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
    }
}

/// `"#RRGGBB"` 또는 `"#RRGGBBAA"`.
public struct HexColor: Codable, Hashable, Sendable {
    public var rgba: RGBA

    public init(_ rgba: RGBA) { self.rgba = rgba }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = HexColor.parse(raw) else {
            throw StyleError(problems: ["색 \(raw) 을 읽지 못했습니다. #RRGGBB 또는 #RRGGBBAA 여야 합니다"])
        }
        rgba = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        let v = { (x: CGFloat) in Int((x * 255).rounded()) }
        try c.encode(String(
            format: rgba.a >= 1 ? "#%02X%02X%02X" : "#%02X%02X%02X%02X",
            v(rgba.r), v(rgba.g), v(rgba.b), v(rgba.a)
        ))
    }

    static func parse(_ raw: String) -> RGBA? {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        let byte = { (shift: UInt32) in CGFloat((value >> shift) & 0xFF) / 255 }
        if hex.count == 6 {
            return RGBA(byte(16), byte(8), byte(0), 1)
        }
        return RGBA(byte(24), byte(16), byte(8), byte(0))
    }
}

// MARK: - 파라미터

/// `CaptionSlot` 별 값. **좌표는 여기(스타일)에만 있다.**
/// AI 는 슬롯 **이름**만 고르고 숫자는 못 만진다 (AGENTS.md §1-2).
public struct SlotPositions: Codable, Hashable, Sendable {
    public var upperBody: Double
    public var fullBody: Double
    public var lowerBody: Double

    public init(upperBody: Double, fullBody: Double, lowerBody: Double) {
        self.upperBody = upperBody; self.fullBody = fullBody; self.lowerBody = lowerBody
    }

    public subscript(slot: CaptionSlot) -> Double {
        get {
            switch slot {
            case .upperBody: upperBody
            case .fullBody: fullBody
            case .lowerBody: lowerBody
            }
        }
        set {
            switch slot {
            case .upperBody: upperBody = newValue
            case .fullBody: fullBody = newValue
            case .lowerBody: lowerBody = newValue
            }
        }
    }

    public var all: [(CaptionSlot, Double)] {
        [(.upperBody, upperBody), (.fullBody, fullBody), (.lowerBody, lowerBody)]
    }
}

public struct StyleValues: Codable, Hashable, Sendable {
    public var caption: CaptionValues
    public var secondary: SecondaryValues
    public var shadow: ShadowValues
    public var reframe: ReframeValues

    public struct CaptionValues: Codable, Hashable, Sendable {
        /// Pretendard 의 `wght` 가변 축. 400 Regular · 700 Bold · 800 ExtraBold · 900 Black.
        ///
        /// 재는 법: 원본 프레임에서 한글 세로 획의 **흰 폭(px)** 과 **글자 높이(px)** 를 재고
        /// 그 비율이 나오는 웨이트를 고른다. `madi-spike stems` 가 웨이트별 비율을 찍어 준다.
        /// 눈대중으로 "굵어 보인다"로 정하지 않는다.
        public var weight: Double

        /// **그려진 글자의 높이** ÷ 프레임 높이.
        ///
        /// 재는 법: 자막 영역에서 흰 픽셀이 찍힌 행의 위아래 끝을 세고 프레임 높이로 나눈다.
        /// `tools/measure.mjs` 의 "본문높이" 와 같은 정의다 — 그래서 바로 대조가 된다.
        /// ★ 폰트 크기가 아니다. 폰트 크기는 이 값에서 역산한다.
        public var inkHeightRatio: Double

        /// 글자 **아래끝**에서 화면 아래까지 ÷ 프레임 높이. **슬롯마다 하나씩.**
        ///
        /// 재는 법: 흰 픽셀 마지막 행의 아래 여백 ÷ 프레임 높이.
        /// ★ 블록 전체가 아니라 **마지막 줄의 아래끝** 기준이다. 블록 기준으로 잡으면
        ///   보조 문구가 있을 때 본문이 밀려 올라간다 (archive/README.md 의 교훈).
        /// ★ 값이 셋인 이유: 공개본 10편에서 **편 안에서는 고정, 편 사이에서는 0.235~0.483**
        ///   으로 갈렸다. 하나로 뭉개면 어느 무리에서든 틀린다
        ///   (`docs/findings/2026-09-25-caption-position-10.md`).
        public var inkBottomRatio: SlotPositions

        /// 검은 외곽선이 글자 **바깥으로** 나간 두께 ÷ 프레임 높이. 안쪽은 세지 않는다.
        ///
        /// 재는 법: 글자 위쪽에서 검은 픽셀이 몇 행 이어지는지 센다.
        /// ★ CoreText `strokeWidth` 는 px 가 아니라 폰트 크기 대비 백분율이고 획 **가운데** 기준이다.
        ///   변환은 `CaptionLayout` 이 한다. 여기에는 눈에 보이는 바깥 두께를 적는다.
        public var strokeOuterRatio: Double

        /// 화면 폭 대비 상한. **목표가 아니라 clamp 다.**
        /// 실제 폭을 채우는 건 글자 크기이고, 원본은 크기가 고정이라 이 값은 거의 안 걸린다.
        public var maxWidthRatio: Double

        /// 한 덩어리 최대 글자 수 · 최대 줄 수. 품질 게이트 G5.
        ///
        /// 재는 법: **한 편을 처음부터 끝까지** 보고 한 번에 뜬 글자 수의 최댓값(공백 포함).
        /// 프레임 몇 장만 보면 최댓값을 놓친다 — 12자로 뒀다가 원본의 15자 자막이
        /// 두 줄로 쪼개진 적이 있다 (`docs/findings/2026-09-25-coretext-caption-measurement.md §9`).
        ///
        /// ★ 글자 수는 실제 제약이 아니다. **폭이 제약**이고 `maxWidthRatio` 가 이미 막는다.
        ///   이 값은 근사치이므로 의심스러우면 느슨하게 두고 폭에 맡긴다.
        public var maxChars: Int
        public var maxLines: Int

        /// 2줄일 때 줄 간격 ÷ 글자 높이.
        /// 재는 법: 두 줄의 같은 지점(예: 글자 아래끝) 사이 픽셀 간격 ÷ 글자 높이.
        public var lineGapRatio: Double

        public var fill: HexColor
        public var stroke: HexColor
        /// 강조 구간 색. 쓰지 않을 수도 있다 — 원본이 강조를 안 쓰면 `emphasis` 를 비워 둔다.
        public var emphasisFill: HexColor

        /// 등장 애니메이션. 픽셀로 못 잰다.
        /// 재는 법: 연속 프레임 2~3장을 비교해 "몇 프레임 만에 제자리로 오는가"를 세고 fps 로 나눈다.
        /// 정확할 필요 없다. 눈에 띄게 다르지만 않으면 된다.
        public var popInSec: Double
        public var popInScaleFrom: Double
    }

    public struct SecondaryValues: Codable, Hashable, Sendable {
        /// 본문 폰트 크기 대비 비율.
        /// 재는 법: 보조 문구의 라틴 어센더 높이(`l` · `k` 위끝 ~ 베이스라인)를 재고,
        /// 그 높이가 나오는 비율을 `madi-spike metrics` 로 맞춘다.
        public var scale: Double
        public var weight: Double

        /// 본문 글자 아래끝에서 보조 문구 **베이스라인**까지의 거리 ÷ 프레임 높이.
        /// 값이 클수록 보조가 본문에서 멀어진다(아래로 내려간다).
        ///
        /// ★ **절대 위치가 아니라 본문 기준 상대 위치다.** 공개 숏폼 10편을 재 보니
        ///   본문 위치는 0.235 ~ 0.483 으로 프레임 높이의 25% 나 벌어지는데
        ///   이 간격은 **0.031 ~ 0.041 로 붙어 있다**
        ///   (`docs/findings/2026-09-25-caption-position-10.md §3`).
        ///   절대값으로 두면 본문이 움직일 때 보조가 따로 논다.
        ///
        /// ★ 본문과 달리 ink 아래끝이 아니라 베이스라인으로 잡는다. 라틴 문자는 `y` · `g` 의
        ///   디센더 유무가 문구마다 달라서 ink 아래끝이 흔들린다. 베이스라인은 안 흔들린다.
        /// 재는 법: (본문 흰 픽셀 마지막 행) − (보조 행별 픽셀 수가 뚝 떨어지는 행) ÷ 프레임 높이.
        public var baselineOffsetRatio: Double

        public var fill: HexColor
        public var italic: Bool
        /// 보조 문구에도 외곽선을 그릴지. 원본에 없으면 false.
        public var hasStroke: Bool
    }

    /// 자막 아래에 깔리는 흐린 그림자.
    ///
    /// 재는 법: 글자 위쪽 검은 띠는 배경으로 **딱 끊기는데** 아래쪽은 몇 px 에 걸쳐 번지면
    /// 아래로 내린 그림자가 있는 것이다. 번지는 폭이 blur, 위아래 비대칭 양이 offset 이다.
    public struct ShadowValues: Codable, Hashable, Sendable {
        public var enabled: Bool
        /// 프레임 높이 대비. y 는 아래로 갈수록 음수 (CoreGraphics 좌표).
        public var offsetXRatio: Double
        public var offsetYRatio: Double
        public var blurRatio: Double
        public var fill: HexColor
    }

    public struct ReframeValues: Codable, Hashable, Sendable {
        /// 인물 높이가 프레임 높이의 이만큼을 채우도록. **미학 목표**이지 게이트가 아니다
        /// (하드 게이트 G1 하한은 0.55).
        public var targetSubjectHeightRatio: Double

        /// 확대 상한 — **업스케일 배수**의 최대값.
        ///
        /// ```
        /// 배율 1 크롭 폭(px) = min(소스 폭, 소스 높이 × 9/16)
        /// 업스케일 배수 U    = 출력 폭 ÷ (배율 1 크롭 폭 ÷ 배율)
        /// 최대 배율          = 배율 1 크롭 폭 ÷ 출력 폭 × maxUpscale
        /// ```
        ///
        /// 즉 **원본 해상도마다 최대 배율이 달라진다.** 세로 4K 는 2.5배까지,
        /// 1080p 는 확대 자체가 불가능하다 (9:16 크롭 폭이 608px 뿐이라 이미 1.78배 업스케일).
        ///
        /// ⚠ **추측한 값이다.** 1.0 / 1.25 / 1.5 를 3배 확대해 눈으로 비교해 골랐다 —
        ///   1.00 또렷 · 1.25 미세하게 무름 · 1.50 눈에 띄게 뭉갬.
        ///   평균 |라플라시안| 선명도 지표는 업스케일 에일리어싱을 디테일로 착각해서 버렸다
        ///   (`docs/findings/2026-09-25-zoom-design.md §2`).
        ///   비교 프레임: `docs/findings/frames/2026-09-25-upscale-1.0-1.25-1.5.jpg`
        public var maxUpscale: Double

        /// 이보다 짧게 스무딩하면 프레임이 떨린다 (G3).
        public var smoothingSec: Double
        public var padding: Double
    }
}

// MARK: - 검증

public struct StyleError: Error, CustomStringConvertible {
    public let problems: [String]
    public var description: String {
        "스타일 값이 올바르지 않습니다:\n" + problems.map { "  - \($0)" }.joined(separator: "\n")
    }
}

/// 값이 말이 되는 범위 안에 있는지 본다.
///
/// 범위를 두는 이유: JSON 은 빌드를 안 거치므로 오타가 그대로 렌더까지 간다.
/// `inkHeightRatio` 에 0.359 (소수점 하나 밀림) 를 적으면 자막이 화면을 덮는다.
/// 값을 **막는 게 아니라** 명백히 틀린 걸 잡는 범위다 — 좁게 잡아서 측정 결과를 거절하지 않는다.
public func validate(_ values: StyleValues) throws {
    var problems: [String] = []

    func check(_ name: String, _ value: Double, _ range: ClosedRange<Double>) {
        if !range.contains(value) {
            problems.append("\(name) \(value) 는 \(range.lowerBound)~\(range.upperBound) 밖이다")
        }
    }

    let c = values.caption
    check("caption.weight", c.weight, 100...900)
    // 품질 게이트 G4 하한이 0.032 다. 그보다 아래는 자동 자막처럼 보인다.
    check("caption.inkHeightRatio", c.inkHeightRatio, 0.02...0.12)
    for (slot, value) in c.inkBottomRatio.all {
        check("caption.inkBottomRatio.\(slot.rawValue)", value, 0.02...0.6)
    }
    // 슬롯이 이름 순서대로 위로 올라가야 한다. 뒤집히면 이름이 거짓말을 한다.
    if !(c.inkBottomRatio.upperBody < c.inkBottomRatio.fullBody
         && c.inkBottomRatio.fullBody < c.inkBottomRatio.lowerBody) {
        problems.append(
            "caption.inkBottomRatio 는 upperBody < fullBody < lowerBody 여야 한다 "
            + "(지금 \(c.inkBottomRatio.upperBody) / \(c.inkBottomRatio.fullBody) "
            + "/ \(c.inkBottomRatio.lowerBody))"
        )
    }
    check("caption.strokeOuterRatio", c.strokeOuterRatio, 0...0.02)
    check("caption.maxWidthRatio", c.maxWidthRatio, 0.3...1.0)
    check("caption.lineGapRatio", c.lineGapRatio, 1.0...3.0)
    check("caption.popInSec", c.popInSec, 0...1)
    check("caption.popInScaleFrom", c.popInScaleFrom, 0.3...1.0)
    if c.maxChars < 1 || c.maxChars > 40 {
        problems.append("caption.maxChars \(c.maxChars) 는 1~40 밖이다")
    }
    if c.maxLines < 1 || c.maxLines > 3 {
        problems.append("caption.maxLines \(c.maxLines) 는 1~3 밖이다 (G5 는 2줄 이내)")
    }

    let s = values.secondary
    check("secondary.scale", s.scale, 0.2...1.0)
    check("secondary.weight", s.weight, 100...900)
    // 0 이면 본문과 겹치고, 음수면 본문 위로 올라간다. 실측은 0.031~0.041 이다.
    check("secondary.baselineOffsetRatio", s.baselineOffsetRatio, 0.005...0.15)

    let sh = values.shadow
    check("shadow.offsetXRatio", sh.offsetXRatio, -0.02...0.02)
    check("shadow.offsetYRatio", sh.offsetYRatio, -0.02...0.02)
    check("shadow.blurRatio", sh.blurRatio, 0...0.02)

    let r = values.reframe
    check("reframe.targetSubjectHeightRatio", r.targetSubjectHeightRatio, 0.3...1.0)
    // 1.0 = 무손실만. 2.0 을 넘으면 눈에 띄게 뭉갠다.
    check("reframe.maxUpscale", r.maxUpscale, 1.0...2.0)
    check("reframe.smoothingSec", r.smoothingSec, 0...2)
    check("reframe.padding", r.padding, 0...0.5)

    // 어느 슬롯에서도 보조가 화면 밖으로 나가면 안 된다.
    for (slot, bottom) in c.inkBottomRatio.all where bottom - s.baselineOffsetRatio <= 0 {
        problems.append(
            "caption.inkBottomRatio.\(slot.rawValue)(\(bottom)) 에서 "
            + "secondary.baselineOffsetRatio(\(s.baselineOffsetRatio)) 를 빼면 화면 밖이다"
        )
    }

    guard problems.isEmpty else { throw StyleError(problems: problems) }
}
