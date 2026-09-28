import SwiftUI
import MadiKit
import Sparkle

/// 앱 창 (6단계 — 화면을 붙였다).
///
/// 화면은 디자인 것(`Madi/UI`)을 **그대로** 올린다. 여기서는 값과 행동만 잇는다 (`AppController`).
/// 개발 쪽 뷰로 감싸거나 가운데 띄우는 틀을 만들지 않는다 — 높이가 글에 따라 바뀌는 것을 편집안 칸 가운데 두면
/// AppKit 이 제약 갱신을 무한 반복하며 멈춘다 (docs/design/decisions.md "그리다 걸린 것").
@main
struct MadiApp: App {
    @State private var controller = AppController(pipeline: MadiPipeline())
    /// 자동 업데이트 (§2 배포). 켜지면 하루 한 번 새 판을 확인한다 — 설정은 Info.plist (project.yml).
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // `Scene` 은 SwiftUI 와 `Madi/Model` 양쪽에 있다. 모델 쪽 이름은 AGENTS.md §5 가 정한 것이라
    // 바꾸지 않고, UI 코드에서 SwiftUI 쪽을 명시한다.
    var body: some SwiftUI.Scene {
        Window(Copy.Onboarding.appName, id: "main") {
            MainWindow(controller: controller)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(Copy.Update.checkForUpdates) { updater.checkForUpdates(nil) }
            }
        }

        Settings {
            SettingsScreen(values: controller.settings, onAction: { controller.handle(.settings($0)) })
        }

        Window(Copy.Onboarding.appName, id: "onboarding") {
            OnboardingWindow(state: controller.onboarding, onAction: { controller.handle(.onboarding($0)) })
        }
        .windowResizability(.contentSize)
    }
}

/// 본 창. `RootView` 에 값을 넣고 행동을 받는다 — 그 밖에는 아무것도 그리지 않는다.
private struct MainWindow: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        RootView(
            studio: controller.studio,
            gallery: controller.gallery,
            plan: controller.plan,
            planMessages: controller.planMessages,
            planChips: controller.planChips,
            results: controller.results,
            resultDetail: controller.resultDetail,
            exportTargets: controller.exportTargets,
            resultsNotice: controller.resultsNotice,
            making: controller.making,
            onAction: controller.handle
        )
        .task {
            if controller.showsOnboarding { openWindow(id: "onboarding") }
            await controller.start()
        }
        .onChange(of: controller.showsOnboarding) { _, shows in
            if !shows { dismissWindow(id: "onboarding") }
        }
        .onChange(of: controller.settingsRequest) { _, _ in openSettings() }
    }
}
