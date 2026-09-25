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

/// 자막 위치 슬롯. 기본은 앉아서 말하는 상반신 (공개본 A 무리).
let slot = CaptionSlot(rawValue: option("slot") ?? "upperBody") ?? .upperBody

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
    let m = CaptionLayout.metrics(frameSize: frameSize, style: values, slot: slot)
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
                      goldenCaption, size: frameSize, style: probe, slot: slot,
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
            goldenCaption, size: frameSize, style: values, slot: slot, backdrop: backdrop
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

case "followtest":
    // "매 프레임 가장 큰 덩어리" vs "직전 것과 가장 많이 겹치는 덩어리(IoU)".
    // 배율이 0.5초마다 얼마나 튀는지 비교한다.
    guard args.count > 1 else { fail("사용법: madi-spike followtest <영상> [--step 0.5] [--until 30]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let step = Double(option("step") ?? "") ?? 0.5
        let target = Double(option("target") ?? "") ?? 0.72
        let info = try await FrameSheet.info(of: video)
        let until = min(Double(option("until") ?? "") ?? info.duration, info.duration - 0.05)
        let times = stride(from: 0.0, to: until, by: step).map { $0 }
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: URL(fileURLWithPath: "out/follow")
                .appending(path: video.deletingPathExtension().lastPathComponent), prefix: ""
        )
        var biggest: [Double] = [], followed: [Double] = []
        var previous: NormRect?
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            let parts = try SubjectDetector.maskComponents(image)
            guard !parts.isEmpty else { continue }
            let big = parts.max { $0.coverage < $1.coverage }!
            let kept = SubjectDetector.follow(parts, previous: previous)!
            previous = kept.box
            biggest.append(target / max(big.box.h, 0.001))
            followed.append(target / max(kept.box.h, 0.001))
        }
        func report(_ name: String, _ v: [Double]) {
            guard v.count > 1 else { print("  \(name) 샘플 부족"); return }
            var steps: [Double] = []
            for i in 1..<v.count { steps.append(abs(v[i] - v[i - 1])) }
            let sorted = steps.sorted()
            let big = steps.filter { $0 > 0.25 }.count
            print(String(format: "  %@  샘플간 배율변동  중앙 %.3f  최대 %.3f  0.25 초과 %d/%d",
                         name as NSString, sorted[sorted.count / 2], sorted[sorted.count - 1],
                         big, steps.count))
        }
        print("  \(frames.count)샘플 중 덩어리 있음 \(biggest.count)")
        report("가장 큰 것   ", biggest)
        report("IoU 로 이어서", followed)
    } catch { fail("\(error)") }

