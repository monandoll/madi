import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import QuartzCore

/// 프레임 한 장만 PNG 로. 측정·대조용 (`docs/stage-0.spec.md` 산출물).
///
/// 영상을 렌더하기 전에 **정지 화면 한 장**부터 맞춘다. 여기서 다르면 영상 전체가 다르다
/// (docs/style-authoring.md §3). 이 단계를 건너뛰고 렌더부터 돌리지 않는다.
public enum StillRenderer {

    public enum Failure: Error, CustomStringConvertible {
        case contextCreationFailed
        case imageReadFailed(URL)
        case imageWriteFailed(URL)

        public var description: String {
            switch self {
            case .contextCreationFailed: "비트맵 컨텍스트를 만들지 못했습니다"
            case .imageReadFailed(let url): "이미지를 읽지 못했습니다: \(url.lastPathComponent)"
            case .imageWriteFailed(let url): "이미지를 쓰지 못했습니다: \(url.lastPathComponent)"
            }
        }
    }

    /// 배경. 원본 프레임 위에 겹쳐 봐야 크기·위치가 어긋난 게 한눈에 보인다.
    public enum Backdrop {
        /// 단색. 측정용 — 흰 글자와 섞이지 않는 어두운 회색.
        case solid(RGBA)
        /// `reference/` 프레임.
        case image(URL)
    }

    /// 자막 한 덩어리를 레이어로 그려 이미지로 낸다.
    ///
    /// **최종 렌더와 같은 `CaptionLayer` 를 쓴다.** 프리뷰·스틸·영상이 다른 코드로 그리면
    /// 여기서 맞춘 숫자가 영상에서 의미가 없어진다 (AGENTS.md §7).
    public static func renderCaption(
        _ caption: Caption,
        size: CGSize,
        style: StyleValues,
        slot: CaptionSlot,
        backdrop: Backdrop = .solid(RGBA(0.13, 0.13, 0.15, 1))
    ) throws -> CGImage {
        let ctx = try makeContext(size: size)

        switch backdrop {
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        case .image(let url):
            let image = try loadImage(url)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        }

        let layer = CaptionLayer(caption: caption, frameSize: size, style: style, slot: slot)
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        layer.render(in: ctx)

        guard let image = ctx.makeImage() else { throw Failure.contextCreationFailed }
        return image
    }

    public static func makeContext(size: CGSize) throws -> CGContext {
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Failure.contextCreationFailed }
        // 자막 치수를 픽셀로 재기 때문에 스케일을 곱하지 않는다.
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(false)  // 서브픽셀 렌더링은 측정값을 흔든다
        return ctx
    }

    public static func loadImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw Failure.imageReadFailed(url) }
        return image
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw Failure.imageWriteFailed(url) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.imageWriteFailed(url) }
    }
}

// MARK: - 선명도

extension StillRenderer {
    /// 평균 |라플라시안|. 확대하면 떨어진다 — 확대 상한을 정하는 근거로 쓴다.
    ///
    /// 절대값에는 의미가 없다(내용에 따라 다르다). **같은 프레임 · 같은 화각**을
    /// 소스 해상도만 바꿔 비교할 때만 뜻이 있다.
    public static func sharpness(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        guard w > 2, h > 2, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return 0 }
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func luma(_ x: Int, _ y: Int) -> Double {
            let i = (y * w + x) * 4
            return 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
        }
        var sum = 0.0
        var n = 0
        for y in stride(from: 1, to: h - 1, by: 2) {
            for x in stride(from: 1, to: w - 1, by: 2) {
                let value = 4 * luma(x, y) - luma(x - 1, y) - luma(x + 1, y)
                    - luma(x, y - 1) - luma(x, y + 1)
                sum += abs(value)
                n += 1
            }
        }
        return n > 0 ? sum / Double(n) : 0
    }

    /// 원본의 한 영역을 출력 크기로 뽑는다. 확대 화질을 재는 데 쓴다.
    public static func crop(
        _ image: CGImage, rect: NormRect, to size: CGSize
    ) throws -> CGImage {
        let px = CGRect(
            x: rect.x * Double(image.width),
            // CGImage.cropping 은 위가 0 인 좌표를 쓴다. NormRect 는 y 가 위로 간다.
            y: (1 - rect.y - rect.h) * Double(image.height),
            width: rect.w * Double(image.width),
            height: rect.h * Double(image.height)
        )
        guard let piece = image.cropping(to: px) else { throw Failure.contextCreationFailed }
        let ctx = try makeContext(size: size)
        ctx.interpolationQuality = .high
        ctx.draw(piece, in: CGRect(origin: .zero, size: size))
        guard let out = ctx.makeImage() else { throw Failure.contextCreationFailed }
        return out
    }
}

