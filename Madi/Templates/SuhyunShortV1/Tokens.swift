import Foundation
import CoreGraphics

/// 스타일 자산. AGENTS.md §9 · docs/style-authoring.md.
///
/// ★ 이 파일의 값은 **`reference/` 프레임을 픽셀로 재서** 채운다. 추측해서 채우지 않는다.
///   전작이 기본값을 디자인 시안 색(#E8C33F 노란 박스, 56px)으로 박아 놓고
///   "스타일 학습" 이라고 부른 게 §0-4 실패 원인이다.
///
/// ★ 값은 전부 **프레임 높이 대비 비율**이다. 포인트 크기가 아니다.
///   "글자 높이 ≠ 폰트 크기" 이므로 폰트 크기는 `CaptionLayer` 가 CoreText 메트릭에서 역산한다
///   (docs/stage-0.spec.md 알려진 함정). 여기에 포인트 값을 적으면 폰트를 바꿀 때마다 전부 틀어진다.
///
/// 측정 출처: `reference/yt_15s.png` (720x1280).
/// 이 프레임은 `tools/measure.mjs` 의 세 목표치를 모두 통과하는 골든 프레임이다
/// (본문높이 3.59% · 하단여백 0.2352 · 보조하단 0.2039).
public enum SuhyunShortV1 {

    /// 값이 `docs/style-authoring.md §1` 의 5편 절차를 통과했는가.
    ///
    /// 아직 false 인 이유: 자막 실측은 유튜브 숏츠 1편(`EDpBGkaNJmU`)에서만 했다.
    /// 레이아웃 어휘는 5편을 봤지만(`docs/findings/2026-09-23-layout-survey.md`)
    /// 자막 치수는 아니다. 인스타 릴스 원본이 들어오면 5편으로 다시 재고 true 로 바꾼다.
    public static let measured = false

    public enum Frame {
        public static let width = 1080
        public static let height = 1920
        public static let fps = 30
    }

    // MARK: - 자막 본문

    public enum Caption {
        /// `wght` 가변 축.
        ///
        /// 실측 근거: `yt_15s.png` 에서 세로 획의 흰 폭이 5px, 글자 높이가 46px 이었다
        /// (획/글자높이 = 0.109). 이 비율이 나오는 웨이트를 `madi-spike stem` 으로 골랐다.
        /// 값을 바꾸면 반드시 다시 재고 이 주석을 고친다.
        public static let weight: CGFloat = 800

        /// **그려진 흰 글자의 높이** ÷ 프레임 높이.
        /// 실측 46px / 1280 = 0.0359. 신뢰도 높음 — 3편에서 같은 값.
        /// (`tools/measure.mjs` 가 흰 픽셀 밴드로 재는 값과 같은 정의다)
        public static let inkHeightRatio: Double = 0.0359

        /// 흰 글자 **아래끝**에서 화면 아래까지 ÷ 프레임 높이.
        /// 실측 0.2344~0.2352 (4프레임). 가장 흔들림이 적은 값이라 신뢰도 높음.
        /// ★ 블록 전체가 아니라 **본문 마지막 줄의 아래끝** 기준이다.
        ///   블록 기준으로 잡으면 보조 문구가 있을 때 본문이 밀려 올라간다 (archive/README.md).
        public static let inkBottomRatio: Double = 0.2352

        /// 검은 외곽선이 글자 **바깥으로** 나간 두께 ÷ 프레임 높이.
        /// 실측: 글자 위쪽 검은 띠 4px @1280 (= 6px @1920). 4/1280 = 0.003125.
        ///
        /// ★ 원본은 외곽선이 글자 안쪽을 **깎지 않는다.** 흰 픽셀 바로 위가 검은 4px 이고
        ///   그 안쪽은 온전히 흰색이다. 즉 "stroke 먼저, fill 나중" 순서로 그려졌다.
        ///   `NSAttributedString.strokeWidth` 를 음수로 주면 fill 먼저 stroke 나중이라
        ///   글자 안쪽이 획 절반만큼 깎인다 — 원본과 다르다. `CaptionLayer` 는 2패스로 그린다.
        public static let strokeOuterRatio: Double = 0.003125

        /// 화면 폭 대비 상한. **목표가 아니라 clamp 다** (docs/style-authoring.md).
        /// 참고: 실측에서 11자가 폭의 0.657 을 썼다. 12자여도 0.72 근처라 이 상한은 거의 안 걸린다.
        public static let maxWidthRatio: Double = 0.90

        /// 한 덩어리 최대 글자 수. 실측: 12자까지 한 줄로 갔다. 품질 게이트 G5.
        public static let maxChars = 13
        public static let maxLines = 2

        /// 2줄일 때 줄 간격 ÷ 글자 높이.
        /// ⚠ **미측정.** `reference/` 34장에 2줄 자막 프레임이 없었다.
        ///   폰트의 기본 행간(ascent+descent+leading)을 쓰면 한글에서 너무 벌어져서
        ///   1.35 로 뒀다. 2줄 자막이 나오는 프레임을 확보하면 재서 고친다.
        public static let lineGapRatio: Double = 1.35

