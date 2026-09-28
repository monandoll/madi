import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO

/// 영상을 **처음부터 끝까지 한 번, 차례로** 읽으며 사람 찾기 프레임과 컷 찾기 썸네일을 같이 뽑는다.
///
/// 전에는 사람 찾기(0.5초마다)와 컷 찾기(0.2초마다)가 **각자** 영상을 열어 그 시각으로 건너뛰었다.
/// 건너뛸 때마다 앞 키프레임부터 다시 풀어야 해서 느렸고, 사람 찾기는 원본 해상도 프레임을 PNG 로
/// 썼다가 다시 읽었다. 1분 영상에서 이 둘이 49초 — 분석 시간의 대부분이었다 (2026-09-29 실측).
///
/// 뽑는 시각의 뜻은 예전과 같다:
/// - 사람 찾기: 시각 t 에 **화면에 보이는** 프레임 (예전 `AVAssetImageGenerator` 관용 0)
/// - 컷 찾기: 시각 t **이후 첫** 프레임 (예전 관용 앞 0 · 뒤 반 표본)
public enum VideoScan {

    public enum Failure: Error, CustomStringConvertible {
        case noVideoTrack(URL)
        case readerFailed(String)
        public var description: String {
            switch self {
            case .noVideoTrack(let url): "영상 트랙이 없다: \(url.lastPathComponent)"
            case .readerFailed(let reason): "영상을 읽다 멈췄다: \(reason)"
            }
        }
    }

    public struct Result: Sendable {
        /// 컷 찾기 썸네일 (32×32 흑백), `cutStep` 간격.
        public var thumbs: [[UInt8]]
        public var cutStep: Double
    }

    /// - Parameters:
    ///   - subjectTimes: 사람 찾기 시각들 (오름차순).
    ///   - cutFPS: 컷 찾기 표본 수 (초당).
    ///   - onSubject: 사람 찾기 프레임 (회전 반영). 불리는 동안 읽기가 기다린다.
    public static func run(
        url: URL, subjectTimes: [Double], cutFPS: Double,
        onSubject: (Double, CIImage) throws -> Void,
        progress: ((Double) -> Void)? = nil
    ) async throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack(url)
        }
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let orientation = Self.orientation(transform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { throw Failure.readerFailed(reader.error.map { "\($0)" } ?? "?") }

        let context = CIContext(options: [.cacheIntermediates: false])
        let cutStep = 1 / cutFPS
        var cutTarget = 0.0
        var subjectIndex = 0
        var thumbs: [[UInt8]] = []
        var previous: (pts: Double, image: CIImage)?
        var lastReport = -1.0

        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)

            // 사람 찾기 — t 가 이 프레임보다 앞이면 t 에 보이던 것은 직전 프레임이다
            while subjectIndex < subjectTimes.count, subjectTimes[subjectIndex] < pts - 1e-6 {
                try onSubject(subjectTimes[subjectIndex], previous?.image ?? image)
                subjectIndex += 1
            }
            // 컷 찾기 — t 이후 첫 프레임
            while cutTarget < duration - 0.01, cutTarget <= pts + 1e-6 {
                thumbs.append(gray(image, context))
                cutTarget += cutStep
            }
            previous = (pts, image)

            if pts - lastReport >= 1 { progress?(min(pts / max(duration, 0.01), 1)); lastReport = pts }
        }
        if reader.status == .failed { throw Failure.readerFailed(reader.error.map { "\($0)" } ?? "?") }
        // 끝에 남은 시각 — 마지막 프레임
        if let last = previous?.image {
            while subjectIndex < subjectTimes.count {
                try onSubject(subjectTimes[subjectIndex], last)
                subjectIndex += 1
            }
            while cutTarget < duration - 0.01 {
                thumbs.append(gray(last, context))
                cutTarget += cutStep
            }
        }
        progress?(1)
        return Result(thumbs: thumbs, cutStep: cutStep)
    }

    /// 32×32 흑백 — 컷 찾기가 비교하는 썸네일 (`SceneCutDetector` 와 같은 크기).
    static func gray(_ image: CIImage, _ context: CIContext) -> [UInt8] {
        let side = 32
        let extent = image.extent
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width, y: CGFloat(side) / extent.height))
        var buf = [UInt8](repeating: 0, count: side * side)
        context.render(scaled, toBitmap: &buf, rowBytes: side,
                       bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        return buf
    }

    /// 트랙 회전(`preferredTransform`) → 그림 방향. 아이폰 세로 촬영은 90° 회전이 붙어 온다.
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
