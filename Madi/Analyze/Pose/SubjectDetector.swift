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
