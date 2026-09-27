import SwiftUI

/// 설정. macOS 규칙대로 **`Settings` 씬 + `Form`** 이다 (⌘,).
/// 앱 창 안에 칸으로 두지 않는다 — 같은 것이 두 군데가 된다.
///
/// 여기 있는 것은 첫 실행에서 물은 셋과 촬영본 보관뿐이다.
/// 스타일 값(글자 크기 · 외곽선 · 자막 자리)은 **설정에 없다.** 크리에이터가 "외곽선 7px" 을
/// 알 리 없고, 그건 측정해서 정하는 값이다 (`AGENTS.md §9`).
struct SettingsScreen: View {
    var values: SettingsValues
    var isLoading = false

    var onConnect: (AIConnection) -> Void = { _ in }
    var onDisconnect: () -> Void = {}
    var onPickActive: (AIConnection) -> Void = { _ in }
    var onStudioName: (String) -> Void = { _ in }
    var onKeepDays: (Int) -> Void = { _ in }
    var onPickAlbum: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}

    @State private var studioName: String = ""
    @State private var keepDays: Int = 90
    @State private var activeAI: AIConnection = .claude

    var body: some View {
        Form {
            aiSection
            studioSection
            shotsSection
        }
        .formStyle(.grouped)
        // 설정 창 크기. 세 묶음이 스크롤 없이 다 들어가는 높이다.
        .frame(width: 520, height: 520)
        .tint(Tokens.Palette.accent)
        .onAppear {
            studioName = values.studioName
            keepDays = values.keepDays
            activeAI = values.activeAI
        }
    }

    // MARK: - AI

    @ViewBuilder
    private var aiSection: some View {
        Section(Copy.Settings.AI.header) {
            if isLoading {
                HStack(spacing: Tokens.Space.inner) {
                    ProgressView().controlSize(.small)
                    Text(Copy.Settings.loading)
                        .foregroundStyle(.secondary)
                }
            } else {
                switch values.ai {
                case .connected(let ai, let account):
                    LabeledContent {
                        HStack(spacing: Tokens.Space.inner) {
                            Label(Copy.Settings.AI.connected, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Tokens.Palette.ok)
                                .labelStyle(.titleAndIcon)
                                .font(.callout)
                            Button(Copy.Settings.AI.disconnect, action: onDisconnect)
                        }
                    } label: {
                        Text(name(ai))
                        Text(account)
                    }
                default:
                    // **오류가 아니다.** 붉은색을 쓰지 않는다 (AGENTS.md §1-6).
                    LabeledContent {
                        Button(Copy.Settings.AI.connect) { onConnect(activeAI) }
                            .buttonStyle(.borderedProminent)
                    } label: {
                        Text(Copy.Settings.AI.notConnected)
                        Text(Copy.Onboarding.AI.needed)
                    }
                }

                Picker(Copy.Settings.AI.active, selection: $activeAI) {
                    Text(Copy.Onboarding.AI.claude).tag(AIConnection.claude)
                    Text(Copy.Onboarding.AI.codex).tag(AIConnection.codex)
                }
                .onChange(of: activeAI) { _, new in onPickActive(new) }
                Text(Copy.Settings.AI.activeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 스튜디오

    private var studioSection: some View {
        Section(Copy.Settings.Studio.header) {
            LabeledContent(Copy.Settings.Studio.name) {
                TextField("", text: $studioName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: studioName) { _, new in onStudioName(new) }
            }
            Text(Copy.Settings.Studio.nameHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 촬영본

    private var shotsSection: some View {
        Section(Copy.Settings.Shots.header) {
            Picker(Copy.Settings.Shots.keep, selection: $keepDays) {
                ForEach([30, 60, 90, 180], id: \.self) { days in
                    Text(Copy.Settings.Shots.days(days)).tag(days)
                }
                Text(Copy.Settings.Shots.forever).tag(0)
            }
            .onChange(of: keepDays) { _, new in onKeepDays(new) }
            Text(Copy.Settings.Shots.keepHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(Copy.Settings.Shots.album) {
                HStack(spacing: Tokens.Space.inner) {
                    Text(values.albumName ?? Copy.Settings.Shots.albumAll)
                        .foregroundStyle(.secondary)
                    Button(Copy.Settings.Shots.pickAlbum, action: onPickAlbum)
                }
            }

            LabeledContent(Copy.Settings.Shots.photoAccess) {
                switch values.photos {
                case .granted:
                    Label(Copy.Settings.Shots.photoAccessOn, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Tokens.Palette.ok)
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                default:
                    HStack(spacing: Tokens.Space.inner) {
                        Text(Copy.Settings.Shots.photoAccessOff)
                            .foregroundStyle(.secondary)
                        Button(Copy.Onboarding.Photos.openSystemSettings,
                               action: onOpenSystemSettings)
                    }
                }
            }
        }
    }

    private func name(_ ai: AIConnection) -> String {
        ai == .codex ? Copy.Onboarding.AI.codex : Copy.Onboarding.AI.claude
    }
}

#Preview("설정 · 연결됨") {
    SettingsScreen(values: SampleData.settings)
}

#Preview("설정 · 연결 안 됨") {
    SettingsScreen(values: SampleData.settingsDisconnected)
}

#Preview("설정 · 확인 중") {
    SettingsScreen(values: SampleData.settings, isLoading: true)
}
