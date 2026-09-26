import Foundation
import CoreGraphics

/// 품질 게이트 측정. **코드로 잰다. AI 판단에 맡기지 않는다** (`AGENTS.md §8`).
///
/// 여기는 자막 쪽(G4 · G5 · G6 · G7)이다.
/// 리프레이밍 쪽(G1 · G2 · G3)은 `ReframePlanner` 가 키프레임을 만들면서 같이 잰다 —
/// 같은 계산을 두 번 하지 않기 위해서다.
public enum Gate {

    // MARK: - G4 자막 크기

    /// 글자 높이 ÷ 프레임 높이의 하한. 원본 실측 3.59% 에 여유 -15% (`AGENTS.md §8`).
    public static let minInkHeightRatio = 0.032

    public struct G4Measurement: Sendable {
        public var inkHeightRatio: Double
        public var slot: CaptionSlot
    }

    /// 스타일 값만으로 정해진다 — 자막마다 다르지 않다 (원본은 크기가 고정이다, `§9`).
    public static func g4(
        frameSize: CGSize, style: StyleValues, slot: CaptionSlot
    ) -> (GateResult, G4Measurement) {
        let metrics = CaptionLayout.metrics(frameSize: frameSize, style: style, slot: slot)
        let ratio = Double(metrics.inkHeight / frameSize.height)
        let m = G4Measurement(inkHeightRatio: ratio, slot: slot)
        return (ratio >= minInkHeightRatio ? .pass : .fail, m)
    }

    // MARK: - G5 자막 분절

    public struct G5Measurement: Sendable {
        public var captionCount: Int
        /// 글자 수 상한을 넘은 자막.
        public var overChars: [String]
        /// 줄 수 상한을 넘은 자막.
        public var overLines: [String]
        /// 실제 글자 수 분포 — 공개본 실측(중앙 9 · p90 13)과 대조하려고 남긴다.
        public var charCounts: [Int]
    }

    public static func g5(
        _ comp: Composition, frameSize: CGSize, style: StyleValues
    ) -> (GateResult, G5Measurement) {
        var overChars: [String] = [], overLines: [String] = [], counts: [Int] = []
        for scene in comp.scenes {
            let slot = comp.captionSlot(for: scene)
            let metrics = CaptionLayout.metrics(frameSize: frameSize, style: style, slot: slot)
            let font = style.captionFont(size: metrics.fontSize)
            for caption in scene.captions {
                counts.append(caption.text.count)
                if caption.text.count > style.caption.maxChars { overChars.append(caption.id) }
                let lines = CaptionLayout.wrap(
                    caption.text, font: font,
                    maxWidth: frameSize.width * style.caption.maxWidthRatio,
                    style: style.caption
                )
                if lines.count > style.caption.maxLines { overLines.append(caption.id) }
            }
        }
        let m = G5Measurement(
            captionCount: counts.count, overChars: overChars,
            overLines: overLines, charCounts: counts
        )
        guard !counts.isEmpty else { return (.cannotJudge(.noCaptions), m) }
        return (overChars.isEmpty && overLines.isEmpty ? .pass : .fail, m)
    }

    // MARK: - G6 자막 싱크

    /// 캡션 시작과 대응 낱말 시작의 허용 오차 (초).
    public static let maxSyncErrorSec = 0.15

    public struct G6Measurement: Sendable {
        public var checked: Int
        /// 대응 낱말을 못 찾은 자막 수.
        public var unmatched: Int
        public var errors: [Double]
        public var worstError: Double { errors.map(abs).max() ?? 0 }
    }

    /// - Parameter transcript: **원본 초** 기준. 장면 오프셋은 여기서 맞춘다.
    ///
    /// 대응 낱말은 "캡션 본문의 첫 낱말과 글자가 같은 것 중 가장 가까운 것" 이다.
    /// 시각만으로 가장 가까운 낱말을 고르면 오차가 정의상 작아져 게이트가 무의미해진다.
    public static func g6(
        _ comp: Composition, transcript: Transcript
    ) -> (GateResult, G6Measurement) {
        var errors: [Double] = []
        var unmatched = 0
        for scene in comp.scenes {
            for caption in scene.captions {
                let firstWord = caption.text.split(separator: " ").first.map(String.init) ?? ""
                let sourceStart = scene.source.start + caption.start * scene.speed
                let candidates = transcript.words.filter { $0.text == firstWord }
                guard let match = candidates.min(by: {
                    abs($0.start - sourceStart) < abs($1.start - sourceStart)
                }) else { unmatched += 1; continue }
                errors.append(match.start - sourceStart)
            }
        }
        let m = G6Measurement(
            checked: errors.count, unmatched: unmatched, errors: errors
        )
        guard !errors.isEmpty else { return (.cannotJudge(.noTranscript), m) }
        return (m.worstError <= maxSyncErrorSec ? .pass : .fail, m)
    }

    // MARK: - G7 자막 가림

    public struct G7Measurement: Sendable {
        /// 자막이 떠 있고 관절도 잡힌 표본 수.
        public var checked: Int
        /// 그중 어깨선 위 관절이 자막 상자 안에 들어간 표본 수.
        public var covered: Int
        public var coveredJoints: Set<String>
        public var ratio: Double { checked > 0 ? Double(covered) / Double(checked) : 0 }
    }

    /// 어깨선 **위** 관절. G7 이 지키려는 건 얼굴이다.
    public static let aboveShoulder: [PoseObservation.Joint] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar, .neck, .leftShoulder, .rightShoulder,
    ]

    /// - Returns: 측정만. **판정을 내리지 않는다.**
    ///
    /// ⚠ 임계값이 아직 없다. 공개본 9편을 재 보니 7편은 0% 인데
    ///   `lzDW-9ITfWU` 가 **24%**, `nCshtY04NiY` 가 11% 다 — 몸을 앞으로 숙이면
    ///   머리가 자막 띠로 내려오고 크리에이터는 그대로 얹는다
    ///   (`docs/findings/2026-09-26-g7-measurement.md`).
    ///   "덮지 않음" 을 문자 그대로 걸면 **크리에이터 본인 영상이 탈락한다.**
    ///   G4(4.5%) · G5(13자) · G2(86% 탈락) 와 같은 길이다.
    ///
    ///   "고른 슬롯이 다른 슬롯보다 덜 덮는가" 로 바꾸는 안(B)도 **공개본 9편 중 2편에서
    ///   걸렸다.** 슬롯은 영상이 보여주는 **몸의 범위**로 고르는 것이라, 바닥 자세에서는
    ///   자막도 아래고 숙인 머리도 아래다 — 두 목표가 충돌한다.
    ///   **측정만 하는 것으로 확정했다** (`docs/findings/2026-09-26-g7-measurement.md §4-1`).
    public static func g7(
        captionBox: NormRect, joints: [PoseObservation.Joint: (point: CGPoint, confidence: Float)],
        minConfidence: Float = 0.3
    ) -> (covered: Bool, hits: Set<String>) {
        var hits: Set<String> = []
        for joint in aboveShoulder {
            guard let (p, conf) = joints[joint], conf >= minConfidence else { continue }
            let inside = p.x >= captionBox.x && p.x <= captionBox.x + captionBox.w
                && p.y >= captionBox.y && p.y <= captionBox.y + captionBox.h
            if inside { hits.insert(joint.rawValue) }
        }
        return (!hits.isEmpty, hits)
    }
}
