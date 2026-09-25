import Foundation
import SwiftUI

/// 뷰가 받는 입력. **값 타입이고 로직이 없다.**
///
/// 디자인 단계의 뷰는 이 타입들만 받는다 (design-ai 지침 8). 나중에 개발이
/// `Madi/Model` 의 `Composition` · `Digest` 를 여기로 옮겨 담는다. 그래서 여기 있는 것은
/// 저장 구조가 아니라 **화면에 보이는 것** 만이다 — 예를 들어 장면은 `source.in/out` 이 아니라
/// "몇 초짜리인지" 를 들고 있다.
///
/// 이름도 화면 말로 짓는다. `Composition` → `PlanView`, `Output` → `ResultRef`
/// (AGENTS.md §1-5 UI 에 전문 용어 금지).

// MARK: - 썸네일

/// 미리보기 그림 한 장. 디자인 단계에서는 `reference/` 프레임을 그대로 읽고,
/// 개발이 붙을 때 프록시에서 뽑은 그림 URL 로 바뀐다.
/// 없으면 뷰가 회색 자리표시로 그린다 — **비슷하게 흉내 낸 가짜 화면을 그리지 않는다**.
public struct Thumbnail: Hashable, Sendable {
    public var fileURL: URL?
    public init(fileURL: URL? = nil) { self.fileURL = fileURL }
    public static let none = Thumbnail()
}

// MARK: - 촬영본

public enum SpeechLevel: Hashable, Sendable {
    case clear, noisy, silent

    public var label: String {
        switch self {
        case .clear: Copy.Speech.clear
        case .noisy: Copy.Speech.noisy
        case .silent: Copy.Speech.silent
        }
    }
}

public enum PlatformKind: Hashable, Sendable, CaseIterable {
    case reels, shorts, tiktok

    public var label: String {
        switch self {
        case .reels: Copy.Platform.reels
        case .shorts: Copy.Platform.shorts
        case .tiktok: Copy.Platform.tiktok
        }
    }
}

/// 만들어 둔 결과물 한 편. 갤러리 정보 패널과 결과물 화면이 같이 쓴다.
public struct ResultRef: Identifiable, Hashable, Sendable {
    public var id: String
    public var platform: PlatformKind
    /// `편집안 2` 처럼 어느 편집안에서 나왔는지. 사람은 이걸로 "그 버전" 을 찾는다.
    public var planLabel: String
    public var when: String
    public var duration: Double
    public var sceneCount: Int
    public var isNew: Bool
    public var thumbnail: Thumbnail

    public init(
        id: String, platform: PlatformKind, planLabel: String, when: String,
        duration: Double, sceneCount: Int, isNew: Bool = false,
        thumbnail: Thumbnail = .none
    ) {
        self.id = id; self.platform = platform; self.planLabel = planLabel
        self.when = when; self.duration = duration; self.sceneCount = sceneCount
        self.isNew = isNew; self.thumbnail = thumbnail
    }
}

/// 갤러리 한 칸. 아이폰으로 찍어 iCloud 사진으로 들어온 원본 하나.
public struct ShotItem: Identifiable, Hashable, Sendable {
    public var id: String
    /// 말소리에서 뽑은 제목. 없으면 빈 문자열이고 뷰가 날짜로 대신 보여준다.
    public var title: String
    public var shotAt: Date
    public var duration: Double
    public var speech: SpeechLevel
    /// 지금 이 촬영본으로 영상을 만들고 있는 중인지.
    public var isMaking: Bool
    public var thumbnail: Thumbnail
    public var results: [ResultRef]

    public init(
        id: String, title: String, shotAt: Date, duration: Double,
        speech: SpeechLevel = .clear, isMaking: Bool = false,
        thumbnail: Thumbnail = .none, results: [ResultRef] = []
    ) {
        self.id = id; self.title = title; self.shotAt = shotAt; self.duration = duration
        self.speech = speech; self.isMaking = isMaking
        self.thumbnail = thumbnail; self.results = results
    }

