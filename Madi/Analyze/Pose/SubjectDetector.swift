import Foundation
import Vision
import CoreGraphics
import CoreVideo

/// 한 프레임에서 "피사체가 어디 있나" 를 **여러 방법으로** 물어본다.
///
/// 관절만으로는 부족하다는 게 0단계 스파이크에서 드러났다
/// (`docs/findings/2026-09-25-pose-detection-spike.md`):
/// 클로즈업에서 `VNDetectHumanBodyPoseRequest` 가 아무것도 내지 않고,
/// 관절 상자에는 **머리 꼭대기가 없다** (최상단 관절이 눈 · 귀 · 코다).
///
/// 그래서 G1 · G2 의 "사람 높이" 를 무엇으로 잴지 고르기 위해 후보를 나란히 재 본다.
/// **여기서 고르는 게 아니라 재기만 한다.** 고르는 건 사람이 정의를 정한 뒤다.
public struct SubjectScan: Sendable {
    /// 관절에서 만든 상자. 머리 꼭대기가 빠진다.
    public var jointBox: NormRect?
    /// 사람 분할 마스크의 상자. **머리 꼭대기가 들어간다.**
    public var segmentBox: NormRect?
    /// 마스크가 프레임에서 차지하는 픽셀 비율. 0 이면 사람이 없다고 본 것이다.
    public var segmentCoverage: Double
    /// `VNDetectHumanRectanglesRequest` 전신.
    public var personBox: NormRect?
    /// 같은 요청의 `upperBodyOnly` 판.
    public var upperBodyBox: NormRect?
    /// 잡힌 손 개수. 마사지 클로즈업처럼 몸이 없는 화면의 단서.
    public var handCount: Int
    /// 주목도(saliency) 최상위 영역. 사람이 아예 없는 화면의 폴백 후보.
    public var salientBox: NormRect?

    public init() {
        jointBox = nil; segmentBox = nil; segmentCoverage = 0
        personBox = nil; upperBodyBox = nil; handCount = 0; salientBox = nil
    }
}

public enum SubjectDetector {

    public static func scan(
        _ image: CGImage, minJointConfidence: Float = 0.3
    ) throws -> SubjectScan {
        var scan = SubjectScan()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let pose = VNDetectHumanBodyPoseRequest()
        let segment = VNGeneratePersonSegmentationRequest()
        // .accurate 는 느리지만 0단계는 시간을 재지 않는다. 품질을 본다.
        segment.qualityLevel = .accurate
        segment.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let person = VNDetectHumanRectanglesRequest()
        let upper = VNDetectHumanRectanglesRequest()
        upper.upperBodyOnly = true
        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 4
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()

        // 하나가 실패해도 나머지 결과는 본다 — 무엇이 되고 무엇이 안 되는지가 목적이다.
        try? handler.perform([pose, segment, person, upper, hands, saliency])

        if let observation = (pose.results ?? []).first,
           let points = try? observation.recognizedPoints(.all) {
            let located = points.values.filter { $0.confidence >= minJointConfidence }
            if !located.isEmpty {
                let xs = located.map(\.location.x), ys = located.map(\.location.y)
                scan.jointBox = NormRect(
                    x: xs.min()!, y: ys.min()!,
                    w: max(xs.max()! - xs.min()!, 0.0001),
                    h: max(ys.max()! - ys.min()!, 0.0001)
                )
            }
        }

        if let mask = (segment.results ?? []).first?.pixelBuffer {
            let result = maskBox(mask)
            scan.segmentBox = result.box
            scan.segmentCoverage = result.coverage
        }

        scan.personBox = largest(person.results ?? [])
        scan.upperBodyBox = largest(upper.results ?? [])
        scan.handCount = (hands.results ?? []).count
        if let salient = (saliency.results ?? []).first,
           let objects = salient.salientObjects {
            scan.salientBox = largest(objects)
        }
        return scan
    }

