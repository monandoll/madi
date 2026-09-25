import SwiftUI

/// 앱 창 하나. 사이드바 + 고른 칸의 화면.
///
/// **로직이 없다.** 상태는 전부 밖에서 주입한 값이고, 버튼은 클로저로 나간다
/// (design-ai 지침 8). 개발이 붙을 때 이 자리에 실제 저장소를 연결한다.
struct RootView: View {
    var studio: StudioStatus
    var gallery: GalleryState
    var onOpenSettings: () -> Void = {}
    /// 프리뷰 · 스크린샷용. 열자마자 고를 촬영본.
    var selectedShotID: ShotItem.ID?
    /// 갤러리 상태줄에 한 줄 알림 (숨김 등).
    var galleryNotice: String?

    @State private var selection: LibrarySection? = .shots

    var body: some View {
        NavigationSplitView {
            SidebarView(studio: studio, selection: $selection, onOpenSettings: onOpenSettings)
        } detail: {
            switch selection {
            case .shots, nil:
                GalleryScreen(
                    state: gallery, studio: studio,
                    initialSelection: selectedShotID, notice: galleryNotice
                )
            case .results:
                ComingSoon(label: Copy.Sidebar.results)
            case .making:
                ComingSoon(label: Copy.Sidebar.making)
            }
        }
        .frame(
            minWidth: Tokens.Size.windowMin.width,
            minHeight: Tokens.Size.windowMin.height
        )
        .tint(Tokens.Palette.accent)
    }
}

/// 아직 안 그린 화면 자리. 4단계에서 결과물 · 만드는 중으로 바뀐다.
private struct ComingSoon: View {
    var label: String

    var body: some View {
        ContentUnavailableView(label, systemImage: "hammer")
            .navigationTitle(label)
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