    public var hasResult: Bool { !results.isEmpty }
}

/// 날짜 묶음. 사진 앱처럼 "오늘 · 이번 주 · 지난주" 로 끊는다.
public struct ShotGroup: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    /// `9월 25일` · `9월 21–23일`. 날짜 계산은 개발이 하고 뷰는 받은 문자열만 그린다.
    public var subtitle: String
    public var shots: [ShotItem]

    public init(title: String, subtitle: String, shots: [ShotItem]) {
        self.title = title; self.subtitle = subtitle; self.shots = shots
    }
}

/// 갤러리가 지금 무엇을 보여줄 상태인지. 빈 상태 · 가져오는 중 · 정상 · 실패.
public enum GalleryState: Hashable, Sendable {
    case loading
    case empty
    /// iCloud 사진에서 받아오는 중. 이미 받은 것은 같이 보여준다.
    case importing(done: Int, total: Int, groups: [ShotGroup])
    case loaded([ShotGroup])
    /// 사진 보관함을 못 읽는 상태. 오류창을 띄우지 않고 화면 안에서 다음 행동을 준다.
    case noPhotoAccess

    public var groups: [ShotGroup] {
        switch self {
        case .loaded(let g): g
        case .importing(_, _, let g): g
        default: []
        }
    }
}

// MARK: - 사이드바

public enum AIConnection: Hashable, Sendable {
    case claude, codex, none

    public var label: String {
        switch self {
        case .claude: Copy.Sidebar.aiConnected
        case .codex: Copy.Sidebar.aiConnectedCodex
        case .none: Copy.Sidebar.aiDisconnected
        }
    }

    public var isConnected: Bool { self != .none }
}

/// 사이드바가 고르는 칸.
public enum LibrarySection: Hashable, Sendable, CaseIterable, Identifiable {
    case shots, results, making

    public var id: Self { self }

    public var label: String {
        switch self {
        case .shots: Copy.Sidebar.shots
        case .results: Copy.Sidebar.results
        case .making: Copy.Sidebar.making
        }
    }

    /// SF Symbols. 시스템 아이콘만 쓴다 — 커스텀 아이콘 세트를 만들지 않는다.
    public var symbol: String {
        switch self {
        case .shots: "video"
        case .results: "square.and.arrow.up.on.square"
        case .making: "clock"
        }
    }
}

/// 사이드바 푸터 + 배지에 필요한 것.
public struct StudioStatus: Hashable, Sendable {
    /// 설정값이다. 코드에 박지 않는다 (AGENTS.md §1-7).
    public var studioName: String
    public var ai: AIConnection
    public var shotCount: Int
    public var resultCount: Int
    public var makingCount: Int

    public init(
        studioName: String, ai: AIConnection,
        shotCount: Int, resultCount: Int, makingCount: Int
    ) {
        self.studioName = studioName; self.ai = ai
        self.shotCount = shotCount; self.resultCount = resultCount
        self.makingCount = makingCount
    }

    public func count(for section: LibrarySection) -> Int {
        switch section {
        case .shots: shotCount
        case .results: resultCount
        case .making: makingCount
        }
    }
}

// MARK: - 편집안

/// 자막 블록을 어디에 놓을지. **영상마다 하나다** — 장면마다 따로 고르지 않는다
/// (`AGENTS.md §5` `Composition.captionSlot`).
///
/// 이름이 위치어가 아니라 **내용어**인 이유: 자막 자리는 "빈 곳" 으로 정해지지 않는다.
/// 피사체를 피해 올라간다는 가설을 10편으로 검증했고 **기각됐다**
/// (`docs/findings/2026-09-25-caption-position-rule-test.md` — 실제로는 자막이
/// 피사체 위에 얹혀 있었다). 정해지는 기준은 **그 영상이 주로 보여주는 몸의 범위**다.
/// 좌표는 스타일이 갖는다 (`§9`).
public enum CaptionSlot: Hashable, Sendable, CaseIterable {
    case upperBody, fullBody, lowerBody