case "zoomtest":
    // 확대 상한 근거. 소스 크롭 폭이 출력 폭보다 작아지면 그때부터 업스케일이다.
    guard args.count > 1 else { fail("사용법: madi-spike zoomtest <영상> [--at 5]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let at = Double(option("at") ?? "") ?? 5
        let info = try await FrameSheet.info(of: video)
        let frames = try await FrameSheet.extract(
            from: video, at: [at], into: URL(fileURLWithPath: "out/zoomtest"), prefix: "src_"
        )
        let source = try StillRenderer.loadImage(frames[0])
        let out = CGSize(width: 1080, height: 1920)
        // 출력과 같은 9:16 을 원본에서 잘라낼 때의 배율 1 크롭 폭(소스 픽셀).
        let baseWidthPx = min(info.size.width, info.size.height * 9 / 16)
        print(String(format: "  원본 %.0fx%.0f · 배율 1 크롭 폭 %.0fpx · 출력 폭 %.0fpx",
                     info.size.width, info.size.height, baseWidthPx, out.width))
        // 대조군: 소스를 반으로 줄인 것. 같은 화각을 두 해상도로 뽑아 비교하면
        // "배율을 올려서 흐려진 것" 과 "해상도가 모자라서 흐려진 것" 이 분리된다.
        let halfSource = try StillRenderer.crop(
            source, rect: NormRect(x: 0, y: 0, w: 1, h: 1),
            to: CGSize(width: info.size.width / 2, height: info.size.height / 2)
        )
        print("  배율   크롭폭(px)  업스케일   선명도   반해상도   손실   비고")
        for zoom in [1.0, 1.5, 2.0, 2.25, 2.5, 3.0] {
            let cropPx = baseWidthPx / zoom
            let wNorm = cropPx / info.size.width
            let hNorm = (cropPx * 16 / 9) / info.size.height
            guard wNorm <= 1, hNorm <= 1 else { continue }
            let rect = NormRect(x: (1 - wNorm) / 2, y: (1 - hNorm) / 2, w: wNorm, h: hNorm)
            let image = try StillRenderer.crop(source, rect: rect, to: out)
            try StillRenderer.writePNG(image, to: URL(fileURLWithPath:
                String(format: "out/zoomtest/zoom_%.2f.png", zoom)))
            let upscale = out.width / cropPx
            let full = StillRenderer.sharpness(image)
            let half = StillRenderer.sharpness(
                try StillRenderer.crop(halfSource, rect: rect, to: out)
            )
            print(String(format: "  %.2f   %8.0f   %7.2f   %6.2f   %7.2f   %5.0f%%   %@",
                         zoom, cropPx, upscale, full, half,
                         full > 0 ? (1 - half / full) * 100 : 0,
                         upscale > 1 ? "업스케일" : "원본 픽셀로 충분"))
        }
    } catch { fail("\(error)") }

case "track":
    // 0.5초 간격 피사체 추적 (AGENTS.md §6). 1단계 설계를 위한 실측.
    guard args.count > 1 else { fail("사용법: madi-spike track <영상> [--step 0.5] [--target 0.72]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let step = Double(option("step") ?? "") ?? 0.5
        let target = Double(option("target") ?? "") ?? 0.72
        let info = try await FrameSheet.info(of: video)
        // 대용 원본은 150초라 전구간을 0.5초로 훑으면 너무 오래 걸린다. 앞쪽 구간만 본다.
        let until = min(Double(option("until") ?? "") ?? info.duration, info.duration - 0.05)
        let times = stride(from: 0.0, to: until, by: step).map { $0 }
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: URL(fileURLWithPath: "out/track")
                .appending(path: video.deletingPathExtension().lastPathComponent), prefix: ""
        )
        print(String(format: "  %.0fx%.0f  %.2f초  %d샘플 (%.1f초 간격)",
                     info.size.width, info.size.height, info.duration, frames.count, step))
        print("   시각   사람높이  필요배율  가로중심  세로중심   점유   덩어리")
        var heights: [Double] = [], cxs: [Double] = [], cys: [Double] = []
        var missing = 0
        for (i, url) in frames.enumerated() {
            let image = try StillRenderer.loadImage(url)
            guard let st = try SubjectDetector.maskStats(image) else {
                missing += 1
                print(String(format: "  %5.1f   — 마스크 없음", times[i]))
                continue
            }
            let parts = try SubjectDetector.maskComponents(image)
            heights.append(st.box.h); cxs.append(st.massCenterX); cys.append(st.massCenterY)
            print(String(format: "  %5.1f    %6.3f    %6.2f    %6.3f    %6.3f  %6.3f   %2d",
                         times[i], st.box.h, target / max(st.box.h, 0.001),
                         st.massCenterX, st.massCenterY, st.coverage, parts.count))
        }
        func stats(_ v: [Double], _ name: String) {
            guard !v.isEmpty else { return }
            let sorted = v.sorted()
            let med = sorted[sorted.count / 2]
            var maxStep = 0.0
            for i in 1..<v.count { maxStep = max(maxStep, abs(v[i] - v[i - 1])) }
            print(String(format: "  %@  최소 %.3f  중앙 %.3f  최대 %.3f  샘플간 최대이동 %.3f",
                         name as NSString, sorted[0], med, sorted[sorted.count - 1], maxStep))
        }
        print("")
        print("  마스크 없음 \(missing)/\(frames.count)")
        stats(heights, "사람높이")
        stats(cxs, "가로중심")
        stats(cys, "세로중심")
    } catch { fail("\(error)") }

case "croptest":
    // 가로로 넓은 자세에서 "크롭 중심을 무엇으로 잡나" 를 후보별로 잰다.
    // 점수 = 크롭 안에 남는 마스크 비율. 높을수록 몸이 덜 잘린다.
    guard args.count > 1 else { fail("사용법: madi-spike croptest <영상> [--at 1,2]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let info = try await FrameSheet.info(of: video)
        let cropW = min(1.0, (info.size.height * 9 / 16) / info.size.width)
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: URL(fileURLWithPath: "out/croptest")
                .appending(path: video.deletingPathExtension().lastPathComponent), prefix: ""
        )
        func retained(_ stats: SubjectDetector.MaskStats, centerX: Double) -> Double {
            let half = cropW / 2
            let lo = min(max(centerX - half, 0), 1 - cropW)
            let hi = lo + cropW
            let bins = stats.columnMass.count
            var kept = 0.0
            for i in 0..<bins {
                let x = (Double(i) + 0.5) / Double(bins)
                if x >= lo && x < hi { kept += stats.columnMass[i] }
            }
            return kept
        }
        var sums = [0.0, 0.0, 0.0]
        var n = 0
        print(String(format: "  9:16 가용 폭 %.4f", cropW))
        print("  프레임        상자중심  무게중심  화면중앙")
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            guard let stats = try SubjectDetector.maskStats(image) else { continue }
            let scores = [
                retained(stats, centerX: stats.box.x + stats.box.w / 2),
                retained(stats, centerX: stats.massCenterX),
                retained(stats, centerX: 0.5),
            ]
            for (i, v) in scores.enumerated() { sums[i] += v }
            n += 1
            print(String(format: "  %-12@  %6.3f    %6.3f    %6.3f",
                         url.deletingPathExtension().lastPathComponent as NSString,
                         scores[0], scores[1], scores[2]))
        }
        guard n > 0 else { fail("마스크를 못 찾았습니다") }
        print(String(format: "  %-12@  %6.3f    %6.3f    %6.3f", "평균" as NSString,
                     sums[0] / Double(n), sums[1] / Double(n), sums[2] / Double(n)))
    } catch { fail("\(error)") }

