import SwiftUI

/// 앱 창 하나. 사이드바 + 고른 칸의 화면.
///
/// **로직이 없다.** 상태는 전부 밖에서 주입한 값이고, 버튼은 클로저로 나간다
/// (design-ai 지침 8). 개발이 붙을 때 이 자리에 실제 저장소를 연결한다.
///
/// 창이 하나인 이유: 촬영본 → 편집안 → 결과물이 한 줄기라 창을 나누면 왔다 갔다 하게 된다.
/// 편집안은 **같은 칸 안에서** 열린다 (`NavigationStack`).
struct RootView: View {
    var studio: StudioStatus
    var gallery: GalleryState
    var onOpenSettings: () -> Void = {}

    /// 편집안 화면에 넣을 것. 없으면 갤러리에서 `숏폼 만들기` 를 눌러도 열 게 없다.
    var plan: PlanState?
    var planMessages: [ChatMessage] = []
    var planChips: [String] = []

    var results: ResultsState = .empty
    var resultDetail: ResultDetail?
    var exportTargets: [ExportTarget] = []
    var resultsNotice: ScreenNotice?
    var making: MakingState = .empty

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

    var body: some View {
        NavigationSplitView {
            SidebarView(studio: studio, selection: $selection, onOpenSettings: onOpenSettings)
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
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .shots, nil:
            GalleryScreen(
                state: gallery, studio: studio,
                // 촬영본에서 나가는 길은 하나다. 누르면 편집안이 열리고 AI 가 초안을 짠다.
                onMakeShort: { _ in showsPlan = true },
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
                initialSelection: selectedResultID,
                showsExportSheet: showsExportSheet,
                showsTrashConfirm: showsTrashConfirm
            )
        case .making:
            MakingScreen(state: making)
        }
    }

    @ViewBuilder
    private var planScreen: some View {
        if let plan {
            PlanScreen(
                state: plan,
                messages: planMessages,
                chips: planChips,
                onBack: { showsPlan = false },
                initialSceneID: selectedSceneID,
                initialEditingID: editingSceneID
            )
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
