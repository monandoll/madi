import Foundation
import CoreGraphics

/// `SubjectTrack` → 리프레임 키프레임 + G1 · G3 측정.
///
/// ```
/// 표본(0.5s) → 배율·중심 계산 → 빈 구간 채우기 → 스무딩(0.4s) → 키프레임
/// ```
///
/// **여기서 나온 키프레임은 `Composition` 에 다시 적는다** (`AGENTS.md §7-1`).
/// 렌더가 `SubjectTrack` 을 다시 읽지 않아야 결과가 재현 가능하다.
public enum ReframePlanner {

    /// 크롭 **세로** 중심을 무엇에 맞출지.
    ///
    /// 가로는 이미 무게중심으로 정해졌다 (`docs/findings/2026-09-25-reframe-center-rule.md §2`).
    /// 세로는 그 조사에서 "아직 안 정한 것" 으로 남았다 — 6편 전부 크롭이 전체 높이를 써서
    /// 고를 게 없었다. 확대가 들어오면서 처음 고를 일이 생겼다.
    /// **주장하지 않고 잰다** — `madi-spike reframe --anchor` 로 둘을 비교한다.
    public enum VerticalAnchor: String, Sendable, CaseIterable {
        /// 상자 위·아래 여백이 같아진다.
        case boxCenter
        /// 픽셀이 많은 쪽으로 간다. 가로에서 이긴 규칙.
        case massCenter
    }

    /// 스무딩 전 한 표본의 목표.
    struct Target {
        var t: Double
        var zoom: Double
        var center: CGPoint
        /// 배율 상한에 걸려 목표 점유율에 못 닿았다.
        var zoomCapped: Bool
        /// 마스크가 없어 이웃에서 채운 값.
        var filled: Bool
        /// 원본 상자 (있을 때만). 잘림 측정에 쓴다.
        var box: NormRect?
    }

    public struct Measurement: Sendable {
        public var sampleCount: Int
        public var missingRatio: Double
        /// 크롭 뒤 인물 높이. 스무딩된 배율이 반영된 값이다.
        public var subjectHeights: [Double]
        /// G1 — 인물 높이가 0.55 이상인 표본 비율.
        public var heightPassRatio: Double
        /// 0.55 에 못 닿았고 **그 이유가 배율 상한**인 표본 비율.
        public var sourceLimitedRatio: Double
        /// 배율 상한 때문에 못 닿은 표본 수.
        public var cappedFailCount: Int
        /// 배율에 여유가 있었는데도 못 닿은 표본 수. **이게 0 보다 크면 진짜 실패다.**
        public var hardFailCount: Int
        /// G3 — 출력 프레임 폭 대비 1프레임당 크롭 중심 이동, 최댓값.
        public var maxCenterShiftPerFrame: Double
        /// 상자가 크롭 밖으로 나간 면적 비율의 평균. 조용히 자르지 않기 위해 남긴다
        /// (`docs/findings/2026-09-25-reframe-center-rule.md §2`).
        public var clippedRatio: Double
        /// G2 — **우리가 새로 자른** 비율. `AGENTS.md §8`.
        public var g2: G2Measurement
    }

    public struct Plan: Sendable {
        public var keyframes: [ReframeTrack.Keyframe]
        public var measurement: Measurement
        public var g1: GateResult
        public var g2: GateResult
        public var g3: GateResult
    }

    /// G2 — "**리프레이밍이 새로 자른** 구간 5% 이하" (`AGENTS.md §8`).
    ///
    /// 원본에서 마스크가 위/아래 경계에 **안 닿았는데** 크롭 뒤 닿게 된 비율이다.
    /// 원본이 이미 닿은 프레임은 분모에서 뺀다 — 세로 숏폼에서 발이 프레임 밖으로
    /// 나가는 건 정상이고, 그걸로 재면 공개본이 86% 탈락한다.
    ///
    /// **좌우는 보지 않는다.** 팔 끝이 잘리는 건 문제가 아니다.
    ///
    /// ⚠ 위/아래를 **따로** 잰다. `§8` 문장("원본이 이미 닿은 프레임은 분모에서 뺀다")은
    ///   프레임 단위로도 읽히는데, 그러면 발이 잘린 프레임이 통째로 빠져서
    ///   **머리 잘림을 잴 표본이 거의 안 남는다.** 비교용으로 그 해석도 같이 계산해
    ///   `strict*` 에 담는다 (`docs/findings/2026-09-25-g2-measurement.md §2`).
    public struct G2Measurement: Sendable {
        /// 원본에서 위가 안 잘려 있던 표본 수. 이게 분모다.
        public var topEligible: Int
        /// 그중 크롭 뒤 위가 잘린 표본 수.
        public var topNewlyClipped: Int
        public var bottomEligible: Int
        public var bottomNewlyClipped: Int
        /// 위/아래 중 **나쁜 쪽**. 게이트는 이걸 본다.
        public var worstRatio: Double
        /// 프레임 단위 해석: 원본에서 위·아래 어느 쪽도 안 잘린 표본만 분모.
        public var strictEligible: Int
        public var strictNewlyClipped: Int

