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

/// 스타일 값은 두 층이다.
///
/// | 층 | 무엇 | 누가 바꾸나 |
/// |---|---|---|
/// | 템플릿 (`caption` · `secondary` · `shadow` · `reframe`) | 크기 · 위치 · 분절 · 리프레임 | 측정. 사용자는 안 만진다 |
/// | **모양 (`look`)** | 글꼴 · 굵기 · 기울임 · 색 | **사용자가 설정에서 고른다** |
///
/// 근거: 크리에이터가 2026-08-27 에 자막 스타일을 바꿨는데, 바뀐 건 **글꼴과 기울임뿐**이었다.
/// 글자 크기 · 보조 크기 · 색 · 위치 규칙은 그대로였다
/// (`docs/findings/2026-09-27-secondary-10.md`). 스타일은 또 바뀔 수 있다 — 그때 바뀌는 쪽이 `look` 이다.
///
/// AI 는 어느 층도 쓸 수 없다 (`AGENTS.md §1-2`). `look` 은 **사람이** 고르는 값이다.
public struct StyleValues: Codable, Hashable, Sendable {
    public var caption: CaptionValues
    public var secondary: SecondaryValues
    public var shadow: ShadowValues
    public var reframe: ReframeValues
    public var look: LookValues

    public struct CaptionValues: Codable, Hashable, Sendable {
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
        /// 한 덩어리 글자 수 **상한**. G5 가 보는 값이다.
        public var maxChars: Int

        /// 구문 경계에서 끊기 전에 **최소한 담아야 할** 글자 수.
        ///
        /// ★ 목표값이 아니라 하한이다. 6 으로 두면 결과 덩어리 중앙값이 11~12자가 되고,
        ///   그게 크리에이터 실측(중앙 9~11자)과 가장 가깝다.
        ///   4~9 를 같은 3편에서 훑어 고른 값이다 —
        ///   경계 일치 tc6 58% · tc5 54% · tc4 62%(군더더기 28) · tc9 48%
        ///   (`docs/findings/2026-09-26-caption-splitter.md §3`).
        ///
        /// ⚠ **3~5편으로 고른 값이다.** 촬영본이 들어오면 다시 훑는다.
        public var minCharsBeforeBreak: Int

        /// 한 덩어리 목표 길이(초). 공개본 10편 전부 중앙값이 0.75~1.25초였다.
        /// **게이트가 아니다** — 실패 사례를 본 적이 없어 임계값으로 걸지 않는다.
        public var targetDurationSec: Double

        /// 한 덩어리가 이보다 길면 안 끊은 것으로 본다.
        ///
        /// 재는 법: 번인 자막(OCR) 덩어리의 실제 길이. 공개본 6편 118덩어리에서
        /// 중앙 0.75~1.25초 · **최대 2.75초**였다. 실측 최댓값을 넘지 않게 3.0 으로 둔다
        /// (`docs/findings/2026-09-26-whisperkit.md §3`).
        /// ★ 처음엔 2.5 로 추측했는데 **재 보니 크리에이터 자막 하나가 걸렸다.**
        public var maxDurationSec: Double


        /// 줄 수 상한. **2줄은 상한이지 목표가 아니다** — 190덩어리 중 2줄은 1개였다.
        public var maxLines: Int

        /// 2줄일 때 줄 간격 ÷ 글자 높이.
        /// 재는 법: 두 줄의 같은 지점(예: 글자 아래끝) 사이 픽셀 간격 ÷ 글자 높이.
        public var lineGapRatio: Double

        /// `look` 이 기울임을 켰는데 고른 글꼴에 이탤릭 자형이 없을 때 **기울이는 각도(도)**.
        ///
        /// 재는 법: 행을 밀어 세로 획이 가장 곧게 모이는 전단 각도 (`madi-spike secondary`).
        /// 크리에이터 B 스타일 6편이 본문 · 보조 모두 **+10°** 였다
        /// (`docs/findings/2026-09-27-secondary-10.md §1`).
        public var italicSlantDeg: Double

        /// 등장 애니메이션. 픽셀로 못 잰다.
        /// 재는 법: 연속 프레임 2~3장을 비교해 "몇 프레임 만에 제자리로 오는가"를 세고 fps 로 나눈다.
        /// 정확할 필요 없다. 눈에 띄게 다르지만 않으면 된다.
        public var popInSec: Double
        public var popInScaleFrom: Double
    }

