import Foundation
import AVFoundation
import CoreGraphics
import os

/// 0.5초 간격 피사체 표본 하나. `AGENTS.md §6 SUBJECT` 한 줄에 해당한다.
public struct SubjectSample: Codable, Hashable, Sendable {
    /// **원본** 초. 장면 로컬이 아니다.
    public var t: Double
    /// 따라가던 마스크 덩어리의 상자. `nil` 이면 그 시각에 입력이 없다.
    public var box: NormRect?
    /// 덩어리 픽셀 무게중심 (y 는 위로). 크롭 가로 중심이 이걸 쓴다
    /// (`docs/findings/2026-09-25-reframe-center-rule.md §2`).
    public var massCenterX: Double?
    public var massCenterY: Double?
    /// 프레임 대비 마스크 픽셀 비율.
    public var coverage: Double
    /// 원본에서 이미 위/아래가 잘려 있었다. **G2 의 분모를 정하는 값이다** (`AGENTS.md §8`).
    public var touchesTop: Bool
    public var touchesBottom: Bool
    /// 마스크 한 픽셀의 정규화 높이. 크롭 경계 판정 허용오차.
    public var pixelHeight: Double

    public var isMissing: Bool { box == nil }

    public init(
        t: Double, box: NormRect?, massCenterX: Double?, massCenterY: Double?, coverage: Double,
        touchesTop: Bool = false, touchesBottom: Bool = false, pixelHeight: Double = 0.003
    ) {
        self.t = t; self.box = box
        self.massCenterX = massCenterX; self.massCenterY = massCenterY
        self.coverage = coverage
        self.touchesTop = touchesTop; self.touchesBottom = touchesBottom
        self.pixelHeight = pixelHeight
    }
}

/// 한 원본 전체의 피사체 추적 결과. 리프레임 키프레임의 **유일한 입력**이다.
///
/// 관절이 아니라 **분할 마스크**를 쓴다. 관절은 대용 원본 6편에서 37/60 프레임만 잡혔고
/// 분할은 60/60 이었다 (`docs/findings/2026-09-25-pose-detection-spike.md`).
public struct SubjectTrack: Codable, Sendable {
    public var source: SourceInfo
    public var stepSec: Double
    public var samples: [SubjectSample]

    public init(source: SourceInfo, stepSec: Double, samples: [SubjectSample]) {
        self.source = source; self.stepSec = stepSec; self.samples = samples
    }

    /// 입력이 없는 표본 비율.
    public var missingRatio: Double {
        guard !samples.isEmpty else { return 1 }
        return Double(samples.filter(\.isMissing).count) / Double(samples.count)
    }

    /// **20% 를 넘으면 게이트를 판정하지 않는다** (`AGENTS.md §8`).
    /// 통과로 적지도, 실패로 적지도 않는다 — `판정 불가` 다.
    public static let missingRatioLimit = 0.20
    public var isJudgeable: Bool { missingRatio <= Self.missingRatioLimit }

    public func samples(in range: ClosedRange<Double>) -> [SubjectSample] {
        samples.filter { $0.t >= range.lowerBound - 1e-9 && $0.t <= range.upperBound + 1e-9 }
    }
}

/// 원본 파일 → `SubjectTrack`.
///
/// 프레임을 PNG 로 떨어뜨린 뒤 읽는다. `Vision` 요청이 `CGImage` 를 받고,
/// 같은 프레임을 `tools/measure.mjs` 로 교차 검증할 수 있어야 하기 때문이다.
/// 3단계에서 캐시 디렉토리로 옮긴다 (`AGENTS.md §7` 중간 산출물).
public enum SubjectTrackBuilder {

    private static let log = Logger(subsystem: "app.madi", category: "analyze")

    /// 덩어리로 인정할 최소 픽셀 비율.
    ///
    /// ★ **0.005(0.5%)는 너무 높다.** 4K 세로로 멀리서 찍은 IMG_6022 는 사람이
    ///   프레임의 0.6~1.7% 뿐이라 하한에 걸려 절반이 버려졌다 — 입력없음이
    ///   27.5% 에서 48% 로 뛰었다 (`docs/findings/2026-09-25-subject-track.md §2`).
    ///   해상도가 올라가면 사람이 차지하는 **비율**은 그대로여야 하는데,
    ///   분할 마스크가 작은 피사체에서 성기게 잡혀 실제 비율이 내려간다.
    public static let defaultMinCoverage = 0.0005

    public static func build(
        videoID: String,
        url: URL,
        stepSec: Double = 0.5,
        until: Double? = nil,
        minCoverage: Double = defaultMinCoverage,
        workDir: URL
    ) async throws -> SubjectTrack {
        let info = try await FrameSheet.info(of: url)
        let source = SourceInfo(
            videoID: videoID,
            width: Int(info.size.width.rounded()),
            height: Int(info.size.height.rounded()),
            durationSec: info.duration,
            fps: Double(info.fps)
        )
        let end = min(until ?? info.duration, info.duration - 0.05)
        let times = stride(from: 0.0, to: max(end, stepSec), by: stepSec).map { $0 }
        let frames = try await FrameSheet.extract(
            from: url, at: times, into: workDir, prefix: ""
        )

        var samples: [SubjectSample] = []
        var previous: NormRect?
        for (i, frame) in frames.enumerated() {
            let image = try StillRenderer.loadImage(frame)
            let parts = try SubjectDetector.maskComponents(image, minCoverage: minCoverage)
            // 직전에 따라가던 덩어리와 가장 많이 겹치는 것을 이어서 따라간다.
            // IMG_6022 에서 배율 변동 감소 효과는 **0** 이었다
              // (`docs/findings/2026-09-25-zoom-design.md §4`) — 그래도 규칙은 남긴다.
            guard let part = SubjectDetector.follow(parts, previous: previous) else {
                samples.append(SubjectSample(
                    t: times[i], box: nil, massCenterX: nil, massCenterY: nil, coverage: 0
                ))
                previous = nil
                continue
            }
            previous = part.box
            samples.append(SubjectSample(
                t: times[i], box: part.box,
                massCenterX: part.massCenter.x, massCenterY: part.massCenter.y,
                coverage: part.coverage,
                touchesTop: part.touchesTop, touchesBottom: part.touchesBottom,
                pixelHeight: part.pixelHeight
            ))
        }

        let track = SubjectTrack(source: source, stepSec: stepSec, samples: samples)
        log.info("""
        추적 \(videoID, privacy: .public): \(samples.count) 표본, \
        입력 없음 \(Int(track.missingRatio * 100))%
        """)
        return track
    }
}
