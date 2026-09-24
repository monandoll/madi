import Foundation
import CoreGraphics
import CoreText
import AVFoundation
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

// 최상위 코드에서 await 를 쓴다. Swift 는 main.swift 에서만 이걸 허용한다.
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
    width: Double(option("width") ?? "") ?? 1080,
    height: Double(option("height") ?? "") ?? 1920
)

/// 스타일 값은 파일에서 읽는다. `MADI_STYLES_DIR` 로 레포의 JSON 을 바로 가리킬 수 있어서
/// 값을 고치고 다시 그리는 데 빌드가 필요 없다 (AGENTS.md §9).
let style: Style
do {
    style = try StyleStore.load(option("style") ?? StyleStore.defaultID)
} catch {
    fail("\(error)")
}
let values = style.values

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

case "style":
    print("\(style.id) v\(style.version) — \(style.name)")
    print("확정 여부: \(style.measured ? "측정 완료" : "잠정값")")
    if let note = style.measuredNote { print("메모: \(note)") }
    print("근거 프레임: \(style.measuredFrom.joined(separator: ", "))")

case "metrics":
    let m = CaptionLayout.metrics(frameSize: frameSize, style: values)
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

    let font = MadiFont.pretendard(size: m.fontSize, weight: CGFloat(values.caption.weight))
    print("\n문자열별 ink 높이 (크기가 문자열에 따라 흔들리면 기준 문자열을 고쳐야 한다):")
    for s in [CaptionLayout.metricProbe, "가능성이 높다는 겁니다", "어깨가", "골반 틀어졌으면", "하나 둘 셋"] {
        let ink = CaptionLayout.inkBounds(s, font: font)
        print(String(format: "  %-22@  높이 %6.2f  아래끝 %6.2f  폭 %7.2f",
                     s as NSString, ink.height, ink.minY,
                     CaptionLayout.advanceWidth(s, font: font)))
    }

    let sFont = MadiFont.pretendard(
        size: m.secondaryFontSize, weight: CGFloat(values.secondary.weight)
    )
    let sInk = CaptionLayout.inkBounds(CaptionLayout.secondaryMetricProbe, font: sFont)
    print(String(format: "\n보조 라틴 어센더 높이 %.2f px  (원본 실측 16px @1280 = %.2f px @%d)",
                 sInk.height, 16.0 / 1280 * frameSize.height, Int(frameSize.height)))

case "stems":
    // 웨이트를 눈대중으로 고르지 않기 위한 도구.
    // 원본 프레임과 내 렌더를 **같은 코드**로 재서 "세로획 두께 ÷ 글자 높이" 를 비교한다.
    //   madi-spike stems --image reference/yt_15s.png   원본을 잰다
    //   madi-spike stems                                웨이트를 훑는다
    func report(_ label: String, _ scan: StillRenderer.StrokeScan) {
        print(String(format: "%-28@ 글자높이 %5.1f   세로획 %5.2f (%d개)   비율 %.4f",
                     label as NSString, scan.inkHeight, scan.medianStroke,
                     scan.strokeCount, scan.medianStroke / scan.inkHeight))
    }
    if let path = option("image") {
        guard let image = try? StillRenderer.loadImage(URL(fileURLWithPath: path)),
              let scan = StillRenderer.scanStrokes(image)
        else { fail("\(path) 에서 흰 글자를 찾지 못했습니다") }
        report(path, scan)
    } else {
        for w in stride(from: 400.0, through: 900.0, by: 50.0) {
            var probe = values
            probe.caption.weight = w
            guard let image = try? StillRenderer.renderCaption(
                      goldenCaption, size: frameSize, style: probe,
                      backdrop: .solid(RGBA(0, 0, 0, 1))
                  ),
                  let scan = StillRenderer.scanStrokes(image)
            else {
                print(String(format: "wght %4.0f  측정 실패", w))
                continue
            }
            report(String(format: "wght %4.0f", w), scan)
        }
    }

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
            goldenCaption, size: frameSize, style: values, backdrop: backdrop
        )
        try StillRenderer.writePNG(image, to: out)
        print("\(out.path)  \(image.width)x\(image.height)")
    } catch {
        fail("\(error)")
    }

