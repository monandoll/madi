import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 영상에서 특정 시각의 프레임을 뽑는다.
///
/// **렌더 관련 변경은 프레임을 뽑아 눈으로 확인하고 커밋에 남긴다** (AGENTS.md §14).
/// 측정 숫자만 보고 통과라고 하지 않는다.
public enum FrameSheet {

    public enum Failure: Error, CustomStringConvertible {
        case noVideoTrack(URL)
        public var description: String {
            switch self {
            case .noVideoTrack(let url): "\(url.lastPathComponent) 에 비디오 트랙이 없습니다"
            }
        }
    }

    public struct Info: Sendable {
        public let size: CGSize
        public let duration: Double
        public let fps: Float
        public let codec: String
    }

    public static func info(of url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack(url)
        }
        let (natural, transform, fps) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate
        )
        let display = natural.applying(transform)
        let formats = try await track.load(.formatDescriptions)
        let codec = formats.first.map {
            let raw = CMFormatDescriptionGetMediaSubType($0)
            return String(bytes: [
                UInt8((raw >> 24) & 0xFF), UInt8((raw >> 16) & 0xFF),
                UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF),
            ], encoding: .ascii) ?? "?"
        } ?? "?"
        return Info(
            size: CGSize(width: abs(display.width), height: abs(display.height)),
            duration: try await asset.load(.duration).seconds,
            fps: fps,
            codec: codec
        )
    }

    /// 주어진 시각들의 프레임을 PNG 로 뽑는다.
    ///
    /// - Parameter times: 초. 비어 있으면 길이의 5/20/35/50/65/85% 지점을 쓴다
    ///   (`docs/findings/2026-09-23-layout-survey.md` 와 같은 간격).
    @discardableResult
    public static func extract(
        from url: URL, at times: [Double], into directory: URL, prefix: String = ""
    ) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let wanted = times.isEmpty
            ? [0.05, 0.20, 0.35, 0.50, 0.65, 0.85].map { $0 * duration }
            : times

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 정확한 시각이어야 원본과 같은 프레임끼리 비교된다. 관용을 주면 이웃 프레임이 나온다.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        for t in wanted {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            let name = String(format: "%@%06.2fs.png", prefix, t).replacingOccurrences(of: " ", with: "0")
            let out = directory.appending(path: name)
            try StillRenderer.writePNG(image, to: out)
            written.append(out)
        }
        return written
    }
}

// MARK: - 나란히 비교

extension FrameSheet {
    /// 두 영상의 같은 시각 프레임을 **왼쪽 원본 · 오른쪽 렌더** 로 붙여 한 장으로 만든다.
    ///
    /// `docs/stage-0.spec.md` 통과 조건 B 의 판정 방식이다.
    /// 숫자만 보고 통과라고 하지 않는다 — 사람이 눈으로 본다 (AGENTS.md §14).
    ///
    /// - Parameter band: 화면 전체 대신 이 세로 구간만 자른다 (0..1, 위에서부터).
    ///   자막만 볼 때는 아래쪽 좁은 띠를 준다.
    public static func compareSheet(
        original: URL,
        rendered: URL,
        at times: [Double],
        band: ClosedRange<Double> = 0...1,
        columnWidth: Int = 420,
        to outputURL: URL
    ) async throws {
        func generator(_ url: URL) -> AVAssetImageGenerator {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            g.appliesPreferredTrackTransform = true
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
            return g
        }
        let left = generator(original), right = generator(rendered)

        var rows: [(CGImage, CGImage)] = []
        for t in times {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            let (a, _) = try await left.image(at: time)
            let (b, _) = try await right.image(at: time)
            rows.append((a, b))
        }
        guard let first = rows.first?.0 else { return }

        func crop(_ image: CGImage) -> CGImage {
            guard band != 0...1 else { return image }
            let y = Int(Double(image.height) * band.lowerBound)
            let h = max(Int(Double(image.height) * (band.upperBound - band.lowerBound)), 1)
            return image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: h)) ?? image
        }

        let sample = crop(first)
        let rowHeight = Int(Double(columnWidth) * Double(sample.height) / Double(sample.width))
        let gap = 8
        let width = columnWidth * 2 + gap
        let height = (rowHeight + gap) * rows.count + gap

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StillRenderer.Failure.contextCreationFailed }
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var y = height - gap
        for (a, b) in rows {
            y -= rowHeight
            ctx.draw(crop(a), in: CGRect(x: 0, y: y, width: columnWidth, height: rowHeight))
            ctx.draw(crop(b), in: CGRect(
                x: columnWidth + gap, y: y, width: columnWidth, height: rowHeight
            ))
            y -= gap
        }
        guard let image = ctx.makeImage() else { throw StillRenderer.Failure.contextCreationFailed }
        try StillRenderer.writePNG(image, to: outputURL)
    }
}

