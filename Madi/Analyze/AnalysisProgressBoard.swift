import Foundation

/// 분석 중인 영상의 단계별 진행률. 메모리에만 있다 — 분석 작업이 올리고, 바꾸는 층이 읽어
/// 편집안 준비 화면의 "말 받아적기 42%" 에 낸다.
///
/// 받아적기와 사람 찾기(영상 읽기)는 **동시에** 돈다 (`DigestBuilder`) — 그래서 단계마다 따로 든다.
public struct AnalysisProgress: Hashable, Sendable {
    /// 0…1. nil 이면 아직 시작 전.
    public var transcribe: Double?
    /// 사람 찾기 + 컷 찾기(같은 영상 읽기) + 그림 몇 장. 0…1.
    public var findPerson: Double?

    public init(transcribe: Double? = nil, findPerson: Double? = nil) {
        self.transcribe = transcribe; self.findPerson = findPerson
    }
}

public actor AnalysisProgressBoard {
    private var values: [String: AnalysisProgress] = [:]
    public init() {}
    public func set(_ videoID: String, _ step: DigestBuilder.Step, _ fraction: Double) {
        let f = min(max(fraction, 0), 1)
        var v = values[videoID] ?? AnalysisProgress()
        // 뒤로 가지 않는다 (창이 바뀔 때 WhisperKit 진행률이 잠깐 줄어든다)
        switch step {
        case .transcribe: v.transcribe = max(v.transcribe ?? 0, f)
        case .findPerson, .rest: v.findPerson = max(v.findPerson ?? 0, f)
        }
        values[videoID] = v
    }
    public func clear(_ videoID: String) { values[videoID] = nil }
    public func snapshot() -> [String: AnalysisProgress] { values }
}