// MARK: - 픽셀 측정

extension StillRenderer {
    /// 그려진 글자의 높이와 세로획 두께를 **픽셀에서** 잰다.
    ///
    /// 웨이트를 눈대중으로 고르지 않기 위한 도구다 (docs/style-authoring.md §2).
    ///
    /// ★ 획 두께는 **루마 50% 교차점**으로 잰다. "흰 픽셀 개수" 로 세면 안 된다 —
    ///   원본 프레임은 유튜브 재인코딩본이라 검은 외곽선이 흰 획으로 번져서
    ///   임계값(>230) 기준 흰 폭이 실제보다 1px 넘게 얇게 나온다. 같은 자막을 crisp 하게
    ///   그린 내 렌더와 비교하면 내 쪽이 항상 굵어 보이고, 그대로 믿으면 웨이트를
    ///   두 단계 낮추게 된다. 실제로 그럴 뻔했다.
    ///   50% 교차는 번짐이 대칭이면 원래 경계를 그대로 준다.
    public struct StrokeScan: Sendable {
        /// 흰 글자 밴드의 높이(px).
        public let inkHeight: CGFloat
        /// 흰 글자 밴드의 **아래끝**에서 화면 아래까지 ÷ 프레임 높이.
        /// `tools/measure.mjs` 의 "하단여백" 과 같은 정의다.
        public let inkBottomRatio: CGFloat
        /// 흰 글자 밴드의 높이 ÷ 프레임 높이. `measure.mjs` 의 "본문높이".
        public let inkHeightRatio: CGFloat
        /// 세로획 두께의 중앙값(px, 소수점 포함).
        public let medianStroke: CGFloat
        /// 잰 세로획 개수.
        public let strokeCount: Int
    }

