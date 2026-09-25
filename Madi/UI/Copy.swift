import Foundation

/// **모든 UI 문구는 여기 한 파일에.** 하드코딩 금지 (AGENTS.md §14).
///
/// 말투 규칙 (`§1-5`, `§1-6`):
/// - 전문 용어 금지. "인코딩"→"만드는 중", "컴포지션"→"편집안", "리프레임"→"화면 잡기"
/// - 오류는 알림창이 아니라 채팅 안에 **AI 말투**로
/// - 붉은색은 진짜 실패에만
///
/// ⚠ 아래 문구는 **자리만 잡아 둔 것**이다. 최종안은 디자인 쪽에서 정한다
///   (`docs/prompts/design.md`). 코드가 문구를 정하지 않는다.
public enum Copy {

    /// 품질 게이트가 결과를 막지 않는 경우들. `AGENTS.md §8`.
    ///
    /// 셋 다 self-eval 로 되돌리지 않고 결과를 보여준다. 이유만 다르다.
    public enum GateNotice {

        /// `원본 한계` — 최대 배율까지 확대해도 인물이 목표만큼 안 커지는 경우.
        ///
        /// 고칠 방법이 없으므로 다음에 찍을 때를 위한 조언을 붙인다.
        /// - Parameter canSuggestResolution: 해상도를 올리면 여지가 생기는 경우에만 true.
        ///   (1080p 로 멀리서 찍으면 확대 여력이 없다 —
        ///   `docs/findings/2026-09-25-zoom-design.md §2`)
        public static func subjectTooSmall(canSuggestResolution: Bool) -> String {
            let base = "인물이 좀 작게 잡혔어요. 다음엔 조금 더 가까이서 찍으면 크게 나와요."
            guard canSuggestResolution else { return base }
            // ⚠ 문구 자리. 디자인 확정 전이다.
            return base + " 4K 로 찍으면 더 크게 잡을 수 있어요."
        }

        /// `판정 불가` — 사람을 못 찾은 구간이 너무 많은 경우.
        public static let subjectNotFound =
            "화면에서 사람을 찾기 어려운 구간이 많았어요. "
            + "배경이 단순한 곳에서 찍으면 더 잘 잡혀요."
    }
}