        public var topRatio: Double {
            topEligible > 0 ? Double(topNewlyClipped) / Double(topEligible) : 0
        }
        public var bottomRatio: Double {
            bottomEligible > 0 ? Double(bottomNewlyClipped) / Double(bottomEligible) : 0
        }
        public var strictRatio: Double {
            strictEligible > 0 ? Double(strictNewlyClipped) / Double(strictEligible) : 0
        }
    }

    /// G2 임계값. `AGENTS.md §8`.
    public static let maxNewlyClippedRatio = 0.05

    /// G1 하한. 근거는 `AGENTS.md §8` — 미학 목표(0.72)와 다르다.
    public static let minSubjectHeight = 0.55
    public static let minHeightPassRatio = 0.80
    /// G3 — 프레임 폭의 3% / frame.
    public static let maxCenterShiftPerFrame = 0.03

    /// - Parameters:
    ///   - range: 이 장면이 쓰는 **원본** 구간 (초).
    ///   - speed: 장면 배속. 키프레임 시각은 장면 로컬 **출력** 초다.
    public static func plan(
        track: SubjectTrack,
        range: ClosedRange<Double>,
        speed: Double = 1,
        output: CGSize,
        fps: Int,
        style: StyleValues.ReframeValues,
        verticalAnchor: VerticalAnchor = .boxCenter
    ) -> Plan {
        let source = track.source.size
        let picked = track.samples(in: range)
        let missingRatio = picked.isEmpty
            ? 1 : Double(picked.filter(\.isMissing).count) / Double(picked.count)

        // 표본이 하나도 없으면 중앙 크롭 하나만 놓고 판정 불가로 남긴다.
        guard !picked.isEmpty, picked.contains(where: { !$0.isMissing }) else {
            let rect = ReframeLimits.cropRect(
                zoom: 1, center: CGPoint(x: 0.5, y: 0.5), source: source, output: output
            )
            return Plan(
                keyframes: [ReframeTrack.Keyframe(t: 0, rect: rect)],
                measurement: Measurement(
                    sampleCount: picked.count, missingRatio: 1, subjectHeights: [],
                    heightPassRatio: 0, sourceLimitedRatio: 0,
                    cappedFailCount: 0, hardFailCount: 0,
                    maxCenterShiftPerFrame: 0, clippedRatio: 0,
                    g2: G2Measurement(
                        topEligible: 0, topNewlyClipped: 0,
                        bottomEligible: 0, bottomNewlyClipped: 0, worstRatio: 0,
                        strictEligible: 0, strictNewlyClipped: 0
                    )
                ),
                g1: .cannotJudge(.subjectNotFound),
                g2: .cannotJudge(.subjectNotFound),
                g3: .cannotJudge(.subjectNotFound)
            )
        }

        var targets = rawTargets(
            picked, source: source, output: output, style: style, verticalAnchor: verticalAnchor
        )
        fillGaps(&targets)
        let smoothed = smooth(targets, sigma: style.smoothingSec)

        // 키프레임. 시각은 장면 로컬 출력 초.
        var keyframes: [ReframeTrack.Keyframe] = []
        var heights: [Double] = []
        var cappedFails = 0, hardFails = 0
        var clipped: [Double] = []
        var g2 = G2Measurement(
            topEligible: 0, topNewlyClipped: 0, bottomEligible: 0, bottomNewlyClipped: 0,
            worstRatio: 0, strictEligible: 0, strictNewlyClipped: 0
        )
        for (i, s) in smoothed.enumerated() {
            let rect = ReframeLimits.cropRect(
                zoom: s.zoom, center: s.center, source: source, output: output
            )
            keyframes.append(ReframeTrack.Keyframe(
                t: max(0, (s.t - range.lowerBound) / max(speed, 0.0001)), rect: rect
            ))
            guard let box = targets[i].box else { continue }
            let height = rect.h > 0 ? box.h / rect.h : 0
            heights.append(height)
            if height < minSubjectHeight {
                if targets[i].zoomCapped { cappedFails += 1 } else { hardFails += 1 }
            }
            clipped.append(max(0, 1 - overlapRatio(box, rect)))

            // G2. 크롭 경계 판정은 마스크 한 픽셀만큼 봐준다.
            let sample = picked[i]
            let eps = sample.pixelHeight
            let cutTop = (box.y + box.h) >= (rect.y + rect.h) - eps
            let cutBottom = box.y <= rect.y + eps
            if !sample.touchesTop {
                g2.topEligible += 1
                if cutTop { g2.topNewlyClipped += 1 }
            }
            if !sample.touchesBottom {
                g2.bottomEligible += 1
                if cutBottom { g2.bottomNewlyClipped += 1 }
            }
            if !sample.touchesTop && !sample.touchesBottom {
                g2.strictEligible += 1
                if cutTop || cutBottom { g2.strictNewlyClipped += 1 }
            }
        }
        g2.worstRatio = max(g2.topRatio, g2.bottomRatio)

        let counted = max(heights.count, 1)
        let passRatio = Double(heights.filter { $0 >= minSubjectHeight }.count) / Double(counted)
        let sourceLimitedRatio = Double(cappedFails) / Double(counted)

        let g1: GateResult
        if missingRatio > SubjectTrack.missingRatioLimit {
            // 입력이 없는 구간이 너무 많다. 통과로도 실패로도 적지 않는다.
            g1 = .cannotJudge(.subjectNotFound)
        } else if passRatio >= minHeightPassRatio {
            g1 = .pass
        } else if hardFails == 0 {
            // 못 닿은 표본이 **전부** 배율 상한 때문이다. self-eval 로 되돌려도 달라지지 않는다.
            g1 = .sourceLimited(.subjectTooSmallLowResolution)
        } else {
            g1 = .fail
        }

        let shift = maxShiftPerFrame(keyframes, source: source, output: output, fps: fps)
        let g3: GateResult = missingRatio > SubjectTrack.missingRatioLimit
            ? .cannotJudge(.subjectNotFound)
            : (shift <= maxCenterShiftPerFrame ? .pass : .fail)

        return Plan(
            keyframes: keyframes,
            measurement: Measurement(
                sampleCount: picked.count,
                missingRatio: missingRatio,
                subjectHeights: heights,
                heightPassRatio: passRatio,
                sourceLimitedRatio: sourceLimitedRatio,
                cappedFailCount: cappedFails, hardFailCount: hardFails,
                maxCenterShiftPerFrame: shift,
                clippedRatio: mean(clipped), g2: g2
            ),
            g1: g1, g2: g2Result(g2, missingRatio: missingRatio), g3: g3
        )
    }

