import Foundation
import CoreGraphics
import CoreText
import MadiKit

/// 0단계 측정 루프용 도구. **제품 기능이 아니다.**
///
/// 자막 한 장을 PNG 로 뽑아 `node tools/measure.mjs` 로 재고, 숫자가 맞을 때까지
/// `Tokens.swift` 를 고치는 왕복에 쓴다 (docs/stage-0.spec.md 통과 조건 A).
///
///   madi-spike font
///   madi-spike metrics
///   madi-spike still out/caption-probe.png [--backdrop reference/yt_15s.png]
///   madi-spike render spike/composition.json out/spike.mp4

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--" + name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

/// 골든 프레임 `reference/yt_15s.png` 의 자막. 측정 기준이므로 바꾸지 않는다.
let goldenCaption = Caption(
    id: "probe",
    start: 0,
    end: 2,
    text: option("text") ?? "가능성이 높다는 겁니다",
    secondary: option("secondary") ?? "is likely misaligned."
)

let frameSize = CGSize(
    width: Double(option("width") ?? "") ?? Double(SuhyunShortV1.Frame.width),
    height: Double(option("height") ?? "") ?? Double(SuhyunShortV1.Frame.height)
)

switch args.first {

case "font":
    print("PostScript 이름: \(MadiFont.postScriptName ?? "(등록 실패)")")
    print("가변 축:")
    for axis in MadiFont.variationAxes() { print("  \(axis)") }
    // wght 가 실제로 먹는지 확인한다. 안 먹으면 굵기별 폭이 전부 같게 나온다.
    print("\n웨이트별 \"가능성이 높다는 겁니다\" 진행 폭 (size 100):")
    for w in [400, 600, 700, 800, 900] as [CGFloat] {
        let f = MadiFont.pretendard(size: 100, weight: w)
        let width = CaptionLayout.advanceWidth("가능성이 높다는 겁니다", font: f)
        let ink = CaptionLayout.inkBounds(CaptionLayout.metricProbe, font: f)
        print(String(format: "  wght %3.0f  폭 %7.2f  ink높이 %6.2f  ink아래끝 %6.2f",
                     w, width, ink.height, ink.minY))
    }

case "metrics":
    let m = CaptionLayout.metrics(frameSize: frameSize)
    print("프레임 \(Int(frameSize.width))x\(Int(frameSize.height))")
    print(String(format: "본문 폰트 크기        %.2f pt   (토큰이 아니라 역산값)", m.fontSize))
    print(String(format: "  1pt 당 글자 높이    %.4f", m.inkHeightPerPoint))
    print(String(format: "  목표 글자 높이      %.2f px  = 프레임 높이의 %.4f",
                 m.inkHeight, m.inkHeight / frameSize.height))
    print(String(format: "  ink 아래끝 오프셋   %.2f px", m.inkMinYAtSize))
    print(String(format: "  베이스라인(아래에서) %.2f px", m.baselineFromBottom))
    print(String(format: "외곽선 바깥 두께      %.2f px  → strokeWidth %.2f%%",
                 m.strokeOuter, m.strokeWidthPercent))
    print(String(format: "보조 폰트 크기        %.2f pt", m.secondaryFontSize))
    print(String(format: "  베이스라인(아래에서) %.2f px", m.secondaryBaselineFromBottom))
    print(String(format: "줄 간격               %.2f px", m.lineStep))

    let font = MadiFont.pretendard(size: m.fontSize, weight: SuhyunShortV1.Caption.weight)
    print("\n문자열별 ink 높이 (크기가 문자열에 따라 흔들리면 기준 문자열을 고쳐야 한다):")
    for s in [CaptionLayout.metricProbe, "가능성이 높다는 겁니다", "어깨가", "골반 틀어졌으면", "하나 둘 셋"] {
        let ink = CaptionLayout.inkBounds(s, font: font)
        print(String(format: "  %-22@  높이 %6.2f  아래끝 %6.2f  폭 %7.2f",
                     s as NSString, ink.height, ink.minY,
                     CaptionLayout.advanceWidth(s, font: font)))
    }

    let sFont = MadiFont.pretendard(
        size: m.secondaryFontSize, weight: SuhyunShortV1.Secondary.weight
    )
    let sInk = CaptionLayout.inkBounds("Ilk", font: sFont)
    print(String(format: "\n보조 라틴 어센더 높이 %.2f px  (원본 실측 16px @1280 = %.2f px @%d)",
                 sInk.height, 16.0 / 1280 * frameSize.height, Int(frameSize.height)))

case "still":
    guard args.count > 1 else { fail("사용법: madi-spike still <out.png> [--backdrop <png>]") }
    let out = URL(fileURLWithPath: args[1])
    let backdrop: StillRenderer.Backdrop
    if let path = option("backdrop") {
        backdrop = .image(URL(fileURLWithPath: path))
    } else {
        backdrop = .solid(RGBA(0.13, 0.13, 0.15, 1))
    }
    do {
        let image = try StillRenderer.renderCaption(
            goldenCaption, size: frameSize, backdrop: backdrop
        )
        try StillRenderer.writePNG(image, to: out)
        print("\(out.path)  \(image.width)x\(image.height)")
    } catch {
        fail("\(error)")
    }

// `render` · `frames` 는 A 를 통과한 뒤에 붙인다 (docs/stage-0.spec.md 작업순서 4 → 5).
// "4번을 건너뛰고 5번으로 가지 않는다."

default:
    print("""
    madi-spike — 0단계 측정 도구

      font                              등록된 폰트와 가변 축 확인
      metrics                           토큰에서 역산된 실제 픽셀 치수
      still <out.png> [--backdrop <png>]  자막 한 장

    공통 옵션: --text --secondary --width --height
    """)
}
