import Foundation

/// AI 한 턴의 프롬프트 (AGENTS.md §10 컨텍스트 조립 순서):
///
/// ```
/// 1. 제작 지침 (playbook)     — 숏폼 편집 일반 규칙. 고정
/// 2. 템플릿 Spec.json         — 쓸 수 있는 role · slot · overlay 와 payload 스키마
/// 3. 품질 게이트 요약 (§8)     — 지켜야 할 수치
/// 4. 사용자 규칙 (설정에서 직접 쓴 것)
/// 5. digest                   — read_digest 로 읽는다 (여기에는 영상 id 만)
/// 6. 대화 이력 / 수정 요청
/// ```
/// 세기 순서: 사용자 규칙 > 템플릿 Spec > 품질 게이트 > 제작 지침 — 프롬프트 맨 위에 적는다.
public enum PromptAssembler {

    public struct Turn: Sendable, Equatable {
        public enum Speaker: String, Sendable { case creator, assistant }
        public var speaker: Speaker
        public var text: String
        public init(_ speaker: Speaker, _ text: String) { self.speaker = speaker; self.text = text }
    }

    /// 첫 진입 요청 (§10 — 다이제스트 → AI 1턴 → 편집안 초안).
    public static let firstDraftRequest = "이 영상으로 편집안 초안을 만든다."

    public static func assemble(
        videoID: String, userRules: [String] = [], history: [Turn] = [], request: String = firstDraftRequest
    ) throws -> String {
        let rules = userRules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var out: [String] = []
        out.append("""
        규칙이 서로 부딪히면 이 순서로 따른다: 4. 크리에이터 규칙 > 2. 템플릿 Spec > 3. 품질 기준 > 1. 제작 지침.
        """)
        out.append("# 1. 제작 지침\n\n" + (try resource("playbook", "md")).trimmingCharacters(in: .whitespacesAndNewlines))
        out.append("# 2. 템플릿이 지원하는 것 (Spec.json)\n\n여기 있는 이름만 쓴다.\n\n```json\n"
                   + (try resource("Spec", "json")).trimmingCharacters(in: .whitespacesAndNewlines) + "\n```")
        out.append("# 3. 품질 기준\n\n" + gateSummary)
        out.append("# 4. 크리에이터 규칙\n\n" + (rules.isEmpty ? "(아직 없음)" : rules.map { "- " + $0 }.joined(separator: "\n")))
        out.append("# 5. 영상\n\nvideoId: `\(videoID)` — `read_digest` 로 읽는다. 다른 영상은 없다.")
        var talk = history.map { "\($0.speaker == .creator ? "크리에이터" : "너"): \($0.text)" }
        talk.append("크리에이터: \(request)")
        out.append("# 6. 대화\n\n" + talk.joined(separator: "\n"))
        return out.joined(separator: "\n\n---\n\n") + "\n"
    }

    /// `§8` 중 **AI 의 선택이 좌우하는 것**만. 자막 크기 · 분절 · 싱크 · 가림은 앱이 맞춘다.
    static let gateSummary = """
    결과물은 앱이 재서 판정한다. 네 선택이 좌우하는 것:

    - 인물 크기: 인물 높이가 화면 높이의 55% 이상인 구간이 전체의 80% 이상. 화면 잡기가 맞추지만, \
    원본에서 인물이 멀고 작은 구간보다 가까운 구간을 고르면 더 잘 맞는다
    - 훅: 첫 장면이 `hook` 이고 첫 자막이 0.5초 안에 시작한다
    - 정적 구간: 조용하고 움직임 없는 구간이 1.2초 넘게 이어지지 않는다
    - 컷 리듬: 장면 길이 중앙값 1.5~4.0초
    - 길이: `meta.targetDurationSec` 의 ±15% 안
    - 자막 크기 · 분절 · 싱크 · 가림 · 위치 값은 앱이 맞춘다. 너는 `captionSlot` 만 고른다
    """

    static func resource(_ name: String, _ ext: String) throws -> String {
        guard let url = Bundle(for: PromptBundleToken.self).url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(ext)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// `Bundle(for:)` 로 MadiKit 프레임워크 번들을 잡기 위한 앵커.
private final class PromptBundleToken {}