case "subjects":
    // 1단계 준비. 마스크를 덩어리로 쪼개 "누가 피사체인가" 와 "가로로 다 들어가나" 를 잰다.
    guard args.count > 1 else { fail("사용법: madi-spike subjects <영상> [--at 1,2]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let info = try await FrameSheet.info(of: video)
        // 9:16 로 뽑을 때 쓸 수 있는 가로 폭 (전체 높이를 쓰는 경우).
        let cropWidth = min(1.0, (info.size.height * 9 / 16) / info.size.width)
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: URL(fileURLWithPath: "out/subjects")
                .appending(path: video.deletingPathExtension().lastPathComponent), prefix: ""
        )
        print(String(format: "  9:16 크롭 가용 폭 %.4f", cropWidth))
        print("  프레임        덩어리  1등 폭   1등 높이  1등 점유  2등 점유  폭 초과")
        var over = 0, multi = 0, n = 0
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            let parts = try SubjectDetector.maskComponents(image)
            n += 1
            guard let first = parts.first else {
                print("  \(url.deletingPathExtension().lastPathComponent)      없음")
                continue
            }
            if parts.count > 1 { multi += 1 }
            let tooWide = first.box.w > cropWidth
            if tooWide { over += 1 }
            print(String(format: "  %-12@ %5d  %6.3f   %6.3f   %6.3f   %6.3f   %@",
                         url.deletingPathExtension().lastPathComponent as NSString,
                         parts.count, first.box.w, first.box.h, first.coverage,
                         parts.count > 1 ? parts[1].coverage : 0,
                         tooWide ? "  ✗ 안 들어감" : ""))
        }
        print("")
        print("  덩어리 2개 이상 \(multi)/\(n) · 1등이 9:16 폭을 넘는 프레임 \(over)/\(n)")
    } catch { fail("\(error)") }

