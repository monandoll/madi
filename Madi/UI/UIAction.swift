import Foundation

/// 사람이 화면에서 한 일. **화면이 밖으로 내보내는 것은 이것 하나다.**
///
/// 뷰는 로직이 없다 (design-ai 지침 8). 누른 것은 값으로 만들어 `onAction` 으로 내보내고,
/// 무엇을 할지는 바꾸는 층(`Madi/App/Bridge`)이 정한다. 입구가 하나라야 앱에 붙였을 때
/// "보기만 되는" 화면이 되지 않는다 (docs/design/viewdata-map.md 3절 ⑦).
///
/// 화면별로 묶었다. 바꾸는 층은 `switch action { case .plan(let a): … }` 로 받는다.
/// 모든 값에 **무엇에 대한 일인지**(촬영본 · 장면 · 결과물 id)가 들어 있다 — 화면이 기억하는 선택에
/// 기대지 않는다.
public enum UIAction: Hashable, Sendable {
    case gallery(Gallery)
    case plan(Plan)
    case chat(Chat)
    case scene(SceneCardItem.ID, Scene)
    case results(Results)
    case making(Making)
    case onboarding(Onboarding)
    case settings(Settings)
    /// 사이드바 스튜디오 줄 · 막힌 상태의 "설정 열기".
    case openSettings

    public enum Gallery: Hashable, Sendable {
        /// `숏폼 만들기`. 편집안 화면이 열리고 AI 가 초안을 짠다.
        case makeShort(ShotItem.ID)
        case play(ShotItem.ID)
        case revealInPhotos(ShotItem.ID)
        /// 목록에서 숨기기. 사진 앱 원본은 그대로다.
        case hide(ShotItem.ID)
        case undoHide
        /// 받기 실패한 촬영본을 다시 가져온다.
        case retryImport(ShotItem.ID)
        case addFromMac
        case openSystemSettings
    }

    public enum Plan: Hashable, Sendable {
        /// 갤러리로 돌아간다. 바꾸는 층은 이때 보던 편집안을 내려놓는다.
        case close
        /// 영상 만들기. 장면 카드를 본 뒤에만 누를 수 있다 (`§1-3`).
        case make
        /// 짜는 중 · 만드는 중을 멈춘다.
        case stop
        case openResults
        case connectAI
        /// 로그인이 풀린 AI 에 다시 로그인한다.
        case login(AIProduct)
        case pickVersion(PlanVersion.ID)
        case play
        /// 멈춘 편집안의 다음 행동 (`PlanState.stopped`).
        case choice(ChatChoice)
        /// 장면 순서를 끌어서 바꿨다. `List.onMove` 와 같은 값이다.
        case moveScenes(from: IndexSet, to: Int)
    }

    public enum Chat: Hashable, Sendable {
        case send(String)
        case chip(String)
        case choice(ChatChoice)
        case retrySend(String)
        case playFromStart
        case undo
        case openResult(ResultRef.ID)
    }

    public enum Scene: Hashable, Sendable {
        case select
        case remove
        /// 1초 늘리기.
        case extend
        /// 1초 줄이기.
        case shorten
        case playFromHere
        case restoreGap
        /// 자막을 고쳤다. `secondary` 가 nil 이면 영문은 AI 가 다시 맞춘다.
        case editCaption(text: String, secondary: String?)
    }

    public enum Results: Hashable, Sendable {
        case openPlan(ResultRef.ID)
        case export(ResultRef.ID, ExportTarget)
        case trash(ResultRef.ID)
        case noticeChoice(ChatChoice)
        case dismissNotice
        case showShots
    }

    public enum Making: Hashable, Sendable {
        case stop(MakingJob.ID)
        case cancel(MakingJob.ID)
        case choice(MakingJob.ID, ChatChoice)
        case openResult(DoneItem.ID)
    }

    public enum Onboarding: Hashable, Sendable {
        case allowPhotos
        case openSystemSettings
        case pickAI(AIConnection)
        case login
        case cancelLogin
        case otherAccount
        case studioName(String)
        case next
        case back
        case skip
        case start
    }

    public enum Settings: Hashable, Sendable {
        case connect(AIConnection)
        case disconnect
        case login(AIProduct)
        case activeAI(AIConnection)
        case studioName(String)
        case keepDays(Int)
        case pickAlbum
        case openSystemSettings
        case look(Look)

        /// 자막 모양 (`§9`). **고르는 것만 있다** — 숫자 입력칸이 없다.
        public enum Look: Hashable, Sendable {
            /// nil 이면 앱 기본 글꼴.
            case font(String?)
            case weight(CaptionLook.Weight)
            case italic(Bool)
            case fill(CaptionLook.Swatch.ID)
            case secondaryFill(CaptionLook.Swatch.ID)
            case secondarySameAsMain(Bool)
        }
    }
}