    public var label: String {
        switch self {
        case .upperBody: Copy.Plan.Caption.upperBody
        case .fullBody: Copy.Plan.Caption.fullBody
        case .lowerBody: Copy.Plan.Caption.lowerBody
        }
    }
}

public enum SceneRoleKind: Hashable, Sendable, CaseIterable {
    case hook, demo, explain, cta, filler

    public var label: String {
        switch self {
        case .hook: Copy.Role.hook
        case .demo: Copy.Role.demo
        case .explain: Copy.Role.explain
        case .cta: Copy.Role.cta
        case .filler: Copy.Role.filler
        }
    }

    public var tint: Color {
        switch self {
        case .hook: Tokens.RoleTint.hook
        case .demo: Tokens.RoleTint.demo
        case .explain: Tokens.RoleTint.explain
        case .cta: Tokens.RoleTint.cta
        case .filler: Tokens.RoleTint.filler
        }
    }
}

/// 장면 카드 하나. 사람이 "틀린 곳을 짚을" 단위다 (AGENTS.md §1-3).
///
/// `Scene` 과 달리 원본 구간(`in`/`out`)을 들고 있지 않다. 화면에 안 나오기 때문이다.
/// 나오는 것은 **몇 번째인지 · 무슨 역할인지 · 뭐라고 말하는지 · 몇 초인지** 넷이다.
public struct SceneCardItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var number: Int
    public var role: SceneRoleKind
    /// 이 장면의 첫 자막 덩어리. 접힌 줄에는 이것만 보인다.
    public var caption: String
    public var secondary: String?
    /// 나머지 덩어리. 줄을 고르면 펼쳐진다.
    public var moreCaptions: [String]
    public var duration: Double
    public var thumbnail: Thumbnail
    /// 이 장면 **뒤에** 뺀 쉬는 구간. 되돌릴 수 있어야 하므로 화면에 남긴다.
    public var removedGapAfter: Double?

    public init(
        id: String, number: Int, role: SceneRoleKind, caption: String,
        secondary: String? = nil, moreCaptions: [String] = [], duration: Double,
        thumbnail: Thumbnail = .none, removedGapAfter: Double? = nil
    ) {
        self.id = id; self.number = number; self.role = role; self.caption = caption
        self.secondary = secondary; self.moreCaptions = moreCaptions
        self.duration = duration; self.thumbnail = thumbnail
        self.removedGapAfter = removedGapAfter
    }

    public var captionCount: Int { caption.isEmpty ? 0 : 1 + moreCaptions.count }
}

/// 편집안 하나. 화면에 보이는 것만 들고 있다.
public struct PlanView: Identifiable, Hashable, Sendable {
    public var id: String
    public var shotID: String
    public var shotTitle: String
    public var platform: PlatformKind
    /// `편집안 2`. 고칠 때마다 새로 생기므로 (AGENTS.md §10 `revisionOf`) 번호가 는다.
    public var versionLabel: String
    public var versionCount: Int
    public var sourceDuration: Double
    public var targetDuration: Double
    public var captionSlot: CaptionSlot
    public var scenes: [SceneCardItem]
    public var resultCount: Int

    public init(
        id: String, shotID: String, shotTitle: String, platform: PlatformKind,
        versionLabel: String, versionCount: Int,
        sourceDuration: Double, targetDuration: Double,
        captionSlot: CaptionSlot,
        scenes: [SceneCardItem], resultCount: Int
    ) {
        self.id = id; self.shotID = shotID; self.shotTitle = shotTitle
        self.platform = platform; self.versionLabel = versionLabel
        self.versionCount = versionCount
        self.sourceDuration = sourceDuration; self.targetDuration = targetDuration
        self.captionSlot = captionSlot
        self.scenes = scenes; self.resultCount = resultCount
    }