case "captionband":
    // 자막 위치 가설 검증 (1단계 첫 작업).
    // 후보 위치마다 "그 높이에서 사람이 가로로 얼마나 차지하나" 를 잰다.
    guard args.count > 1 else { fail("사용법: madi-spike captionband <영상> [--at 1,2]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: URL(fileURLWithPath: "out/band")
                .appending(path: video.deletingPathExtension().lastPathComponent), prefix: ""
        )
        // 실측된 세 무리. 자막 글자 높이(0.0359)만큼의 띠로 본다.
        let candidates: [(name: String, bottom: Double)] =
            [("A 0.235", 0.235), ("B 0.300", 0.300), ("C 0.475", 0.475)]
        let bands = candidates.map { (bottom: $0.bottom, height: 0.0359) }
        var sums = [Double](repeating: 0, count: candidates.count)
        var n = 0
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            let cov = try SubjectDetector.maskBandCoverage(image, bands: bands)
            for (i, c) in cov.enumerated() { sums[i] += c }
            n += 1
        }
        guard n > 0 else { fail("프레임이 없습니다") }
        let avg = sums.map { $0 / Double(n) }
        print("  " + zip(candidates, avg).map {
            String(format: "%@ %.3f", $0.0.name, $0.1) }.joined(separator: "   "))
    } catch { fail("\(error)") }

case "detect":
    // 사람 감지 후보를 나란히 재 본다. 고르는 게 아니라 재기만 한다 (G1·G2 정의 준비).
    guard args.count > 1 else { fail("사용법: madi-spike detect <영상> [--at 1,2] [--out 디렉토리]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let work = URL(fileURLWithPath: option("out") ?? "out/detect")
            .appending(path: video.deletingPathExtension().lastPathComponent)
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: work.appending(path: "raw"), prefix: ""
        )
        print("  프레임        관절상자  분할상자  분할비율  사람상자  상반신  손  주목도"
              + (option("box") != nil ? "   |  분할 상자 x y w h" : ""))
        var tally = [0, 0, 0, 0, 0, 0]
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            let s = try SubjectDetector.scan(image)
            func f(_ r: NormRect?) -> String { r.map { String(format: "%7.3f", $0.h) } ?? "      ·" }
            if s.jointBox != nil { tally[0] += 1 }
            if s.segmentBox != nil { tally[1] += 1 }
            if s.personBox != nil { tally[2] += 1 }
            if s.upperBodyBox != nil { tally[3] += 1 }
            if s.handCount > 0 { tally[4] += 1 }
            if s.salientBox != nil { tally[5] += 1 }
            var line = String(format: "  %-12@ %@ %@ %8.3f %@ %@ %3d %@",
                              url.deletingPathExtension().lastPathComponent as NSString,
                              f(s.jointBox), f(s.segmentBox), s.segmentCoverage,
                              f(s.personBox), f(s.upperBodyBox), s.handCount, f(s.salientBox))
            // 리프레임 좌표를 **손으로** 적기 위한 숫자. 크롭을 자동으로 계산해 주지 않는다 —
            // 자동 리프레이밍은 1단계다 (docs/stage-0.spec.md 범위 밖).
            if option("box") != nil, let b = s.segmentBox {
                line += String(format: "   |  %.4f %.4f %.4f %.4f  (가로중심 %.4f)",
                               b.x, b.y, b.w, b.h, b.x + b.w / 2)
            }
            print(line)
        }
        let names = ["관절", "분할", "사람상자", "상반신", "손", "주목도"]
        print("")
        print("  " + zip(names, tally).map { "\($0.0) \($0.1)/\(frames.count)" }
                .joined(separator: " · "))
    } catch { fail("\(error)") }

