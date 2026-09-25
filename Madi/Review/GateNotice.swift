import Foundation

/// 품질 게이트가 사용자에게 알려야 하는 것. **문구가 아니라 키다.**
///
/// ★ `Madi/UI/Copy.swift` 는 디자인 쪽이 소유한다. 여기서는 **무엇을 알릴지**만 정하고
///   실제 문장은 UI 가 채운다. 리뷰 로직이 문구를 들고 있으면 말투를 고칠 때마다
///   게이트 코드를 건드려야 한다.
///
/// 필요한 문구 키 목록은 `docs/design/copy-keys.md` 에 있다.
public enum GateNotice: String, Codable, Hashable, Sendable, CaseIterable {

    /// `원본 한계` — 최대 허용 배율까지 확대해도 인물이 목표만큼 안 커진다 (`AGENTS.md §8`).
    /// 고칠 방법이 없으므로 다음 촬영을 위한 조언을 붙인다.
    case subjectTooSmall

    /// 위와 같은데 **원본 해상도를 올리면 여지가 생기는** 경우.
    /// 1080p 로 멀리서 찍으면 확대 여력이 없다
    /// (`docs/findings/2026-09-25-zoom-design.md §2`).
    case subjectTooSmallLowResolution

    /// `판정 불가` — 사람을 못 찾은 구간이 영상 길이의 20% 를 넘는다.
    case subjectNotFound
}

/// 게이트 하나의 판정. **통과·실패만으로는 부족하다** (`AGENTS.md §8`).
public enum GateResult: Hashable, Sendable {
    case pass
    /// 고칠 수 있는데 못 맞췄다. self-eval 로 되돌린다.
    case fail
    /// 측정할 수 없었다. 되돌리지 않고 사용자에게 보여준다.
    case cannotJudge(GateNotice)
    /// 원본이 이미 한계다. 되돌리지 않고 사용자에게 보여준다.
    case sourceLimited(GateNotice)

    /// self-eval 로 되돌릴지. `fail` 만 되돌린다.
    public var shouldRetry: Bool {
        if case .fail = self { return true }
        return false
    }

    /// 사용자에게 붙일 안내. 없으면 조용히 지나간다.
    public var notice: GateNotice? {
        switch self {
        case .cannotJudge(let n), .sourceLimited(let n): n
        case .pass, .fail: nil
        }
    }
}
