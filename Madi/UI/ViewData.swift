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