    public struct SecondaryValues: Codable, Hashable, Sendable {
        /// 보조 문구 **라틴 어센더 높이**(`Ilk` 위끝 ~ 베이스라인) ÷ 프레임 높이.
        ///
        /// ★ 본문처럼 **글자 높이**로 적는다. 폰트 크기로 적으면 글꼴을 바꾸는 순간 크기가 흔들린다.
        ///   예전에는 "본문 폰트 크기 × 0.4444" 였는데, 본문 폰트 크기는 본문 글꼴의 한글 메트릭에서
        ///   역산하므로 **본문 글꼴이 보조 크기를 바꿔 버린다.** 실측은 A · B 스타일에서 보조 크기가 같았다.
        ///
        /// 재는 법: 노란 띠 맨 위 행 ~ 베이스라인 행 ÷ 프레임 높이 (`madi-spike secondary`).
        /// 값 0.01281271995563 은 옛 `scale` 0.4444 가 Pretendard 로 **실제로 그리던 높이**(24.60px @1920)다.
        /// 원본 실측은 24px(0.0125)이지만, 이 전환에서는 기본 출력을 1px 도 바꾸지 않는다.
        public var inkHeightRatio: Double

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
    }

    /// **사용자가 바꾸는 값.** 글꼴 · 굵기 · 기울임 · 색만 있다. 크기와 위치는 없다.
    ///
    /// 크리에이터에게 숫자를 만지게 하지 않는다 (`AGENTS.md §9`). 여기 값은 설정 화면에서
    /// **고르는** 것이다 — 글꼴 목록 · 기울임 켜기/끄기 · 색 견본.
    public struct LookValues: Codable, Hashable, Sendable {
        public var caption: TextLook
        public var secondary: TextLook
    }

    public struct TextLook: Codable, Hashable, Sendable {
        /// 글꼴 **패밀리 이름**. `nil` 이면 앱에 들어 있는 Pretendard.
        ///
        /// ★ 이 Mac 에 설치된 글꼴에서 고른다. 앱이 글꼴을 배포하지 않으므로 라이선스는
        ///   사용자 본인 것이다. 크리에이터가 편집 앱에서 쓰던 글꼴을 그대로 쓸 수 있다.
        /// ★ 설치돼 있지 않으면 **다른 글꼴로 조용히 그리지 않는다.** 스타일 검증에서 실패한다.
        public var fontFamily: String?

        /// 굵기. 100~900 (400 Regular · 700 Bold · 900 Black).
        /// 가변 글꼴이면 `wght` 축에 그대로 넣고, 아니면 가장 가까운 굵기의 자형을 고른다.
        ///
        /// 재는 법(Pretendard): 한글 세로 획 폭 ÷ 글자 높이가 원본과 같아지는 웨이트.
        /// `madi-spike stems` 가 웨이트별 비율을 찍어 준다.
        public var weight: Double

        /// 기울임. 글꼴에 이탤릭 자형이 있으면 그걸 쓰고, 없으면 `caption.italicSlantDeg` 만큼 기울인다.
        public var italic: Bool

        public var fill: HexColor
        /// 외곽선 색. `nil` 이면 외곽선을 그리지 않는다 (보조 문구 원본에는 없다).
        /// 두께는 템플릿(`caption.strokeOuterRatio`)이 정한다.
        public var stroke: HexColor?
        /// 강조 구간 색. 원본은 강조를 안 쓴다. 없으면 `fill` 로 그린다.
        public var emphasisFill: HexColor?
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
    check("caption.italicSlantDeg", c.italicSlantDeg, 0...20)
    if c.maxChars < 1 || c.maxChars > 40 {
        problems.append("caption.maxChars \(c.maxChars) 는 1~40 밖이다")
    }
    if c.minCharsBeforeBreak < 1 || c.minCharsBeforeBreak > c.maxChars {
        problems.append(
            "caption.minCharsBeforeBreak \(c.minCharsBeforeBreak) 는 1~maxChars 밖이다"
        )
    }
    if c.targetDurationSec <= 0 || c.targetDurationSec > 5 {
        problems.append("caption.targetDurationSec \(c.targetDurationSec) 는 0~5 밖이다")
    }
    if c.maxDurationSec < c.targetDurationSec || c.maxDurationSec > 10 {
        problems.append("caption.maxDurationSec \(c.maxDurationSec) 는 목표~10 밖이다")
    }
    if c.maxLines < 1 || c.maxLines > 3 {
        problems.append("caption.maxLines \(c.maxLines) 는 1~3 밖이다 (G5 는 2줄 이내)")
    }

    let s = values.secondary
    check("secondary.inkHeightRatio", s.inkHeightRatio, 0.005...c.inkHeightRatio)
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

    for (name, look) in [("look.caption", values.look.caption), ("look.secondary", values.look.secondary)] {
        check("\(name).weight", look.weight, 100...900)
        if let family = look.fontFamily {
            if family.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("\(name).fontFamily 가 비었다. 기본 글꼴이면 null 로 둔다")
            } else if !MadiFont.isInstalled(family: family) {
                problems.append("\(name).fontFamily \"\(family)\" 가 이 Mac 에 설치돼 있지 않다")
            }
        }
    }

    guard problems.isEmpty else { throw StyleError(problems: problems) }
}
