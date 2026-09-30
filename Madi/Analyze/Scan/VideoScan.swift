import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import OSLog

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

    static let log = Logger(subsystem: "app.madi", category: "scan")

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
        progress: ((Double) -> Void)? = nil,
        pace: (TimeInterval) async -> Void = { await LoadGovernor.shared.breathe(worked: $0) }
    ) async throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack(url)
        }
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let orientation = Self.orientation(transform)

        let context = CIContext(options: [.cacheIntermediates: false])
        let cutStep = 1 / cutFPS
        var cutTarget = 0.0
        var subjectIndex = 0
        var thumbs: [[UInt8]] = []
        var previous: (pts: Double, image: CIImage)?
        var lastReport = -1.0
        // 해독기(VideoToolbox XPC)가 도중에 끊기면 읽기가 통째로 실패한다 (10분 영상 72% 에서 실측).
        // 끊긴 곳 바로 뒤부터 새 읽기를 열어 이어 간다. 몇 번 해도 안 되면 그때 멈춘다.
        var restarts = 0

        while true {
            let reader = try AVAssetReader(asset: asset)
            if let resumeAt = previous?.pts {
                reader.timeRange = CMTimeRange(start: CMTime(seconds: resumeAt + 0.001, preferredTimescale: 600),
                                               end: CMTime(seconds: duration + 1, preferredTimescale: 600))
            }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            reader.add(output)
            guard reader.startReading() else { throw Failure.readerFailed(reader.error.map { "\($0)" } ?? "?") }

            // ★ 프레임마다 autoreleasepool 로 비운다. 이 반복은 중간에 멈추지(await) 않아서, 비우지 않으면
            //   프레임마다 생기는 임시 객체(`oriented` 가 돌려주는 CIImage · Vision 내부)가 **영상이 끝날 때까지**
            //   해독된 프레임(1080p 한 장 약 8MB)을 붙잡는다. 해독 서비스(VTDecoderXPCService)가 1초에 1.5GB 씩
            //   불어나 10분 영상에서 메모리가 바닥났고, WindowServer 가 멈춰 맥이 두 번 재부팅됐다 (2026-09-29).
            var finished = false
            while !finished {
                let started = Date()
                try autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { finished = true; return }
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    // 이어 읽을 때 키프레임부터 다시 나온다 — 이미 본 프레임은 건너뛴다
                    if let p = previous?.pts, pts <= p + 1e-6 { return }
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
                // 맥이 뜨거우면 쉬어 가고, 위험하면 식을 때까지 기다린다 (LoadGovernor). 보통이면 바로 돌아온다
                await pace(Date().timeIntervalSince(started))
                // 멈추기(■) · 촬영본 삭제 — 프레임마다 본다. 안 보면 긴 영상은 몇 분을 더 읽고서야 멈췄다
                try Task.checkCancellation()
            }
            guard reader.status == .failed else { break }
            restarts += 1
            if restarts > 3 { throw Failure.readerFailed(reader.error.map { "\($0)" } ?? "?") }
            log.warning("영상 읽기가 끊겨 \(String(format: "%.1f", previous?.pts ?? 0), privacy: .public)초부터 다시 연다 (\(restarts)번째)")
        }
        // 끝에 남은 시각 — 마지막 프레임
        if let last = previous?.image {
            while subjectIndex < subjectTimes.count {
                try autoreleasepool { try onSubject(subjectTimes[subjectIndex], last) }
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