    /// G2 판정. 분모가 비면 **통과로 적지 않는다** — 잴 수 없었던 것이다.
    static func g2Result(_ m: G2Measurement, missingRatio: Double) -> GateResult {
        if missingRatio > SubjectTrack.missingRatioLimit {
            return .cannotJudge(.subjectNotFound)
        }
        // 원본이 위·아래 다 잘려 있으면 "우리가 새로 잘랐는가" 를 물을 수 없다.
        guard m.topEligible > 0 || m.bottomEligible > 0 else {
            return .cannotJudge(.subjectAlreadyCropped)
        }
        return m.worstRatio <= maxNewlyClippedRatio ? .pass : .fail
    }

    // MARK: - Composition 되쓰기

    public struct CompositionPlan: Sendable {
        /// 키프레임이 채워진 새 `Composition`. **이것만 렌더에 넘긴다.**
        public var composition: Composition
        /// 장면 id → 측정값.
        public var scenes: [(sceneID: String, measurement: Measurement)]
        /// 영상 단위 판정. 장면별 판정을 그대로 쓰지 않는다 —
        /// `판정 불가` 기준(20%)은 **영상 길이** 기준이다 (`AGENTS.md §8`).
        public var g1: GateResult
        public var g2: GateResult
        public var g3: GateResult
        public var missingRatio: Double
        public var g2Measurement: G2Measurement
        public var heightPassRatio: Double
        public var maxCenterShiftPerFrame: Double
        public var clippedRatio: Double
    }

