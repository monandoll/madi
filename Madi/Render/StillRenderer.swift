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

        let layer = CaptionLayer(caption: caption, frameSize: size)
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
