import Foundation

/// 전사 한 낱말. **word 단위 타임스탬프가 필수다** (`AGENTS.md §3`, `§6`).
///
/// 문장 단위로만 있으면 자막을 끊을 수가 없고, 끊더라도 G6(싱크 0.15초)를 맞출 수 없다.
public struct Word: Codable, Hashable, Sendable {
    public var text: String
    /// 원본 초.
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text; self.start = start; self.end = end
    }
}

/// 한 원본의 전사.
public struct Transcript: Codable, Hashable, Sendable {
    public var videoID: String
    public var words: [Word]

    public init(videoID: String, words: [Word]) {
        self.videoID = videoID; self.words = words
    }

    public func words(in range: ClosedRange<Double>) -> [Word] {
        words.filter { $0.start >= range.lowerBound - 1e-9 && $0.start <= range.upperBound + 1e-9 }
    }
}
