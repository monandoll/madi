import Foundation

/// 편집안의 자막을 **앱이** 채운다 (docs/stage-4.spec.md — 2026-09-27 결정).
///
/// AI 는 장면(원본 구간 · 순서 · 배속)만 고른다. 자막 덩어리와 시각은 여기서 나온다.
/// - 분절은 템플릿 값이다 (`AGENTS.md §9` — 크기 · 위치 · **분절**은 측정값). `CaptionSplitter` 는 공개본 10편에 맞춰 뒀다
/// - 다이제스트 전사는 문장 단위라 AI 는 낱말 시각을 모른다. AI 가 시각을 쓰면 G6(±0.15초)를 맞출 길이 없다
///
/// **영문 보조 문구**는 AI 가 문장마다 한 줄 쓰고, 여기서 그 문장에 걸린 덩어리들에 나눠 붙인다.
/// 크리에이터 원본이 그렇게 생겼다 — "잘 들어?" 아래 "me!", "중간 관절이라서" 위 "your hip and ankle,"
/// (공개본 프레임, 2026-09-27). 덩어리마다 따로 번역한 게 아니라 문장 번역을 시간 순서대로 나눈 것이다.
/// ⚠ 나누는 비율(한글 글자 수)은 **재지 않은 잠정 규칙**이다.
public enum CaptionFiller {

    /// AI 가 쓴 문장 하나의 영문. `sentenceStart` 는 다이제스트 `[시작-끝]` 의 시작 초.
    public struct Translation: Sendable, Equatable {
        public var sentenceStart: Double
        public var text: String
        public init(sentenceStart: Double, text: String) { self.sentenceStart = sentenceStart; self.text = text }
    }

    /// 다이제스트는 소수 둘째 자리까지 적는다. 그보다 느슨하게 맞춘다.
    static let sentenceTolerance = 0.02

    /// 장면 경계가 **낱말 안에** 떨어지면 가까운 낱말 경계로 옮긴다. 옮긴 곳 수를 돌려준다.
    ///
    /// AI 는 문장 단위 전사만 보고 문장 안을 어림으로 자른다. 그대로 두면 소리에는 반쯤 잘린 낱말이 남고
    /// 자막에서는 빠진다 (2026-09-27 첫 초안 — "20초 동안" 의 "20초" 한가운데서 잘렸다).
    /// 경계가 낱말 가운데보다 앞이면 그 낱말을 넣고, 뒤면 뺀다.
    @discardableResult
    /// - Parameter limit: 영상 길이. 낱말 끝으로 밀어도 이 뒤로는 안 간다 — 전사 마지막 낱말 끝이 영상보다
    ///   길게 나오는 일이 있다 (실제: 60.00초 영상에 60.08초까지 밀려 렌더가 5번 연속 실패).
    public static func snapToWords(_ comp: inout Composition, words: [Word], limit: Double? = nil) -> Int {
        var moved = 0
        for i in comp.scenes.indices {
            var src = comp.scenes[i].source
            if let w = words.first(where: { $0.start < src.start && src.start < $0.end }) {
                src.start = src.start < (w.start + w.end) / 2 ? w.start : w.end
            }
            if let w = words.first(where: { $0.start < src.end && src.end < $0.end }) {
                src.end = src.end > (w.start + w.end) / 2 ? w.end : w.start
            }
            if let limit { src.end = min(src.end, limit) }
            if src != comp.scenes[i].source, src.end > src.start {
                comp.scenes[i].source = src
                moved += 1
            }
        }
        return moved
    }

