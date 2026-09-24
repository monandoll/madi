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

        let layer = CaptionLayer(caption: caption, frameSize: size, style: style)
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
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return px[i] > 230 && px[i + 1] > 230 && px[i + 2] > 230
        }

        // 자막은 화면 아래쪽 = 버퍼의 마지막 40% 행. 가장 아래 흰 글자 줄을 본문으로 본다.
        let minPx = max(8, w * 12 / 1000)
        let maxPx = w * 6 / 10
        var rows: [Int] = []
        for y in (h * 6 / 10)..<h {
            var n = 0
            for x in 0..<w where isWhite(x, y) { n += 1 }
            if n >= minPx && n <= maxPx { rows.append(y) }
        }
        guard !rows.isEmpty else { return nil }
        // 끊긴 구간이 있으면 가장 위 묶음(=본문. 버퍼에서는 가장 작은 y)을 쓴다.
        var band = [rows[0]]
        for y in rows.dropFirst() {
            if y - band[band.count - 1] <= 2 { band.append(y) } else { break }
        }
        let lo = band[0], hi = band[band.count - 1]
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
