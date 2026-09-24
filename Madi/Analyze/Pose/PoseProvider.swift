import Foundation
import Vision
import CoreGraphics
import os

/// 사람 감지. AGENTS.md §3 이 허용한 **두 개뿐인 추상화** 중 하나다.
///
/// 아키텍처 분기(Apple Silicon / Intel)를 이 프로토콜 뒤에 가둔다.
/// `#if arch(arm64)` 를 코드 곳곳에 뿌리지 않는다 (AGENTS.md §14).
/// 0단계에서는 감지 정확도만 본다 — 리프레이밍은 1단계다.
public protocol PoseProvider: Sendable {
    func detect(in image: CGImage) throws -> [PoseObservation]
}

/// 좌표는 전부 **0..1 정규화 · y 위쪽 증가** (CoreGraphics · Vision 과 같은 방향).
public struct PoseObservation: Sendable {
    /// 신뢰도가 충분한 관절들을 감싸는 상자.
    /// ★ Vision 의 사람 사각형이 아니라 **관절에서 만든** 상자다.
    ///   품질 게이트 G1(피사체 크기)·G2(피사체 잘림)가 보는 게 관절이기 때문이다.
    public let jointBox: NormRect
    /// `VNDetectHumanRectanglesRequest` 가 준 사람 사각형. 비교용.
    public var personBox: NormRect?
    /// 관절별 위치와 신뢰도.
    public let joints: [Joint: (point: CGPoint, confidence: Float)]
    /// 관절 신뢰도의 중앙값.
    public let confidence: Float

    public enum Joint: String, CaseIterable, Sendable {
        case nose, leftEye, rightEye, leftEar, rightEar, neck
        case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
        case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, root

        init?(_ name: VNHumanBodyPoseObservation.JointName) {
            switch name {
            case .nose: self = .nose
            case .leftEye: self = .leftEye
            case .rightEye: self = .rightEye
            case .leftEar: self = .leftEar
            case .rightEar: self = .rightEar
            case .neck: self = .neck
            case .leftShoulder: self = .leftShoulder
            case .rightShoulder: self = .rightShoulder
            case .leftElbow: self = .leftElbow
            case .rightElbow: self = .rightElbow
            case .leftWrist: self = .leftWrist
            case .rightWrist: self = .rightWrist
            case .leftHip: self = .leftHip
            case .rightHip: self = .rightHip
            case .leftKnee: self = .leftKnee
            case .rightKnee: self = .rightKnee
            case .leftAnkle: self = .leftAnkle
            case .rightAnkle: self = .rightAnkle
            case .root: self = .root
            default: return nil
            }
        }
    }

    /// 머리 꼭대기에 해당하는 관절이 잡혔는가. G2(피사체 잘림)가 본다.
    public var hasHead: Bool {
        [.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains { joints[$0] != nil }
    }
    /// 발목이 잡혔는가. G2 가 본다.
    public var hasAnkles: Bool {
        joints[.leftAnkle] != nil || joints[.rightAnkle] != nil
    }
}

/// Vision 구현. Apple Silicon 에서는 ANE, Intel 에서는 CPU/GPU 로 돈다.
/// **품질은 같고 시간만 다르다** (AGENTS.md §17).
public struct VisionPoseProvider: PoseProvider {
    private static let log = Logger(subsystem: "app.madi", category: "pose")

    /// 이 신뢰도 아래 관절은 버린다.
    ///
    /// ⚠ 근거 없는 값이다. Vision 예제들이 흔히 쓰는 0.3 에서 시작했다.
    /// 0단계 스파이크에서 관절별 신뢰도 분포를 찍어 보고 정한다.
    public var minJointConfidence: Float

    /// 사람 사각형까지 같이 구할지. 비교·검증용이라 기본은 끈다.
    public var includePersonBox: Bool

    public init(minJointConfidence: Float = 0.3, includePersonBox: Bool = false) {
        self.minJointConfidence = minJointConfidence
        self.includePersonBox = includePersonBox
    }

    public func detect(in image: CGImage) throws -> [PoseObservation] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let poseRequest = VNDetectHumanBodyPoseRequest()
        var requests: [VNRequest] = [poseRequest]
        let rectRequest = VNDetectHumanRectanglesRequest()
        if includePersonBox { requests.append(rectRequest) }
        try handler.perform(requests)

        let personBoxes = (rectRequest.results ?? []).map { obs in
            NormRect(
                x: obs.boundingBox.minX, y: obs.boundingBox.minY,
                w: obs.boundingBox.width, h: obs.boundingBox.height
            )
        }

        return (poseRequest.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var joints: [PoseObservation.Joint: (CGPoint, Float)] = [:]
            for (name, point) in points {
                guard point.confidence >= minJointConfidence,
                      let joint = PoseObservation.Joint(name) else { continue }
                joints[joint] = (point.location, point.confidence)
            }
            guard !joints.isEmpty else { return nil }

            let xs = joints.values.map(\.0.x), ys = joints.values.map(\.0.y)
            let box = NormRect(
                x: xs.min()!, y: ys.min()!,
                w: max(xs.max()! - xs.min()!, 0.0001),
                h: max(ys.max()! - ys.min()!, 0.0001)
            )
            let confidences = joints.values.map(\.1).sorted()
            return PoseObservation(
                jointBox: box,
                // 관절 상자와 가장 많이 겹치는 사람 사각형을 짝지어 준다.
                personBox: personBoxes.max(by: { overlap($0, box) < overlap($1, box) }),
                joints: joints.mapValues { (point: $0.0, confidence: $0.1) },
                confidence: confidences[confidences.count / 2]
            )
        }
    }

    private func overlap(_ a: NormRect, _ b: NormRect) -> Double {
        let right: Double = min(a.x + a.w, b.x + b.w)
        let left: Double = max(a.x, b.x)
        let top: Double = min(a.y + a.h, b.y + b.h)
        let bottom: Double = max(a.y, b.y)
        return max(0, right - left) * max(0, top - bottom)
    }
}
