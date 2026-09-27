import Foundation

/// 지금 만들고 있는 영상의 진행률 (0…1). 메모리에만 있다 — DB 에 적지 않는다 (0.5초마다 바뀐다).
/// 렌더 작업이 올리고, 바꾸는 층이 읽어 "만드는 중" 화면에 낸다 (docs/stage-6.spec.md 7번).
public actor RenderProgressBoard {
    private var values: [String: Double] = [:]

    public init() {}

    public func set(_ compositionID: String, _ fraction: Double) { values[compositionID] = min(max(fraction, 0), 1) }
    public func clear(_ compositionID: String) { values[compositionID] = nil }
    public func snapshot() -> [String: Double] { values }
}
