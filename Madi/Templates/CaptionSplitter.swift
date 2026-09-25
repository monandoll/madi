import Foundation

/// 낱말 → 자막 덩어리. **분절은 스타일이 정한다. AI 가 정하지 않는다** (`AGENTS.md §1-2`).
///
/// 규칙은 공개본 10편 190덩어리 실측에서 나왔다
/// (`docs/findings/2026-09-26-caption-segmentation-10.md`):
///
/// - 글자 수 **목표 9자**, 상한 15자. **상한까지 눌러 담지 않는다** — p90 이 13자다
/// - 2줄은 190개 중 1개. 상한이지 목표가 아니다
/// - 덩어리 길이 중앙 0.75~1.25초
///
/// 낱말(어절) 안에서는 절대 끊지 않는다.
public enum CaptionSplitter {

    /// - Parameter offset: 장면 로컬 시각으로 옮기기 위해 뺄 값 (원본 초).
    public static func split(
        _ words: [Word], style: StyleValues.CaptionValues, offset: Double = 0
    ) -> [Caption] {
        var chunks: [[Word]] = []
        var current: [Word] = []

        func text(_ ws: [Word]) -> String {
            ws.map(\.text).joined(separator: " ")
        }

        for word in words {
            guard let last = current.last else { current = [word]; continue }

            let candidate = text(current) + " " + word.text
            let gap = word.start - last.end
            let duration = word.end - current[0].start

            // 상한을 넘기면 무조건 끊는다. 낱말 안에서는 끊지 않으므로
            // 낱말 하나가 상한보다 길면 그 낱말이 통째로 한 덩어리가 된다.
            let overChars = candidate.count > style.maxChars
            let overDuration = duration > style.maxDurationSec
            // 목표를 채웠는데 말이 쉬면 거기서 끊는다. 호흡을 따라가는 분절이다.
            let restedAfterTarget =
                text(current).count >= style.targetChars && gap >= style.pauseSec

            if overChars || overDuration || restedAfterTarget {
                chunks.append(current)
                current = [word]
            } else {
                current.append(word)
            }
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks.enumerated().map { i, ws in
            Caption(
                id: "c\(i + 1)",
                start: max(0, ws[0].start - offset),
                end: max(0, (ws.last?.end ?? ws[0].end) - offset),
                text: text(ws)
            )
        }
    }
}