    /// `reframe.mode == .auto` 인 장면의 키프레임을 채워 **`Composition` 에 다시 적는다.**
    ///
    /// 되쓰기가 선택이 아닌 이유: 렌더는 항상 `Composition` 으로부터 재현 가능해야 한다
    /// (`AGENTS.md §1-8`, `§7-1`). 렌더 때마다 `SubjectTrack` 을 다시 돌리면
    /// Vision 버전이 바뀌는 순간 같은 편집안이 다른 영상을 낸다.
    public static func apply(
        to comp: Composition, tracks: [String: SubjectTrack], style: StyleValues,
        verticalAnchor: VerticalAnchor = .boxCenter
    ) -> CompositionPlan {
        var out = comp
        var perScene: [(String, Measurement)] = []
        var totalSamples = 0, totalMissing = 0
        var heights: [Double] = []
        var capped = 0, hard = 0
        var shift = 0.0
        var clipped: [Double] = []
        var g2 = G2Measurement(
            topEligible: 0, topNewlyClipped: 0, bottomEligible: 0, bottomNewlyClipped: 0,
            worstRatio: 0, strictEligible: 0, strictNewlyClipped: 0
        )

        for i in out.scenes.indices {
            let scene = out.scenes[i]
            guard scene.reframe.mode == .auto else { continue }
            guard let track = tracks[scene.source.videoID] else { continue }
            let scenePlan = plan(
                track: track,
                range: scene.source.start...scene.source.end,
                speed: scene.speed,
                output: comp.size.cgSize,
                fps: comp.fps,
                style: style.reframe,
                verticalAnchor: verticalAnchor
            )
            out.scenes[i].reframe.mode = .keyframes
            out.scenes[i].reframe.keyframes = scenePlan.keyframes
            perScene.append((scene.id, scenePlan.measurement))

            let m = scenePlan.measurement
            totalSamples += m.sampleCount
            totalMissing += Int((m.missingRatio * Double(m.sampleCount)).rounded())
            heights += m.subjectHeights
            capped += m.cappedFailCount
            hard += m.hardFailCount
            shift = max(shift, m.maxCenterShiftPerFrame)
            clipped.append(m.clippedRatio)
            g2.topEligible += m.g2.topEligible
            g2.topNewlyClipped += m.g2.topNewlyClipped
            g2.bottomEligible += m.g2.bottomEligible
            g2.bottomNewlyClipped += m.g2.bottomNewlyClipped
            g2.strictEligible += m.g2.strictEligible
            g2.strictNewlyClipped += m.g2.strictNewlyClipped
        }

        let missingRatio = totalSamples > 0 ? Double(totalMissing) / Double(totalSamples) : 1
        let counted = max(heights.count, 1)
        let passRatio = Double(heights.filter { $0 >= minSubjectHeight }.count) / Double(counted)

        let g1: GateResult
        if missingRatio > SubjectTrack.missingRatioLimit || heights.isEmpty {
            g1 = .cannotJudge(.subjectNotFound)
        } else if passRatio >= minHeightPassRatio {
            g1 = .pass
        } else if hard == 0 && capped > 0 {
            g1 = .sourceLimited(.subjectTooSmallLowResolution)
        } else {
            g1 = .fail
        }
        let g3: GateResult = (missingRatio > SubjectTrack.missingRatioLimit || heights.isEmpty)
            ? .cannotJudge(.subjectNotFound)
            : (shift <= maxCenterShiftPerFrame ? .pass : .fail)
        g2.worstRatio = max(g2.topRatio, g2.bottomRatio)

        return CompositionPlan(
            composition: out, scenes: perScene,
            g1: g1, g2: g2Result(g2, missingRatio: missingRatio), g3: g3,
            missingRatio: missingRatio, g2Measurement: g2, heightPassRatio: passRatio,
            maxCenterShiftPerFrame: shift, clippedRatio: mean(clipped)
        )
    }

    // MARK: - 표본 → 목표

