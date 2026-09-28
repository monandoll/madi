import Foundation

/// iCloud 원본을 받는 중인 영상의 진행률 (0…1). 메모리에만 있다 — "저장 공간 최적화" 면 오래 걸린다 (§2).
/// 가져오기가 올리고, 바꾸는 층이 읽어 갤러리 칸(`ShotItem.fetchProgress`)에 낸다.
public actor ImportProgressBoard {
    private var values: [String: Double] = [:]
    public init() {}
    public func set(_ videoID: String, _ fraction: Double) { values[videoID] = min(max(fraction, 0), 1) }
    public func clear(_ videoID: String) { values[videoID] = nil }
    public func snapshot() -> [String: Double] { values }
}