case "pose":
    // 1단계 준비. **감지 정확도만** 본다 — 리프레이밍은 아직 만들지 않는다.
    guard args.count > 2 else { fail("사용법: madi-spike pose <영상> <출력디렉토리> [--at 1,2] [--conf 0.3]") }
    do {
        let video = URL(fileURLWithPath: args[1])
        let outDir = URL(fileURLWithPath: args[2])
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let frames = try await FrameSheet.extract(
            from: video, at: times, into: outDir.appending(path: "raw"), prefix: ""
        )
        let provider = VisionPoseProvider(
            minJointConfidence: Float(option("conf") ?? "") ?? 0.3,
            includePersonBox: true
        )
        var detected = 0, withHead = 0, withAnkles = 0
        var heights: [Double] = []
        print("  프레임                 사람  관절  신뢰도  점유높이  머리  발목")
        for url in frames {
            let image = try StillRenderer.loadImage(url)
            let observations = try provider.detect(in: image)
            let name = url.deletingPathExtension().lastPathComponent
            guard let best = observations.max(by: { $0.jointBox.h < $1.jointBox.h }) else {
                print("  \(name.padding(toLength: 22, withPad: " ", startingAt: 0))  없음")
                continue
            }
            detected += 1
            if best.hasHead { withHead += 1 }
            if best.hasAnkles { withAnkles += 1 }
            heights.append(best.jointBox.h)
            print(String(format: "  %-22@ %4d %5d  %6.2f  %7.3f  %@  %@",
                         name as NSString, observations.count, best.joints.count,
                         best.confidence, best.jointBox.h,
                         best.hasHead ? "  O " : "  X ", best.hasAnkles ? " O" : " X"))
            let annotated = try PoseOverlay.draw(observations, on: image)
            try StillRenderer.writePNG(annotated, to: outDir.appending(path: "\(name).png"))
        }
        let sorted = heights.sorted()
        print("")
        print("  프레임 \(frames.count)장 중 감지 \(detected)장 · 머리 \(withHead)장 · 발목 \(withAnkles)장")
        if !sorted.isEmpty {
            print(String(format: "  관절 상자 높이  중앙값 %.3f  최소 %.3f  최대 %.3f  (품질 게이트 G1 하한 0.55)",
                         sorted[sorted.count / 2], sorted[0], sorted[sorted.count - 1]))
        }
        print("  겹쳐 그린 프레임: \(outDir.path)")
    } catch { fail("\(error)") }

case "sheet":
    guard args.count > 2 else { fail("사용법: madi-spike sheet <영상> <out.png> [--at ...] [--cols 5]") }
    do {
        let times = (option("at") ?? "").split(separator: ",").compactMap { Double($0) }
        let used = try await FrameSheet.grid(
            from: URL(fileURLWithPath: args[1]),
            at: times,
            columns: Int(option("cols") ?? "") ?? 5,
            to: URL(fileURLWithPath: args[2])
        )
        print("\(args[2])  " + used.map { String(format: "%.1fs", $0) }.joined(separator: " "))
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
            // 아이폰 촬영본은 .mov 다. 확장자를 하나만 보면 못 찾는다.
            let candidates = ["mp4", "mov", "MOV", "m4v"].flatMap { ext in
                [base.appending(path: "source/\(id).\(ext)"),
                 base.appending(path: "source/raw/\(id).\(ext)"),
                 base.appending(path: "\(id).\(ext)")]
            } + [URL(fileURLWithPath: id)]
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
      sheet <영상> <out.png> [--cols 5]   한 편을 격자로 훑어본다
      pose <영상> <디렉토리> [--conf 0.3]  사람 감지 정확도 (1단계 준비)
      detect <영상> [--at 1,2]           감지 방법 여러 개를 나란히 (G1·G2 정의 준비)
      captionband <영상> [--at 1,2]      자막 후보 위치별 피사체 밀도
      subjects <영상> [--at 1,2]         마스크 덩어리 · 9:16 폭 초과 (1단계 준비)
      croptest <영상> [--at 1,2]         크롭 중심 후보별 "몸이 얼마나 남나"
      track <영상> [--step 0.5] [--until 30]  0.5초 간격 피사체 추적 (1단계 설계용)
      zoomtest <영상> [--at 5]           배율별 업스케일·선명도 (확대 상한 근거)
      followtest <영상>                  덩어리 추적: 가장 큰 것 vs IoU 이어가기

    공통 옵션: --text --secondary --width --height --style --slot
    """)
}
