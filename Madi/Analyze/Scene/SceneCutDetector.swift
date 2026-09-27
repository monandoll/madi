import Foundation
import AVFoundation
import CoreGraphics

/// 다이제스트 `SCENES` (AGENTS.md §6). 프레임 차분으로 컷 지점을 찾는다.
///
/// 작은 흑백 썸네일(64px 폭)을 일정 간격으로 뽑아 이웃 프레임의 **평균 밝기 차**를 잰다.
/// 차가 기준보다 크고 앞뒤보다 큰 곳(국소 최대)이 컷이다.
///
/// ⚠ **기준값이 잠정이다** — `threshold` 0.12 (0..1 밝기). 촬영 원본으로 잰다 (3단계 5번).
///   촬영 규칙(`§11`)대로 블록마다 1초 정지하고 찍으면 컷이 원본 안에 없을 수도 있다 —
///   그땐 이 값이 거의 안 쓰인다.
public enum SceneCutDetector {

    public static let sampleFPS = 5.0
    public static let threshold = 0.12

    public struct Result: Codable, Hashable, Sendable {
        public var cuts: [Double]
        /// 이웃 표본 사이 평균 밝기 차 (0..1). 기준을 다시 잴 때 쓴다.
        public var diffs: [Double]
        public var stepSec: Double
    }

    public static func detect(_ url: URL, fps: Double = sampleFPS) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 64, height: 64)
        // 앞쪽 여유는 0 — 표본 t 는 "t 이후 첫 프레임" 이다. 앞뒤로 여유를 주면 전환 직전 프레임이
        // 나와서 컷이 한 표본 늦게 잡혔다 (합성 영상 1.0초 전환 → 1.2초).
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)

        let step = 1 / fps
        var thumbs: [[UInt8]] = []
        var t = 0.0
        while t < duration - 0.01 {
            let image = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            thumbs.append(gray(image))
            t += step
        }
        var diffs: [Double] = []
        for i in 1..<max(thumbs.count, 1) { diffs.append(meanAbsDiff(thumbs[i - 1], thumbs[i])) }
        return Result(cuts: cuts(in: diffs, stepSec: step), diffs: diffs, stepSec: step)
    }

    /// 차분 배열에서 컷 시각. diffs[i] 는 표본 i 와 i+1 사이 — 컷은 표본 i+1 의 시각.
    public static func cuts(in diffs: [Double], stepSec: Double, threshold: Double = threshold) -> [Double] {
        var out: [Double] = []
        for (i, d) in diffs.enumerated() where d >= threshold {
            let prev = i > 0 ? diffs[i - 1] : 0
            let next = i + 1 < diffs.count ? diffs[i + 1] : 0
            // 페이드처럼 여러 표본에 걸친 변화는 가장 큰 곳 하나만.
            if d >= prev && d > next { out.append(Double(i + 1) * stepSec) }
        }
        return out
    }

    private static func gray(_ image: CGImage) -> [UInt8] {
        let w = 32, h = 32
        var buf = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }

    private static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        for i in 0..<min(a.count, b.count) { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(max(a.count, 1)) / 255
    }
}