    static func mean(_ v: [Double]) -> Double {
        v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    static func rawTargets(
        _ samples: [SubjectSample], source: CGSize, output: CGSize,
        style: StyleValues.ReframeValues, verticalAnchor: VerticalAnchor
    ) -> [Target] {
        samples.map { sample in
            guard let box = sample.box else {
                return Target(
                    t: sample.t, zoom: 1, center: CGPoint(x: 0.5, y: 0.5),
                    zoomCapped: false, filled: true, box: nil
                )
            }
            // 목표 점유율은 **출력 화면 기준**이라 배율 1 크롭 높이로 환산해서 넣는다.
            let visible = ReframeLimits.normalizedSubjectHeight(
                boxHeight: box.h, source: source, output: output
            )
            let planned = ReframeLimits.plan(
                subjectHeight: visible,
                target: style.targetSubjectHeightRatio,
                source: source, output: output, maxUpscale: style.maxUpscale
            )
            return Target(
                t: sample.t,
                zoom: planned.zoom,
                center: CGPoint(
                    // 가로는 무게중심. 팔을 벌리면 상자가 팔 끝에 끌려간다.
                    x: sample.massCenterX ?? (box.x + box.w / 2),
                    // 세로는 고른 규칙에 따른다. 어느 쪽이 나은지는 측정으로 정한다.
                    y: verticalAnchor == .boxCenter
                        ? box.y + box.h / 2
                        : (sample.massCenterY ?? box.y + box.h / 2)
                ),
                zoomCapped: !planned.reachedTarget,
                filled: false, box: box
            )
        }
    }

    /// 마스크가 없던 표본을 양옆에서 채운다. 양쪽에 값이 있으면 선형 보간,
    /// 한쪽만 있으면 그 값을 유지한다. **없는 구간을 화면 중앙으로 튀게 두지 않는다.**
    static func fillGaps(_ targets: inout [Target]) {
        let known = targets.indices.filter { !targets[$0].filled }
        guard let first = known.first, let last = known.last else { return }
        for i in targets.indices where targets[i].filled {
            if i < first { targets[i].zoom = targets[first].zoom; targets[i].center = targets[first].center; continue }
            if i > last { targets[i].zoom = targets[last].zoom; targets[i].center = targets[last].center; continue }
            let before = known.last { $0 < i }!
            let after = known.first { $0 > i }!
            let span = targets[after].t - targets[before].t
            let u = span > 0 ? (targets[i].t - targets[before].t) / span : 0
            targets[i].zoom = targets[before].zoom + (targets[after].zoom - targets[before].zoom) * u
            targets[i].center = CGPoint(
                x: targets[before].center.x + (targets[after].center.x - targets[before].center.x) * u,
                y: targets[before].center.y + (targets[after].center.y - targets[before].center.y) * u
            )
        }
    }

    /// 시간축 저역통과. 가중치는 가우시안, `sigma = smoothingSec`, 3시그마에서 자른다.
    ///
    /// 표본 간격이 0.5초인데 sigma 가 0.4초면 창이 ±1 표본이다 — 약하다.
    /// 그래도 창을 키우지 않는다. 키우면 인물이 실제로 움직일 때 크롭이 늦게 따라간다.
    static func smooth(_ targets: [Target], sigma: Double) -> [Target] {
        guard sigma > 0, targets.count > 1 else { return targets }
        var out = targets
        for i in targets.indices {
            var wSum = 0.0, zoom = 0.0, cx = 0.0, cy = 0.0
            for j in targets.indices {
                let d = (targets[j].t - targets[i].t) / sigma
                guard abs(d) <= 3 else { continue }
                let w = exp(-0.5 * d * d)
                wSum += w
                zoom += targets[j].zoom * w
                cx += targets[j].center.x * w
                cy += targets[j].center.y * w
            }
            guard wSum > 0 else { continue }
            out[i].zoom = zoom / wSum
            out[i].center = CGPoint(x: cx / wSum, y: cy / wSum)
        }
        return out
    }

    // MARK: - 측정

    /// `a` 가 `b` 안에 남는 면적 비율. 1 이면 안 잘렸다.
    static func overlapRatio(_ a: NormRect, _ b: NormRect) -> Double {
        let w = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
        let h = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
        let area = a.w * a.h
        return area > 0 ? (w * h) / area : 0
    }

    /// G3. 크롭 중심이 1프레임 동안 움직인 거리를 **출력 프레임 폭 단위**로 잰다.
    ///
    /// 원본 정규화 이동량을 그대로 쓰면 안 된다 — 크롭이 좁을수록 같은 이동이 화면에서 크게 보인다.
    static func maxShiftPerFrame(
        _ keyframes: [ReframeTrack.Keyframe], source: CGSize, output: CGSize, fps: Int
    ) -> Double {
        guard keyframes.count > 1, fps > 0 else { return 0 }
        let aspect = output.height / output.width
        var worst = 0.0
        for i in 1..<keyframes.count {
            let a = keyframes[i - 1], b = keyframes[i]
            let frames = max((b.t - a.t) * Double(fps), 1)
            let cropW = max((a.rect.w + b.rect.w) / 2 * source.width, 1)
            let cropH = max((a.rect.h + b.rect.h) / 2 * source.height, 1)
            let dx = ((b.rect.x + b.rect.w / 2) - (a.rect.x + a.rect.w / 2)) * source.width / cropW
            let dy = ((b.rect.y + b.rect.h / 2) - (a.rect.y + a.rect.h / 2)) * source.height / cropH
            worst = max(worst, hypot(dx, dy * aspect) / frames)
        }
        return worst
    }
}
