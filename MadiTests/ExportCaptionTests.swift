import Testing
import Foundation
import AVFoundation
import CoreGraphics
@testable import MadiKit

/// **내보낸 영상에 자막이 실제로 그려져 있는가.**
///
/// 한동안 안 그려졌다. 0단계 비교는 원본(공개본)에 크리에이터 자막이 이미 박혀 있어서
/// 우리 자막이 없는데도 "자릿수까지 같다" 로 통과했다 (`docs/findings/2026-09-27-stage2-export.md`).
/// 자막 없는 단색 원본에 그려서, 흰 글자 픽셀이 **내보낸 파일에** 있는지 본다.
struct ExportCaptionTests {

    private func whitePixels(_ image: CGImage) -> Int {
        let W = image.width, H = image.height
        var buf = [UInt8](repeating: 0, count: W * H * 4)
        let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        var n = 0
        for i in stride(from: 0, to: buf.count, by: 4) where min(buf[i], buf[i + 1], buf[i + 2]) > 215 { n += 1 }
        return n
    }

    private func frame(_ url: URL, at t: Double) async throws -> CGImage {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        return try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    @Test("자막이 내보낸 파일에 제 시각에만 그려진다 — 전에도 뒤에도 없다")
    func captionIsBurnedIntoExport() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let size = CGSize(width: 360, height: 640)
        let source = dir.appending(path: "grey.mp4")
        try await TestVideo.makeSolid(at: source, seconds: 2, size: size)

        let comp = Composition(
            id: "export", videoID: "grey", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            size: Composition.Size(w: 360, h: 640), fps: 30,
            meta: Composition.Meta(title: "자막", targetDurationSec: 2),
            captionSlot: .upperBody,
            scenes: [Scene(
                id: "s1", role: .hook,
                source: Scene.Source(videoID: "grey", start: 0, end: 1.9),
                captions: [Caption(id: "c", start: 0.2, end: 1.0, text: "양쪽 다리를")]
            )]
        )
        let out = dir.appending(path: "out.mp4")
        let values = try StyleStore.load(StyleStore.defaultID).values
        try await Renderer().render(comp, sources: ["grey": source], style: values, to: out)

        // 시작 전에도 없어야 한다. 사라지기 애니메이션의 채움이 시작 전까지 번지면
        // 모든 자막이 0초부터 자기 끝 시각까지 겹쳐 떠 있게 된다 (실제로 그랬다).
        let before = whitePixels(try await frame(out, at: 0.05))
        let during = whitePixels(try await frame(out, at: 0.6))
        let after = whitePixels(try await frame(out, at: 1.5))
        #expect(before < 20, "자막이 시작하기 전 0.05초에 흰 픽셀이 \(before)개 있다")
        #expect(during > 200, "자막이 떠 있어야 할 0.6초에 흰 글자 픽셀이 \(during)개뿐이다")
        #expect(after < 20, "자막이 끝난 1.5초에 흰 픽셀이 \(after)개 남아 있다")
    }
}