// MARK: - 격자 시트

extension FrameSheet {
    /// 여러 시각의 프레임을 격자로 붙여 한 장으로 만든다.
    ///
    /// `AGENTS.md §6` 의 다이제스트 `FRAMES` 가 쓰는 형태이고,
    /// 레이아웃 어휘 조사처럼 "한 편을 훑어본다" 는 작업에도 쓴다.
    /// 이미 갖고 있는 이미지들을 격자로. `grid(from:)` 이 쓰는 것과 같은 그리기다.
    /// 셀 높이는 **가장 높은 비율**에 맞춘다 — 세로·가로가 섞여도 안 찌그러진다.
    @discardableResult
    public static func gridOf(
        _ images: [CGImage], columns: Int = 5, cellWidth: Int = 340, to outputURL: URL
    ) throws -> URL {
        guard !images.isEmpty else { throw StillRenderer.Failure.contextCreationFailed }
        let tallest = images.map { Double($0.height) / Double($0.width) }.max() ?? 1
        let cellHeight = Int(Double(cellWidth) * tallest)
        let rows = (images.count + columns - 1) / columns
        let gap = 6
        let width = columns * cellWidth + (columns + 1) * gap
        let height = rows * cellHeight + (rows + 1) * gap

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StillRenderer.Failure.contextCreationFailed }
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, image) in images.enumerated() {
            let col = i % columns, row = i / columns
            // 비율을 지키며 셀 안에 맞춘다.
            let scale = min(Double(cellWidth) / Double(image.width),
                            Double(cellHeight) / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let x = Double(gap + col * (cellWidth + gap)) + (Double(cellWidth) - w) / 2
            let y = Double(height - gap - (row + 1) * cellHeight - row * gap)
                + (Double(cellHeight) - h) / 2
            ctx.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
        }
        guard let out = ctx.makeImage() else {
            throw StillRenderer.Failure.contextCreationFailed
        }
        try StillRenderer.writePNG(out, to: outputURL)
        return outputURL
    }

    @discardableResult
    public static func grid(
        from url: URL,
        at times: [Double] = [],
        columns: Int = 5,
        cellWidth: Int = 340,
        to outputURL: URL
    ) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let wanted = times.isEmpty
            ? stride(from: 0.05, through: 0.95, by: 0.1).map { $0 * duration }
            : times

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var images: [CGImage] = []
        for t in wanted {
            let (image, _) = try await generator.image(
                at: CMTime(seconds: min(t, duration - 0.05), preferredTimescale: 600)
            )
            images.append(image)
        }
        guard let first = images.first else { return [] }

        let cellHeight = Int(Double(cellWidth) * Double(first.height) / Double(first.width))
        let rows = (images.count + columns - 1) / columns
        let gap = 6
        let width = columns * cellWidth + (columns + 1) * gap
        let height = rows * cellHeight + (rows + 1) * gap

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StillRenderer.Failure.contextCreationFailed }
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, image) in images.enumerated() {
            let col = i % columns, row = i / columns
            let x = gap + col * (cellWidth + gap)
            // 격자는 위에서 아래로 읽는다. CG 좌표는 아래가 0 이라 뒤집는다.
            let y = height - gap - (row + 1) * cellHeight - row * gap
            ctx.draw(image, in: CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }
        guard let sheet = ctx.makeImage() else { throw StillRenderer.Failure.contextCreationFailed }
        try StillRenderer.writePNG(sheet, to: outputURL)
        return wanted
    }
}