    /// 가로 띠별 사람 마스크 밀도.
    ///
    /// 자막이 피사체를 덮는지 보려면 **상자가 아니라 마스크**가 필요하다.
    /// 인물 상자는 화면의 87% 를 차지해서 어느 자막 위치든 "겹친다" 고 나온다
    /// (`docs/findings/2026-09-25-caption-position-10.md` 가설 검증).
    ///
    /// - Parameter bands: `(아래에서의 비율, 높이 비율)` 쌍. y 가 위로 가는 좌표.
    /// - Returns: 띠마다 `그 띠에서 마스크가 덮은 가로 비율의 중앙값`.
    ///   자막은 가로로 길게 놓이므로 "이 높이에서 사람이 가로로 얼마나 차지하나" 가 맞는 질문이다.
    public static func maskBandCoverage(
        _ image: CGImage, bands: [(bottom: Double, height: Double)]
    ) throws -> [Double] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let segment = VNGeneratePersonSegmentationRequest()
        segment.qualityLevel = .accurate
        segment.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([segment])
        guard let buffer = (segment.results ?? []).first?.pixelBuffer else {
            return bands.map { _ in 0 }
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return bands.map { _ in 0 } }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let px = base.bindMemory(to: UInt8.self, capacity: stride * h)

        return bands.map { band in
            // 마스크는 이미지 좌표(위가 0행). 아래에서의 비율을 행 번호로 바꾼다.
            let rowLo = Int((1 - band.bottom - band.height) * Double(h))
            let rowHi = Int((1 - band.bottom) * Double(h))
            let lo = max(0, min(rowLo, h - 1)), hi = max(0, min(rowHi, h - 1))
            guard hi > lo else { return 0 }
            var perRow: [Double] = []
            for row in lo...hi {
                var n = 0
                for x in 0..<w where px[row * stride + x] > 127 { n += 1 }
                perRow.append(Double(n) / Double(w))
            }
            perRow.sort()
            return perRow[perRow.count / 2]
        }
    }

    /// 사람 마스크를 **떨어져 있는 덩어리**로 쪼갠다.
    ///
    /// 2인 영상(도수치료: 시술자 + 회원)에서 "누구를 피사체로 볼지" 를 정하려면
    /// 마스크가 한 덩어리인지 두 덩어리인지 알아야 한다. 상자 하나로는 둘을 합쳐 버린다.
    ///
    /// - Returns: 넓이 큰 순서. 각 덩어리의 상자와 픽셀 수(프레임 대비 비율).
    public static func maskComponents(
        _ image: CGImage, minCoverage: Double = 0.005
    ) throws -> [(box: NormRect, coverage: Double)] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let segment = VNGeneratePersonSegmentationRequest()
        segment.qualityLevel = .accurate
        segment.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([segment])
        guard let buffer = (segment.results ?? []).first?.pixelBuffer else { return [] }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let px = base.bindMemory(to: UInt8.self, capacity: stride * h)

        // 너비 우선 탐색으로 이어진 픽셀을 묶는다. 마스크는 원본보다 작아서 이 정도면 충분하다.
        var seen = [Bool](repeating: false, count: w * h)
        var out: [(NormRect, Double)] = []
        var queue: [Int] = []
        queue.reserveCapacity(w * h / 4)

        for start in 0..<(w * h) {
            guard !seen[start] else { continue }
            let sx = start % w, sy = start / w
            guard px[sy * stride + sx] > 127 else { seen[start] = true; continue }

            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            seen[start] = true
            var minX = sx, maxX = sx, minRow = sy, maxRow = sy, count = 0
            var head = 0
            while head < queue.count {
                let index = queue[head]; head += 1
                let x = index % w, y = index / w
                count += 1
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minRow { minRow = y }; if y > maxRow { maxRow = y }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let next = ny * w + nx
                    guard !seen[next], px[ny * stride + nx] > 127 else { continue }
                    seen[next] = true
                    queue.append(next)
                }
            }
            let coverage = Double(count) / Double(w * h)
            guard coverage >= minCoverage else { continue }
            out.append((NormRect(
                x: Double(minX) / Double(w),
                y: 1 - Double(maxRow + 1) / Double(h),
                w: Double(maxX - minX + 1) / Double(w),
                h: Double(maxRow - minRow + 1) / Double(h)
            ), coverage))
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// 크롭 중심 후보를 비교하기 위한 마스크 통계.
    public struct MaskStats: Sendable {
        /// 마스크 상자.
        public let box: NormRect
        /// 마스크 픽셀의 가로 무게중심 (0..1).
        public let massCenterX: Double
        /// 마스크 픽셀의 **세로** 무게중심 (0..1, y 가 위로 가는 좌표).
        public let massCenterY: Double
        /// 열별 마스크 픽셀 수 (가로 512칸으로 압축). 크롭 안에 남는 양을 셀 때 쓴다.
        public let columnMass: [Double]
        /// 전체 마스크 픽셀 수 ÷ 프레임 픽셀 수.
        public let coverage: Double
    }

    public static func maskStats(_ image: CGImage) throws -> MaskStats? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let segment = VNGeneratePersonSegmentationRequest()
        segment.qualityLevel = .accurate
        segment.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([segment])
        guard let buffer = (segment.results ?? []).first?.pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let px = base.bindMemory(to: UInt8.self, capacity: stride * h)

        let bins = 512
        var columns = [Double](repeating: 0, count: bins)
        var minX = w, maxX = -1, minRow = h, maxRow = -1
        var total = 0.0, weightedX = 0.0, weightedRow = 0.0
        for row in 0..<h {
            for x in 0..<w where px[row * stride + x] > 127 {
                total += 1
                weightedX += Double(x)
                weightedRow += Double(row)
                columns[min(bins - 1, x * bins / w)] += 1
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if row < minRow { minRow = row }; if row > maxRow { maxRow = row }
            }
        }
        guard total > 0, maxX >= 0 else { return nil }
        return MaskStats(
            box: NormRect(
                x: Double(minX) / Double(w),
                y: 1 - Double(maxRow + 1) / Double(h),
                w: Double(maxX - minX + 1) / Double(w),
                h: Double(maxRow - minRow + 1) / Double(h)
            ),
            massCenterX: weightedX / total / Double(w),
            // 마스크는 위가 0행. NormRect 와 같은 y-up 으로 뒤집는다.
            massCenterY: 1 - (weightedRow / total / Double(h)),
            columnMass: columns.map { $0 / total },
            coverage: total / Double(w * h)
        )
    }

    private static func largest(_ observations: [VNDetectedObjectObservation]) -> NormRect? {
        guard let best = observations.max(by: {
            $0.boundingBox.height * $0.boundingBox.width
                < $1.boundingBox.height * $1.boundingBox.width
        }) else { return nil }
        return NormRect(
            x: best.boundingBox.minX, y: best.boundingBox.minY,
            w: best.boundingBox.width, h: best.boundingBox.height
        )
    }

    /// 분할 마스크에서 사람 픽셀의 상자와 차지 비율.
    ///
    /// ★ 마스크는 이미지 좌표(위가 0행)로 오고, `NormRect` 는 y 가 위로 가는 좌표다. 뒤집는다.
    private static func maskBox(_ buffer: CVPixelBuffer) -> (box: NormRect?, coverage: Double) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (nil, 0) }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let px = base.bindMemory(to: UInt8.self, capacity: stride * h)

        // 마스크는 0..255 확률이다. 절반을 넘으면 사람으로 본다.
        var minX = w, maxX = -1, minRow = h, maxRow = -1, count = 0
        for row in 0..<h {
            for x in 0..<w where px[row * stride + x] > 127 {
                count += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
            }
        }
        guard maxX >= 0, maxRow >= 0 else { return (nil, 0) }
        let box = NormRect(
            x: Double(minX) / Double(w),
            y: 1 - Double(maxRow + 1) / Double(h),
            w: Double(maxX - minX + 1) / Double(w),
            h: Double(maxRow - minRow + 1) / Double(h)
        )
        return (box, Double(count) / Double(w * h))
    }
}
