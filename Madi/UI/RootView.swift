import SwiftUI

/// 앱 창 하나. 사이드바 + 고른 칸의 화면.
///
/// **로직이 없다.** 상태는 전부 밖에서 주입한 값이고, 사람이 한 일은 **`onAction` 하나로**
/// 밖에 나간다 (viewdata-map 3절 ⑦). 무엇을 할지는 바꾸는 층이 정한다.
///
/// 이 뷰가 스스로 하는 것은 **어느 칸을 보여 줄지(길 찾기)** 뿐이다 — 사이드바 칸, 편집안을 열었는지.
/// 그것도 행동을 먼저 내보낸 **다음에** 바꾼다. 바꾸는 층은 받은 행동으로 필요한 값을 채운다:
/// - `.gallery(.makeShort(id))` → 그 촬영본의 `plan` · `planMessages` 를 넣는다
/// - 편집안을 닫게 하려면 `plan` 을 nil 로 — 편집안 화면은 `plan` 이 있을 때만 선다
///
/// 창이 하나인 이유: 촬영본 → 편집안 → 결과물이 한 줄기라 창을 나누면 왔다 갔다 하게 된다.
struct RootView: View {
    var studio: StudioStatus
    var gallery: GalleryState

    /// 편집안 화면에 넣을 것. **지금 열린 촬영본의 것**이다 (`.gallery(.makeShort)` 로 무엇을 열었는지 안다).
    /// nil 이면 편집안 화면이 닫힌다.
    var plan: PlanState?
    var planMessages: [ChatMessage] = []
    var planChips: [String] = []
    /// 연 촬영본의 제목 (편집안이 아직 없을 때도 제목 줄에 쓴다).
    var planTitle: String = ""

    var results: ResultsState = .empty
    var resultDetail: ResultDetail?
    var exportTargets: [ExportTarget] = []
    var resultsNotice: ScreenNotice?
    var making: MakingState = .empty

    /// 사람이 한 일. **화면에서 나가는 것은 이것 하나다.**
    var onAction: (UIAction) -> Void = { _ in }

    /// 프리뷰 · 스크린샷용 초기 상태.
    var selectedShotID: ShotItem.ID?
    var galleryNotice: String?
    var gallerySearch: String?
    var galleryFilter: GalleryFilter?
    var opensPlan = false
    var selectedSceneID: SceneCardItem.ID?
    var editingSceneID: SceneCardItem.ID?
    var selectedResultID: ResultRef.ID?
    var showsExportSheet = false
    var showsTrashConfirm = false
    /// 열자마자 고를 사이드바 칸.
    var section: LibrarySection = .shots

    @State private var selection: LibrarySection?
    /// 편집안을 열었는지. `NavigationStack` 을 쓰지 않는 이유는 그러면 뒤로 가기 버튼이
    /// **둘**이 되기 때문이다 — 시스템이 하나(화살표만) 놓고, 우리가 "촬영본" 이라고
    /// 적힌 것을 하나 더 놓게 된다. 창이 하나이고 갈 곳도 하나라 상태 하나로 충분하다.
    @State private var showsPlan = false
    /// 다른 칸에서 결과물 칸으로 넘어올 때 골라서 열 결과물 (편집안 툴바 · 채팅 · 만드는 중에서 연 것).
    @State private var openingResultID: ResultRef.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView(studio: studio, selection: $selection) { send(.openSettings) }
        } detail: {
            if showsPlan, plan != nil {
                planScreen
            } else {
                detail
            }
        }
        .frame(
            minWidth: Tokens.Size.windowMin.width,
            minHeight: Tokens.Size.windowMin.height
        )
        .tint(Tokens.Palette.accent)
        .onAppear {
            if selection == nil { selection = section }
            if opensPlan, plan != nil { showsPlan = true }
        }
        // 편집안은 촬영본 칸 안의 화면이다. 사이드바에서 다른 칸을 고르면 편집안을 닫고 그 칸으로 간다 —
        // 전에는 사이드바 선택만 바뀌고 본문은 편집안 그대로였다 (2026-09-30 실제 앱)
        .onChange(of: selection) { _, new in
            if showsPlan, new != .shots {
                showsPlan = false
                onAction(.plan(.close))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .shots, nil:
            GalleryScreen(
                state: gallery, studio: studio,
                onAction: { send(.gallery($0)) },
                initialSelection: selectedShotID,
                notice: galleryNotice,
                initialQuery: gallerySearch,
                initialFilter: galleryFilter
            )
        case .results:
            ResultsScreen(
                state: results,
                detail: resultDetail,
                exportTargets: exportTargets,
                notice: resultsNotice,
                onAction: { send(.results($0)) },
                initialSelection: openingResultID ?? selectedResultID,
                showsExportSheet: showsExportSheet,
                showsTrashConfirm: showsTrashConfirm
            )
        case .making:
            MakingScreen(state: making) { send(.making($0)) }
        }
    }

    @ViewBuilder
    private var planScreen: some View {
        if let plan {
            PlanScreen(
                state: plan,
                messages: planMessages,
                chips: planChips,
                shotTitle: planTitle,
                onAction: send,
                initialSceneID: selectedSceneID,
                initialEditingID: editingSceneID
            )
        }
    }

    /// 행동을 **먼저 내보내고**, 그다음 이 창 안에서 갈 곳만 바꾼다.
    private func send(_ action: UIAction) {
        onAction(action)
        switch action {
        case .gallery(.makeShort):
            showsPlan = true
        case .plan(.close):
            showsPlan = false
        case .plan(.openResults(let id)):
            openingResultID = id
            showsPlan = false
            selection = .results
        case .chat(.openResult(let id)), .making(.openResult(let id)):
            openingResultID = id
            showsPlan = false
            selection = .results
        case .results(.openPlan):
            selection = .shots
            showsPlan = true
        case .results(.showShots):
            selection = .shots
        default:
            break
        }
    }
}

#Preview("창 · 1440×900") {
    RootView(studio: SampleData.studio, gallery: .loaded(SampleData.groups))
        .frame(width: 1440, height: 900)
}

#Preview("창 · 1100×700") {
    RootView(studio: SampleData.studio, gallery: .loaded(SampleData.groups))
        .frame(width: 1100, height: 700)
}

#Preview("창 · 편집안") {
    RootView(
        studio: SampleData.studio,
        gallery: .loaded(SampleData.groups),
        plan: .ready(SampleData.plan),
        planMessages: SampleData.chat,
        planChips: SampleData.chatChips,
        opensPlan: true,
        selectedSceneID: "s4"
    )
    .frame(width: 1440, height: 900)
}
