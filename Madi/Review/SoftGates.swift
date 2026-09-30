import Foundation

/// 소프트 게이트 (docs/stage-5.spec.md 결정 ②). G8 · G9 · G11 은 되먹임을 부른다 — AI 가 장면 고르기로 고칠 수 있다.
/// G10 은 리포트에만 남긴다.
///
/// - G8 · G10 · G11 은 **편집안**에서 잰다 (결과물 길이 · 장면 순서는 편집안이 정한다)
/// - G9 는 **내보낸 파일**에서 잰다 — 소리와 움직임은 결과물에 실제로 남은 것이어야 한다 (`§7`)
/// - 보여 주기는 막지 않는다. 막는 것은 하드(G1 · G4 · G6)뿐이다 (`§8`)
public enum SoftGates {

    // MARK: G8 훅

    /// 첫 장면이 `hook` 이고 첫 자막이 이 안에 시작한다. 공개본 30편 중 28편이 0.0초, 늦은 두 편은 1.0초(걸어 들어옴) ·
    /// 1.75초(폼롤러 개그) — 크리에이터가 넘는 값이어야 한다 (2026-09-30, 전에는 10편만 보고 0.5초.
    /// `docs/findings/2026-09-30-editing-style-30.md`). AI 에게는 여전히 "첫 말 바로 앞" 을 시킨다 (제작 지침)
    public static let hookFirstCaptionSec = 2.0

    public static func g8(_ comp: Composition) -> (GateResult, firstCaptionSec: Double?) {
        guard let first = comp.scenes.first else { return (.fail, nil) }
        let firstCaption = first.captions.map(\.start).min()
        let ok = first.role == .hook && (firstCaption ?? .infinity) <= hookFirstCaptionSec
        return (ok ? .pass : .fail, firstCaption)
    }

    // MARK: G10 컷 리듬 — 리포트만, 되먹임은 부르지 않는다

    /// 공개본 30편의 편별 장면 길이 중앙값 범위 0.42 ~ 3.58초 (중앙 1.25초) — 점프컷까지 잡는 `madi-spike cutpace` 로 쟀다
    /// (2026-09-30 `docs/findings/2026-09-30-editing-style-30.md`). 전에는 근거 없는 1.5~4.0초였고, 크리에이터 21편이 떨어졌다.
    /// 되먹임은 아직 부르지 않는다 (결정 ②) — 리포트에만 남긴다.
    public static let sceneMedianRange = 0.4...3.6

    public static func g10(_ comp: Composition) -> (GateResult, medianSec: Double) {
        let m = median(comp.scenes.map(\.duration))
        return (sceneMedianRange.contains(m) ? .pass : .fail, m)
    }

    // MARK: G11 길이

    public static let durationTolerance = 0.15

    public static func g11(_ comp: Composition) -> (GateResult, ratio: Double) {
        let target = comp.meta.targetDurationSec
        guard target > 0 else { return (.fail, 0) }
        let ratio = comp.duration / target
        return (abs(ratio - 1) <= durationTolerance ? .pass : .fail, ratio)
    }

    // MARK: G9 정적 구간

    /// 조용하고 가만한 구간이 이보다 길면 안 된다 (`§8`).
    public static let maxStaticSec = 1.2

    /// 무음이면서 움직임이 적은 가장 긴 구간(초). 움직임은 `SceneCutDetector` 차분(이웃 표본 평균 밝기 차).
    /// - Parameter stillDiff: 이 차분 아래를 "가만하다" 로 본다. **공개본 10편에 대 보고 정한다** (결정 ②).
    public static func longestStatic(
        silences: [ClosedRange<Double>], diffs: [Double], stepSec: Double, stillDiff: Double
    ) -> Double {
        var longest = 0.0
        var run = 0.0
        for (i, d) in diffs.enumerated() {
            // diffs[i] 는 표본 i ~ i+1 사이. 그 가운데 시각이 무음 안이고 차분이 작으면 정적.
            let t = (Double(i) + 0.5) * stepSec
            let silent = silences.contains { $0.contains(t) }
            if silent && d < stillDiff {
                run += stepSec
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }

    /// "가만하다" 의 차분 기준. **가장 엄격한 값**이다 — 거의 멈춘 화면만 잡는다.
    /// 공개본에 무음이 없어 근거를 못 찾았다. 크리에이터를 떨어뜨리지 않는 것만 확인했다
    /// (`docs/findings/2026-09-27-soft-gates-public.md`). 촬영본이 생기면 다시 잰다.
    public static let stillDiff = 0.002

    public static func g9(longestStaticSec: Double) -> GateResult {
        longestStaticSec <= maxStaticSec ? .pass : .fail
    }

    public static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return (s[s.count / 2] + s[(s.count - 1) / 2]) / 2
    }
}