case "probe":
    guard args.count > 1 else { fail("사용법: madi-spike probe <영상>") }
    let url = URL(fileURLWithPath: args[1])
    do {
        let info = try await FrameSheet.info(of: url)
        print("\(url.lastPathComponent)")
        print(String(format: "  %.0fx%.0f  %.2f초  %.2f fps  %@",
                     info.size.width, info.size.height, info.duration, info.fps, info.codec))
    } catch { fail("\(error)") }

case "frames":
    guard args.count > 2 else {
        fail("사용법: madi-spike frames <영상> <출력디렉토리> [--at 1,2,3] [--prefix p]")
    }
    let video = URL(fileURLWithPath: args[1])
    let outDir = URL(fileURLWithPath: args[2])
    let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
    do {
        let written = try await FrameSheet.extract(
            from: video, at: times, into: outDir, prefix: option("prefix") ?? ""
        )
        for url in written { print(url.path) }
    } catch { fail("\(error)") }

case "compare":
    guard args.count > 3 else {
        fail("사용법: madi-spike compare <원본> <렌더> <out.png> [--at 1,2] [--band 0.7,0.85]")
    }
    do {
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let bandParts = (option("band") ?? "0,1").split(separator: ",").compactMap { Double($0) }
        let band = bandParts.count == 2 ? bandParts[0]...bandParts[1] : 0...1
        try await FrameSheet.compareSheet(
            original: URL(fileURLWithPath: args[1]),
            rendered: URL(fileURLWithPath: args[2]),
            at: times.isEmpty ? [1, 4, 7, 11, 15, 18] : times,
            band: band,
            to: URL(fileURLWithPath: args[3])
        )
        print("\(args[3])  (왼쪽 원본 · 오른쪽 렌더)")
    } catch { fail("\(error)") }

case "render":
    guard args.count > 2 else { fail("사용법: madi-spike render <composition.json> <out.mp4>") }
    let compURL = URL(fileURLWithPath: args[1])
    let outURL = URL(fileURLWithPath: args[2])
    do {
        let comp = try parseComposition(Data(contentsOf: compURL))
        print("컴포지션 \(comp.id) · 장면 \(comp.scenes.count)개 · "
              + String(format: "길이 %.2f초", comp.duration))

        // 원본 경로는 컴포지션 파일과 같은 디렉토리 기준으로 찾는다.
        // videoId 를 파일 이름으로 쓴다 — 0단계에는 DB 가 없다.
        let base = compURL.deletingLastPathComponent()
        var sources: [String: URL] = [:]
        for scene in comp.scenes where sources[scene.source.videoID] == nil {
            let id = scene.source.videoID
            let candidates = [
                base.appending(path: "source/\(id).mp4"),
                base.appending(path: "\(id).mp4"),
                URL(fileURLWithPath: id),
            ]
            guard let found = candidates.first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }) else {
                fail("원본 \(id) 을 찾지 못했습니다. 찾아본 곳:\n"
                     + candidates.map { "  - " + $0.path }.joined(separator: "\n"))
            }
            sources[id] = found
        }

        try await Renderer().render(comp, sources: sources, style: values, to: outURL) { p in
            FileHandle.standardError.write(Data("\r만드는 중 \(Int(p * 100))%   ".utf8))
        }
        FileHandle.standardError.write(Data("\r                 \r".utf8))
        print(outURL.path)
    } catch { fail("\(error)") }


default:
    print("""
    madi-spike — 0단계 측정 도구

      font                              등록된 폰트와 가변 축 확인
      style                             지금 쓰는 스타일 값의 출처
      stems [--image <png>]             세로획 두께 ÷ 글자 높이 (웨이트 고르기)
      metrics                           스타일 값에서 역산된 실제 픽셀 치수
      still <out.png> [--backdrop <png>]  자막 한 장
      probe <영상>                       해상도 · 길이 · fps · 코덱
      frames <영상> <디렉토리> [--at 1,2]  비교용 프레임 추출
      render <composition.json> <out.mp4>  영상 한 편
      compare <원본> <렌더> <out.png>     같은 시각을 나란히 (B 판정용)

    공통 옵션: --text --secondary --width --height --style
    """)
}
