import Foundation

/// 분석 중인 영상의 단계 · 진행률. 메모리에만 있다 — 분석 작업이 올리고, 바꾸는 층이 읽어
/// 편집안 준비 화면의 "말 받아적기 42%" 에 낸다.
public struct AnalysisProgress: Hashable, Sendable {
    public var step: DigestBuilder.Step
    /// 그 단계 안에서 0…1.
    public var fraction: Double

    public init(step: DigestBuilder.Step, fraction: Double) { self.step = step; self.fraction = fraction }
}

public actor AnalysisProgressBoard {
    private var values: [String: AnalysisProgress] = [:]
    public init() {}
    public func set(_ videoID: String, _ step: DigestBuilder.Step, _ fraction: Double) {
        let f = min(max(fraction, 0), 1)
        // 같은 단계에서 뒤로 가지 않는다 (창이 바뀔 때 WhisperKit 진행률이 잠깐 줄어든다)
        if let old = values[videoID], old.step == step, old.fraction > f { return }
        values[videoID] = AnalysisProgress(step: step, fraction: f)
    }
    public func clear(_ videoID: String) { values[videoID] = nil }
    public func snapshot() -> [String: AnalysisProgress] { values }
}
