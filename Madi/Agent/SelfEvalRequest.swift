import Foundation

/// 되먹임 턴의 요청 칸 (§10 컨텍스트 6번). 무엇이 기준에 못 미쳤는지(측정값과 함께)와 지난 편집안.
///
/// 되먹임을 부르는 항목은 `RenderJob.selfEvalGates` 다 (5단계 결정 ②). 여기서는 그 항목을
/// **AI 가 장면 고르기로 고칠 수 있는 말**로 옮긴다. 기준 수치는 게이트 코드의 상수에서 온다 — 두 번 적지 않는다.
public enum SelfEvalRequest {

    public static func text(report: [String: JSONValue], previous: Composition) -> String {
        let items: [String] = {
            guard case .array(let list)? = report["selfEval"] else { return [] }
            return list.compactMap { if case .string(let s) = $0 { s } else { nil } }
        }()
        var lines = [
            "(자동 점검 — 이 턴은 크리에이터에게 보이지 않는다. 크리에이터에게 하는 말은 쓰지 않는다.)",
            "방금 만든 편집안을 영상으로 내보내 확인했더니 아래가 기준에 못 미쳤다.",
            "",
        ]
        for item in items { lines.append("- " + explain(item, report: report, previous: previous)) }
        lines += [
            "",
            "`read_digest` 로 영상을 다시 읽는다 — 끝에 **지난 결과물**(내보낸 영상에서 뽑은 프레임)이 붙어 있다.",
            "위 항목을 고친 편집안을 `write_composition` 으로 새로 보낸다. 영문(`secondary`)도 쓴 문장마다 다시 보낸다.",
            "고칠 것만 고친다. 괜찮았던 장면은 그대로 둔다. `meta.targetDurationSec` 는 바꾸지 않는다 (바꾸면 저장이 거절된다).",
            "",
            "지난 편집안 (앱이 채우는 칸 — 자막 · 화면 잡기 · id — 은 뺐다):",
            "```json",
            previousJSON(previous),
            "```",
        ]
        return lines.joined(separator: "\n")
    }

    static func number(_ report: [String: JSONValue], _ key: String) -> Double? {
        if case .number(let n)? = report[key] { n } else { nil }
    }

    static func explain(_ item: String, report: [String: JSONValue], previous: Composition) -> String {
        func f(_ x: Double?, _ digits: Int = 1) -> String { x.map { String(format: "%.\(digits)f", $0) } ?? "?" }
        switch item.split(separator: ".").first.map(String.init) ?? item {
        case "G1":
            let ratio = number(report, "heightPassRatio").map { $0 * 100 }
            return "인물 크기: 인물이 화면 높이의 \(Int(ReframePlanner.minSubjectHeight * 100))% 이상인 구간이 "
                + "\(Int(ReframePlanner.minHeightPassRatio * 100))% 는 돼야 하는데 지금 \(f(ratio, 0))% 다. "
                + "인물이 작거나, 다가오거나 멀어지며 크기가 빠르게 바뀌는 구간이 있다. 그런 장면을 빼거나 짧게 하고, 인물이 크고 안정된 구간을 쓴다"
        case "G8":
            let first = number(report, "G8.firstCaptionSec")
            return "훅: 첫 장면은 `hook` 이고 첫 말이 \(f(SoftGates.hookFirstCaptionSec)) 초 안에 나와야 한다. "
                + "지금 첫 장면은 `\(previous.scenes.first?.role.rawValue ?? "?")`, 첫 자막 \(f(first, 2))초. 훅 장면의 in 을 첫 말 바로 앞에 둔다"
        case "G9":
            return "정적 구간: 조용하고 화면이 거의 멈춘 구간이 \(f(number(report, "G9.longestStaticSec")))초 이어진다 "
                + "(\(f(SoftGates.maxStaticSec))초를 넘으면 안 된다). 지난 결과물 프레임과 전사의 빈 곳을 보고 그 부분을 뺀다"
        case "G11":
            let ratio = number(report, "G11.ratio") ?? 0
            return "길이: 목표 \(f(previous.meta.targetDurationSec))초의 ±\(Int(SoftGates.durationTolerance * 100))% 안이어야 하는데 "
                + "지금 \(f(previous.duration))초(\(Int((ratio * 100).rounded()))%)다. 장면을 "
                + (ratio < 1 ? "더하거나 늘려서" : "빼거나 줄여서") + " 맞춘다"
        case "G4", "G6":
            return "\(item): 앱이 맞추는 값이라 네가 고칠 것이 없다 — 다른 항목만 고친다"
        default:
            return item
        }
    }

    /// 지난 편집안에서 AI 가 쓰지 않는 칸을 뺀다 (`MadiTools.appFilledKeys` + 자막 · 화면 잡기 · 원본 id).
    static func previousJSON(_ comp: Composition) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(comp),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "{}" }
        for key in MadiTools.appFilledKeys + ["size", "fps"] { dict[key] = nil }
        if var scenes = dict["scenes"] as? [[String: Any]] {
            for i in scenes.indices {
                scenes[i]["captions"] = nil
                scenes[i]["reframe"] = nil
                if var src = scenes[i]["source"] as? [String: Any] { src["videoId"] = nil; scenes[i]["source"] = src }
            }
            dict["scenes"] = scenes
        }
        let out = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: out, as: UTF8.self)
    }
}