    /// - Parameter darkBackground: 배경이 글자보다 어두운가. 자막 영역을 찾는 데 쓴다.
    public static func scanStrokes(_ image: CGImage) -> StrokeScan? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // ★ 비트맵 버퍼의 행 0 은 이미지 **위쪽**이다 (CG 좌표의 y=0 은 아래쪽인 것과 반대).
        func luma(_ x: Int, _ y: Int) -> CGFloat {
            let i = (y * w + x) * 4
            return 0.299 * CGFloat(px[i]) + 0.587 * CGFloat(px[i + 1]) + 0.114 * CGFloat(px[i + 2])
        }
        /// 자막 글자 픽셀 — **흰색이면서 검은 외곽선에 둘러싸인** 픽셀.
        ///
        /// ★ "흰색" 만으로는 안 된다. 흰 벽 · 흰 양말 · 밝은 피부를 자막으로 잡는다.
        ///   자막에만 있는 성질은 검은 외곽선이고, 글자 획은 얇아서 획 안의 어느 픽셀에서든
        ///   가까운 거리 안에 검정이 **양쪽으로** 있다 (세로획이면 좌우, 가로획이면 위아래).
        ///   흰 벽은 어느 방향으로도 검정이 없고, 흰 양말은 가운데가 D 보다 두꺼워 통과 못 한다.
        ///   `tools/measure.mjs` 의 `makeGlyphTest` 와 **같은 정의**다 — 둘이 다르면 의미가 없다.
        let glyphRadius = max(6, Int((Double(h) * 0.012).rounded()))
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return px[i] > 230 && px[i + 1] > 230 && px[i + 2] > 230
        }
        func isDark(_ x: Int, _ y: Int) -> Bool { luma(x, y) < 70 }
        func isGlyph(_ x: Int, _ y: Int) -> Bool {
            guard isWhite(x, y) else { return false }
            var left = false, right = false, up = false, down = false
            for k in 1...glyphRadius {
                if !left, x - k >= 0, isDark(x - k, y) { left = true }
                if !right, x + k < w, isDark(x + k, y) { right = true }
                if !up, y - k >= 0, isDark(x, y - k) { up = true }
                if !down, y + k < h, isDark(x, y + k) { down = true }
                if (left && right) || (up && down) { return true }
            }
            return false
        }

        // 자막은 화면 아래쪽이지만 **아래 끝에 붙어 있다고 가정하지 않는다**.
        // 편마다 아래끝 비율이 0.235 ~ 0.37 로 갈린다 (`measure.mjs` 와 같은 창).
        let minPx = max(8, Int((Double(w) * 0.012).rounded()))
        let maxPx = w * 6 / 10
        var rows: [Int] = []
        for y in (h * 35 / 100)..<h {
            var n = 0
            for x in 0..<w where isGlyph(x, y) { n += 1 }
            if n >= minPx && n <= maxPx { rows.append(y) }
        }
        guard !rows.isEmpty else { return nil }

        // 이어지는 행들을 묶고, 너무 얇은 묶음은 버린다 (`tools/measure.mjs` 의 bands 와 같은 규칙).
        // 최소 높이를 두지 않으면 배경의 한두 행짜리 밝은 픽셀이 묶음 행세를 한다.
        var bands: [(lo: Int, hi: Int)] = []
        var start = rows[0], previous = rows[0]
        for y in rows.dropFirst() {
            if y - previous > 2 {
                if previous - start + 1 >= 6 { bands.append((start, previous)) }
                start = y
            }
            previous = y
        }
        if previous - start + 1 >= 6 { bands.append((start, previous)) }

        // ★ 본문 자막은 화면에서 **가장 아래** 흰 글자 줄이다 (measure.mjs 와 같은 규칙).
        //   위쪽 묶음을 쓰면 벽·옷 같은 밝은 배경을 자막으로 착각한다 — 실제로 착각했다.
        //   버퍼는 행 0 이 이미지 위쪽이므로 마지막 묶음이 화면 아래다.
        // ★ "가장 아래 묶음" 으로는 부족하다. 자막 **아래쪽**에도 밝은 것이 있다
        //   (흰 양말 · 벤치 하이라이트). 실제로 그걸 자막으로 잡았다.
        //   글자 줄은 두껍고 배경 얼룩은 얇으므로, **가장 두꺼운 묶음 급**만 남기고
        //   그중 가장 아래를 쓴다. 2줄 자막이면 두 줄 다 남고 마지막 줄이 뽑힌다
        //   — `inkBottomRatio` 가 마지막 줄 기준이므로 그게 맞다.
        guard let tallest = bands.map({ $0.hi - $0.lo }).max(), tallest > 0 else { return nil }
        let textBands = bands.filter { Double($0.hi - $0.lo) >= Double(tallest) * 0.6 }
        if ProcessInfo.processInfo.environment["MADI_SCAN_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "  [scan] 흰 행 \(rows.count)개, 밴드 \(bands) → 글자 줄 \(textBands)\n".utf8))
        }
        guard let band = textBands.last else { return nil }
        let lo = band.lo, hi = band.hi
        guard hi > lo else { return nil }

        // 글자 중간 높이 스캔라인에서 루마 50% 교차로 획 폭을 잰다.
        let midY = (lo + hi) / 2
        let threshold: CGFloat = 128
        var widths: [CGFloat] = []
        var enter: CGFloat?
        for x in 1..<w {
            let a = luma(x - 1, midY), b = luma(x, midY)
            if a < threshold, b >= threshold {
                enter = CGFloat(x - 1) + (threshold - a) / max(b - a, 0.001)
            } else if a >= threshold, b < threshold, let start = enter {
                let end = CGFloat(x - 1) + (a - threshold) / max(a - b, 0.001)
                let width = end - start
                // 가로획은 훨씬 길다. 글자 높이의 절반을 넘으면 세로획이 아니다.
                if width > 0, width < CGFloat(hi - lo) / 2 { widths.append(width) }
                enter = nil
            }
        }
        if ProcessInfo.processInfo.environment["MADI_SCAN_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "  [scan] 밴드 \(lo)..\(hi), midY \(midY), 획 \(widths.count)개\n".utf8))
        }
        guard !widths.isEmpty else { return nil }
        let sorted = widths.sorted()
        // 버퍼 행 hi 가 이미지에서 가장 아래 = 화면에서 가장 아래.
        return StrokeScan(
            inkHeight: CGFloat(hi - lo + 1),
            inkBottomRatio: CGFloat(h - hi - 1) / CGFloat(h),
            inkHeightRatio: CGFloat(hi - lo + 1) / CGFloat(h),
            medianStroke: sorted[sorted.count / 2],
            strokeCount: sorted.count
        )
    }
}