    /// 장면마다 원본 구간 안의 낱말을 분절해 `captions` 를 채우고, 영문을 나눠 붙인다.
    /// 문제가 있으면 AI 가 고칠 수 있는 문장으로 돌려준다 (빈 배열이면 성공).
    public static func fill(
        _ comp: inout Composition, words: [Word], style: StyleValues.CaptionValues, translations: [Translation]
    ) -> [String] {
        var problems: [String] = []

        // 1. 장면별 분절. 자막 시각은 장면 로컬 · 배속 반영.
        //    원본 구간에 **온전히 들어온 낱말만** 쓴다 — 컷에 걸린 낱말은 말이 잘린 것이라 자막을 달지 않는다.
        var placed: [(scene: Int, caption: Int, sourceMid: Double)] = []
        for si in comp.scenes.indices {
            let s = comp.scenes[si]
            let inRange = words.filter { $0.start >= s.source.start - 0.01 && $0.end <= s.source.end + 0.05 }
            var caps = CaptionSplitter.split(inRange, style: style, offset: s.source.start)
            let limit = s.duration
            for ci in caps.indices {
                caps[ci].id = "\(s.id)-\(caps[ci].id)"
                caps[ci].start = min(caps[ci].start / s.speed, limit)
                caps[ci].end = min(caps[ci].end / s.speed, limit)
                let mid = (caps[ci].start + caps[ci].end) / 2 * s.speed + s.source.start
                placed.append((si, ci, mid))
            }
            comp.scenes[si].captions = caps.filter { $0.end > $0.start }
        }

        // 2. 영문 — 문장 하나를 그 문장에 걸린 덩어리들에 나눈다.
        let sentences = DigestBuilder.sentences(words)
        for t in translations {
            let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let sentence = sentences.first(where: { abs($0.start - t.sentenceStart) <= sentenceTolerance }) else {
                problems.append("secondary: \(String(format: "%.2f", t.sentenceStart)) 에서 시작하는 문장이 다이제스트에 없다 — TRANSCRIPT 의 [시작-끝] 에서 시작 값을 그대로 쓴다")
                continue
            }
            let targets = placed.filter { $0.sourceMid >= sentence.start - 0.01 && $0.sourceMid <= sentence.end + 0.01 }
                .filter { comp.scenes[$0.scene].captions.indices.contains($0.caption) }
            if targets.isEmpty {
                problems.append("secondary: \(String(format: "%.2f", t.sentenceStart)) 문장은 고른 장면에 들어 있지 않다 — 빼거나 장면에 넣는다")
                continue
            }
            let korean = targets.map { comp.scenes[$0.scene].captions[$0.caption].text }
            for (target, piece) in zip(targets, distribute(text, over: korean)) {
                comp.scenes[target.scene].captions[target.caption].secondary = piece
            }
        }
        return problems
    }

    /// 영문 낱말을 순서대로 덩어리들에 나눈다. 덩어리 몫 = 한글 글자 수 비율. 낱말 안에서는 끊지 않는다.
    /// 낱말이 덩어리보다 적으면 뒤쪽 덩어리는 영문이 없다 (nil).
    static func distribute(_ text: String, over korean: [String]) -> [String?] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !korean.isEmpty else { return [] }
        guard !words.isEmpty else { return korean.map { _ in nil } }
        let weights = korean.map { Double(max($0.filter { !$0.isWhitespace }.count, 1)) }
        let total = weights.reduce(0, +)
        let englishTotal = Double(words.reduce(0) { $0 + $1.count })

        var out: [[String]] = Array(repeating: [], count: korean.count)
        var bucket = 0
        var cumulativeWeight = weights[0]
        var used = 0.0
        for (i, w) in words.enumerated() {
            let remainingWords = words.count - i
            let remainingBuckets = korean.count - bucket
            // 낱말 가운데가 지금 덩어리 몫을 넘었으면 다음 덩어리로. 뒤 덩어리마다 한 낱말은 남긴다.
            let mid = (used + Double(w.count) / 2) / englishTotal
            while bucket < korean.count - 1, !out[bucket].isEmpty, mid > cumulativeWeight / total,
                  remainingWords >= remainingBuckets - 1 {
                bucket += 1
                cumulativeWeight += weights[bucket]
            }
            out[bucket].append(w)
            used += Double(w.count)
        }
        return out.map { $0.isEmpty ? nil : $0.joined(separator: " ") }
    }
}
