import Foundation
import CoreGraphics

/// 감지 결과를 프레임 위에 그려 눈으로 확인한다.
///
/// 숫자만 보고 "잘 잡힌다" 고 하지 않는다 (AGENTS.md §14).
/// 제품 렌더가 아니라 **검증 도구**다.
public enum PoseOverlay {

    private static let bones: [(PoseObservation.Joint, PoseObservation.Joint)] = [
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
        (.nose, .neck),
        (.neck, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.neck, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    public static func draw(
        _ observations: [PoseObservation], on image: CGImage
    ) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let ctx = try StillRenderer.makeContext(size: size)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        let unit = size.height / 400  // 선 굵기 기준

        for observation in observations {
            // 관절 상자 — 초록. G1(피사체 크기)이 보는 상자다.
            ctx.setStrokeColor(CGColor(red: 0.2, green: 1, blue: 0.4, alpha: 0.95))
            ctx.setLineWidth(unit * 1.5)
            ctx.stroke(observation.jointBox.rect(in: size))

            // 사람 사각형 — 노랑 점선. 비교용.
            if let person = observation.personBox {
                ctx.saveGState()
                ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.9))
                ctx.setLineDash(phase: 0, lengths: [unit * 4, unit * 3])
                ctx.stroke(person.rect(in: size))
                ctx.restoreGState()
            }

            // 뼈대 — 하늘색
            ctx.setStrokeColor(CGColor(red: 0.3, green: 0.8, blue: 1, alpha: 0.9))
            ctx.setLineWidth(unit)
            ctx.setLineCap(.round)
            for (a, b) in bones {
                guard let pa = observation.joints[a]?.point,
                      let pb = observation.joints[b]?.point else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
                ctx.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
                ctx.strokePath()
            }

            // 관절 점 — 신뢰도가 낮을수록 붉게
            for (_, value) in observation.joints {
                let c = CGFloat(value.confidence)
                ctx.setFillColor(CGColor(red: 1 - c, green: c, blue: 0.25, alpha: 1))
                let r = unit * 2
                ctx.fillEllipse(in: CGRect(
                    x: value.point.x * size.width - r, y: value.point.y * size.height - r,
                    width: r * 2, height: r * 2
                ))
            }
        }

        guard let out = ctx.makeImage() else { throw StillRenderer.Failure.contextCreationFailed }
        return out
    }
}