        /// 등장 애니메이션. 픽셀로 못 재므로 연속 프레임을 세서 잡는다
        /// (docs/style-authoring.md §2). ⚠ 미측정 — 눈에 띄게 다르지만 않으면 된다.
        public static let popInSec: Double = 0.1
        public static let popInScaleFrom: CGFloat = 0.86
    }

    /// 본문 색. 실측: rgb(255,255,255) 순백.
    public static let captionFill = RGBA(1, 1, 1, 1)
    /// 외곽선 색. 실측: rgb(0,0,0).
    public static let captionStroke = RGBA(0, 0, 0, 1)

    /// 강조 단어.
    /// ★ 실측 영상에서는 강조를 **쓰지 않았다.** 본문은 전부 흰색이다.
    ///   기능은 남겨 두되 기본으로 쓰지 않는다. 쓸 근거가 생기면 그때 색을 정한다.
    public static let captionEmphasis = RGBA(1, 0.878, 0.302, 1) // #FFE04D

    // MARK: - 보조 문구 (영문 등)

    public enum Secondary {
        /// 본문 폰트 크기 대비 비율.
        /// 실측: 라틴 어센더 높이 16px, 베이스라인 y=1020 @1280.
        /// 본문 크기를 역산한 뒤 어센더 16px 이 나오는 비율을 `madi-spike metrics` 로 골랐다.
        public static let scale: CGFloat = 0.40

        /// 웨이트. 실측 이미지에서 획이 가늘고 균일 — Regular~Medium.
        public static let weight: CGFloat = 500

        /// 보조 문구 **베이스라인**에서 화면 아래까지 ÷ 프레임 높이.
        ///
        /// ★ 본문과 달리 ink 아래끝이 아니라 베이스라인으로 잡는다. 라틴 문자는 `y` · `g` 의
        ///   디센더가 얼마나 내려오는지가 글자마다 달라서 ink 아래끝이 문구에 따라 흔들린다.
        ///   베이스라인은 안 흔들린다.
        /// 실측: 행별 노란 픽셀 수가 y=1020 에서 46 → 6 으로 끊긴다 = 베이스라인 1020 @1280.
        ///   (1280 - 1020 - 1) / 1280 = 0.2023
        /// `tools/measure.mjs` 는 임계값 때문에 이 자막의 아래끝을 0.2039 로 읽는다. 그게 목표치다.
        public static let baselineBottomRatio: Double = 0.2023

        /// ★ 이탤릭이 **아니다.** 6배 확대해서 확인했다 — 글자가 곧게 서 있다.
        ///   (archive 의 Remotion 토큰은 `italic: true` 였다. 재보니 틀렸다)
        public static let italic = false

        /// ★ 외곽선이 **없다.** 노란 글자에 검은 테두리가 없고 부드러운 그림자만 있다.
        public static let hasStroke = false
    }

    /// 보조 문구 색. 실측: rgb(254,227,116) = #FEE374.
    public static let secondaryFill = RGBA(254.0 / 255, 227.0 / 255, 116.0 / 255, 1)

    // MARK: - 그림자

    /// 자막 아래에 깔리는 부드러운 그림자.
    ///
    /// 실측 근거: 본문 글자 위쪽 검은 띠는 4px 에서 배경으로 **딱 끊기는데**(929~932),
    /// 아래쪽은 5px 뒤 2px 에 걸쳐 배경으로 번진다(979~985, 루마 0 → 35 → 64 → 배경 81).
    /// 위아래 비대칭 + 아래쪽 번짐 = 아래로 조금 내린 흐린 그림자다.
    /// 보조 문구에서는 더 뚜렷하다 (외곽선이 없는데도 오른쪽 아래가 어둡다).
    ///
    /// ⚠ 신뢰도 낮음. 유튜브 720p 재인코딩본이라 압축 번짐과 구분이 어렵다.
    ///   `enabled` 를 false 로 두면 외곽선만 그린다.
    public enum Shadow {
        public static let enabled = true
        /// 프레임 높이 대비. 실측 1px @1280.
        public static let offsetRatio = CGSize(width: 1.0 / 1280, height: -1.0 / 1280)
        /// 프레임 높이 대비. 실측 번짐 폭 2px @1280.
        public static let blurRatio: Double = 2.0 / 1280
        public static let color = RGBA(0, 0, 0, 0.55)
    }

    // MARK: - 훅 · 리프레이밍 · 오디오 (1~2단계)

    /// ⚠ 전부 **미측정**. 0단계 범위 밖이라 재지 않았다.
    ///   1단계(리프레이밍)·2단계(템플릿 완성)에서 프레임을 재서 채운다.
    ///   지금 이 값으로 렌더하면 원본과 다르게 나온다 — 그래서 0단계 스파이크는 쓰지 않는다.
    public enum Reframe {
        /// 품질 게이트 G1 은 0.55 를 하한으로 본다. 목표는 그보다 넉넉히.
        public static let targetSubjectHeightRatio: Double = 0.72
        /// 이보다 짧게 스무딩하면 프레임이 떨린다 (G3).
        public static let smoothingSec: Double = 0.4
        public static let padding: Double = 0.08
    }
}

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
