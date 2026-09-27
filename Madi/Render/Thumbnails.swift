import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 화면에 쓰는 한 장짜리 그림 (ViewData `Thumbnail`, docs/stage-6.spec.md 7번).
///
/// 자리는 **정해져 있다** — 키에서 경로가 바로 나온다. 바꾸는 층은 파일이 있으면 쓰고 없으면 회색 자리표시(디자인 규칙).
/// 캐시다 — 지워져도 다시 만든다 (`~/Library/Caches/madi/thumbs`).
public struct Thumbnails: Sendable {
    public let root: URL

    public init(root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "madi/thumbs", directoryHint: .isDirectory)) {
        self.root = root
    }

    public func video(_ videoID: String) -> URL { root.appending(path: "video-\(videoID).jpg") }
    public func output(_ outputID: String) -> URL { root.appending(path: "output-\(outputID).jpg") }
    public func scene(_ compositionID: String, _ sceneID: String) -> URL { root.appending(path: "scene-\(compositionID)-\(sceneID).jpg") }

    /// 촬영본 — 0.5초 (첫 프레임은 검거나 흔들린 경우가 많다).
    public func makeVideo(_ videoID: String, from source: URL) async throws {
        try await Self.frame(source, at: 0.5, to: video(videoID))
    }

    /// 결과물 — 가운데. 자막이 그려진 내보낸 파일에서 뽑는다.
    public func makeOutput(_ outputID: String, from file: URL) async throws {
        let duration = try await AVURLAsset(url: file).load(.duration).seconds
        try await Self.frame(file, at: max(duration / 2, 0), to: output(outputID))
    }

    /// 장면 카드 — 장면 원본 구간의 첫 0.2초 뒤 (화면 잡기 전 원본 그대로다).
    public func makeScenes(_ comp: Composition, sources: [String: URL]) async throws {
        for scene in comp.scenes {
            guard let src = sources[scene.source.videoID] else { continue }
            let url = self.scene(comp.id, scene.id)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try await Self.frame(src, at: scene.source.start + 0.2, to: url)
        }
    }

    static func frame(_ source: URL, at seconds: Double, to out: URL) async throws {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 540, height: 540)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let image = try await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