    public var removedGapCount: Int { scenes.filter { $0.removedGapAfter != nil }.count }
    public var removedGapSeconds: Double { scenes.compactMap(\.removedGapAfter).reduce(0, +) }
}

/// 편집안을 짜는 동안 보여주는 단계. 퍼센트 하나보다 "지금 뭘 하는지" 가 안심이 된다.
public struct PrepareStep: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case done, running, waiting
    }

    public var id: String { title }
    public var title: String
    public var state: State
    /// `20초쯤 남음`. 없으면 안 보여준다 — 틀린 숫자를 보여주느니 없는 게 낫다.
    public var remaining: String?

    public init(title: String, state: State, remaining: String? = nil) {
        self.title = title; self.state = state; self.remaining = remaining
    }
}

/// 영상을 만드는 중. `만들기` 를 눌러도 **화면을 떠나지 않는다** — 같은 자리에서 진행을 본다.
public struct MakingProgress: Hashable, Sendable {
    public var fraction: Double
    public var steps: [PrepareStep]
    /// `약 1분 남았어요`. 모르면 비운다.
    public var remaining: String?

    public init(fraction: Double, steps: [PrepareStep], remaining: String? = nil) {
        self.fraction = fraction; self.steps = steps; self.remaining = remaining
    }
}

/// 편집안 화면이 지금 무엇을 보여줄 상태인지.
public enum PlanState: Hashable, Sendable {
    /// AI 가 살펴보고 장면을 나누는 중.
    case preparing([PrepareStep])
    case ready(PlanView)
    /// 영상을 만드는 중. 장면 목록은 그대로 보이되 읽기 전용이다.
    case making(PlanView, MakingProgress)
    /// AI 가 연결돼 있지 않다. **오류가 아니다** — 한 줄만 말한다 (AGENTS.md §10).
    case noAI

    public var plan: PlanView? {
        switch self {
        case .ready(let plan), .making(let plan, _): plan
        default: nil
        }
    }
}

// MARK: - 대화

/// 채팅 한 줄. 오류도 여기로 들어온다 (AGENTS.md §1-6 오류는 채팅 안에 AI 말투로).
public struct ChatMessage: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case user(String)
        case assistant(String)
        /// 무엇이 바뀌었는지 표로. 숫자를 말로 풀어 쓰는 것보다 짧다.
        case summary(EditSummary)
        /// 다음 행동 버튼. 막혔을 때 **항상** 같이 준다.
        case choices([ChatChoice])
        /// 다 만든 영상. 만들기가 끝나면 대화에 카드로 붙는다.
        case result(ResultRef)
        /// AI 가 지금 쓰고 있는 중.
        case typing
    }

    public var id: String
    public var kind: Kind
    /// `오늘 오후 2:20`. 묶음 첫 줄에만 보여준다.
    public var stamp: String?

    public init(id: String, kind: Kind, stamp: String? = nil) {
        self.id = id; self.kind = kind; self.stamp = stamp
    }
}

public struct EditSummary: Hashable, Sendable {
    public struct Line: Identifiable, Hashable, Sendable {
        public var id: String { label }
        public var label: String
        public var value: String
        public init(label: String, value: String) { self.label = label; self.value = value }
    }

    public var lines: [Line]
    /// `되돌리기` 를 줄지. 결과물이 이미 나온 편집안은 제자리에서 고치지 않는다 (§1-8).
    public var canUndo: Bool

    public init(lines: [Line], canUndo: Bool = true) {
        self.lines = lines; self.canUndo = canUndo
    }
}

public struct ChatChoice: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    /// 왜 이걸 고르는지 한 줄. 버튼만 있으면 무엇이 다른지 모른다.
    public var detail: String?
    public var isPrimary: Bool

    public init(title: String, detail: String? = nil, isPrimary: Bool = false) {
        self.title = title; self.detail = detail; self.isPrimary = isPrimary
    }
}
