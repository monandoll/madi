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

    /// 한국어 **구문 경계**. 이 어미·조사로 끝나는 낱말 뒤에서 끊는다.
    ///
    /// ★ 쉼으로 끊으려 했다가 실패했다. WhisperKit `base` 의 낱말 시각은
    ///   낱말 사이가 거의 붙어 있다 (42개 중 0.30초 이상이 **2개**).
    ///   그리고 번인 자막 덩어리 사이의 0.25초 간격은 OCR 표본 간격(1/4초)이지
    ///   실제 쉼이 아니었다 (`docs/findings/2026-09-26-caption-splitter.md §1`).
    ///
    /// 쌤 자막 경계를 읽으면 규칙은 시간이 아니라 **문법**에 있다 —
    /// `…할 때,` `…하는데` `…생각보다` `…더라구요` `…상태에서` `…주시고` `…앉아주세요`.
    /// 연결어미 · 종결어미 · 부사격 조사에서 끊는다.
    static let clauseEndings: [String] = [
        // 종결
        "요", "다", "죠", "까", "네", "군요", "세요", "예요", "에요", "니다",
        // 연결
        "고", "서", "면", "며", "니", "나", "듯", "게", "야", "데", "만", "든",
        "지만", "니까", "는데", "면서", "아서", "어서", "려고", "도록", "거나",
        // 부사격 · 보조사 (구 경계)
        "에", "에서", "으로", "로", "까지", "부터", "보다", "처럼", "마다", "대로",
    ]

    /// 이 낱말 뒤가 구문 경계인가.
    static func endsClause(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard !trimmed.isEmpty else { return false }
        // 문장 부호가 붙어 있으면 그 자체가 경계다.
        if let last = trimmed.last, ".,!?…".contains(last) { return true }
        return clauseEndings.contains { trimmed.hasSuffix($0) }
    }

    /// - Parameter offset: 장면 로컬 시각으로 옮기기 위해 뺄 값 (원본 초).
    public static func split(
        _ words: [Word], style: StyleValues.CaptionValues, offset: Double = 0
    ) -> [Caption] {
        func text(_ ws: ArraySlice<Word>) -> String {
            ws.map(\.text).joined(separator: " ")
        }

        var chunks: [ArraySlice<Word>] = []
        var start = 0
        var i = 0
        while i < words.count {
            // 이 낱말까지 담았을 때의 상태.
            let candidate = words[start...i]
            let chars = text(candidate).count
            let duration = words[i].end - words[start].start
            let isLast = i == words.count - 1

            // 상한을 넘겼으면 **직전까지**로 끊는다. 낱말 안에서는 끊지 않는다.
            if chars > style.maxChars && i > start {
                // 목표를 넘긴 뒤 나온 가장 마지막 구문 경계로 되돌아가 끊는다.
                var cut = i - 1
                var j = i - 1
                while j > start {
                    if endsClause(words[j].text),
                       text(words[start...j]).count >= style.minCharsBeforeBreak {
                        cut = j
                        break
                    }
                    j -= 1
                }
                chunks.append(words[start...cut])
                start = cut + 1
                i = start
                continue
            }

            // 목표를 채웠고 여기가 구문 경계면 끊는다. **이게 기본 규칙이다.**
            if chars >= style.minCharsBeforeBreak, endsClause(words[i].text), !isLast {
                chunks.append(candidate)
                start = i + 1
                i = start
                continue
            }

            if duration > style.maxDurationSec, i > start {
                chunks.append(words[start...(i - 1)])
                start = i
                continue
            }

            if isLast { chunks.append(words[start...i]) }
            i += 1
        }

        return chunks.enumerated().map { i, ws in
            Caption(
                id: "c\(i + 1)",
                start: max(0, (ws.first?.start ?? 0) - offset),
                end: max(0, (ws.last?.end ?? 0) - offset),
                text: text(ws)
            )
        }
    }
}
