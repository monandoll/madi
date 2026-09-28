import SwiftUI

/// 설정. macOS 규칙대로 **`Settings` 씬** 이다 (⌘,). 앱 창 안에 칸으로 두지 않는다.
///
/// 탭이 둘이다 — **일반**(AI · 스튜디오 · 촬영본)과 **자막 모양**(`§9`).
/// 한 폼에 다 넣으면 설정 창이 화면 밖으로 길어지고, 자막 모양은 미리보기를 봐 가며 고르는 곳이라
/// 다른 설정과 섞이면 찾기 어렵다. 시스템 설정 창과 같은 탭 문법이다.
///
/// 자막 모양은 **고르는 것만** 있다 — 글꼴 · 굵기 · 기울임 · 색 견본. 크기 · 위치 칸은 없다.
/// 그건 템플릿이 정하고, 글꼴을 바꿔도 글자 높이 · 자리는 그대로다 (`§9` "템플릿과 자막 모양").
struct SettingsScreen: View {
    var values: SettingsValues
    var isLoading = false
    /// 사람이 한 일 (viewdata-map 3절 ⑦).
    var onAction: (UIAction.Settings) -> Void = { _ in }
    /// 프리뷰 · 스크린샷용.
    var initialTab: SettingsTab = .general

    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(values: values, isLoading: isLoading, onAction: onAction)
                .tabItem { Label(Copy.Settings.tabGeneral, systemImage: "gearshape") }
                .tag(SettingsTab.general)

            LookSettings(look: values.look, onAction: { onAction(.look($0)) })
                .tabItem { Label(Copy.Look.lookSectionTitle, systemImage: "textformat") }
                .tag(SettingsTab.look)
        }
        .frame(width: 540, height: 580)
        .tint(Tokens.Palette.accent)
        .onAppear { tab = initialTab }
    }
}

enum SettingsTab: Hashable {
    case general, look
}

// MARK: - 일반

private struct GeneralSettings: View {
    var values: SettingsValues
    var isLoading: Bool
    var onAction: (UIAction.Settings) -> Void

    @State private var studioName: String = ""
    @State private var keepDays: Int = 90
    @State private var activeAI: AIConnection = .claude

    var body: some View {
        Form {
            aiSection
            studioSection
            shotsSection
            if values.isSlowMac {
                // 솔직하게 알린다 — 조용히 느려지게 두지 않는다 (§17). 붉은색이 아니다.
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Copy.Machine.slowMac)
                            Text(Copy.Machine.slowMacDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tortoise")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            studioName = values.studioName
            keepDays = values.keepDays
            activeAI = values.activeAI
        }
    }

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
                            Button(Copy.Settings.AI.disconnect) { onAction(.disconnect) }
                        }
                    } label: {
                        Text(name(ai))
                        Text(account)
                    }
                case .notLoggedIn(let product):
                    // 설치는 돼 있다. 연결하기가 아니라 로그인하기다.
                    LabeledContent {
                        Button(Copy.Plan.NotLoggedIn.action) { onAction(.login(product)) }
                            .buttonStyle(.borderedProminent)
                    } label: {
                        Text(product.name)
                        Text(Copy.Plan.NotLoggedIn.title(product.name))
                    }
                default:
                    // **오류가 아니다.** 붉은색을 쓰지 않는다 (AGENTS.md §1-6).
                    LabeledContent {
                        Button(Copy.Settings.AI.connect) { onAction(.connect(activeAI)) }
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
                .onChange(of: activeAI) { _, new in onAction(.activeAI(new)) }
                Text(Copy.Settings.AI.activeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var studioSection: some View {
        Section(Copy.Settings.Studio.header) {
            LabeledContent(Copy.Settings.Studio.name) {
                TextField("", text: $studioName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: studioName) { _, new in onAction(.studioName(new)) }
            }
            Text(Copy.Settings.Studio.nameHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shotsSection: some View {
        Section(Copy.Settings.Shots.header) {
            Picker(Copy.Settings.Shots.keep, selection: $keepDays) {
                ForEach([30, 60, 90, 180], id: \.self) { days in
                    Text(Copy.Settings.Shots.days(days)).tag(days)
                }
                Text(Copy.Settings.Shots.forever).tag(0)
            }
            .onChange(of: keepDays) { _, new in onAction(.keepDays(new)) }
            Text(Copy.Settings.Shots.keepHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(Copy.Settings.Shots.album) {
                HStack(spacing: Tokens.Space.inner) {
                    Text(values.albumName ?? Copy.Settings.Shots.albumAll)
                        .foregroundStyle(.secondary)
                    Button(Copy.Settings.Shots.pickAlbum) { onAction(.pickAlbum) }
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
                        Button(Copy.Onboarding.Photos.openSystemSettings) {
                            onAction(.openSystemSettings)
                        }
                    }
                }
            }
        }
    }

    private func name(_ ai: AIConnection) -> String {
        ai == .codex ? Copy.Onboarding.AI.codex : Copy.Onboarding.AI.claude
    }
}

// MARK: - 자막 모양

/// 자막 모양 (`§9`). 위에 미리보기, 아래에 고르는 칸.
///
/// **미리보기는 이 화면이 그리지 않는다.** 바꾸는 층이 렌더 코드(`CaptionPainter`)로 그려서
/// `CaptionLook.preview` 에 넣는다 — 레이어 트리를 만드는 함수는 하나뿐이어야 한다 (`§7`).
/// 흉내 내 그리면 설정에서 본 것과 영상에 나온 것이 달라진다.
private struct LookSettings: View {
    var look: CaptionLook?
    var onAction: (UIAction.Settings.Look) -> Void
    /// 미리보기 문장 칸 — 치는 대로 미리보기가 바뀐다 (개발이 넣음, viewdata-map ⑬).
    @State private var previewText = ""
    @State private var previewSecondaryText = ""

    var body: some View {
        if let look {
            filled(look)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func filled(_ look: CaptionLook) -> some View {
        Form {
            Section {
                preview(look)
                TextField(Copy.Look.previewTextField, text: $previewText)
                    .onChange(of: previewText) { _, t in onAction(.previewText(t)) }
                TextField(Copy.Look.previewSecondaryField, text: $previewSecondaryText)
                    .onChange(of: previewSecondaryText) { _, t in onAction(.previewSecondaryText(t)) }
            } header: {
                Text(Copy.Look.preview)
            } footer: {
                VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                    Text(Copy.Look.lookSectionDetail)
                    // 이미 만든 영상이 바뀌는 줄 알면 고르기가 무섭다. 바뀌지 않는다고 먼저 말한다.
                    Text(Copy.Look.appliesNext)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                fontRow(look)
                Picker(Copy.Look.lookWeight, selection: Binding(
                    get: { look.weight }, set: { onAction(.weight($0)) }
                )) {
                    ForEach(CaptionLook.Weight.allCases, id: \.self) { weight in
                        Text(weight.label).tag(weight)
                    }
                }
                Toggle(Copy.Look.lookItalic, isOn: Binding(
                    get: { look.italic }, set: { onAction(.italic($0)) }
                ))
            }

            Section {
                swatchRow(Copy.Look.fill, swatches: look.fills, selected: look.fill, current: look.fillColor,
                          onPick: { onAction(.fill($0)) },
                          onCustom: { onAction(.fillColor(red: $0, green: $1, blue: $2)) },
                          onSetFavorite: { onAction(.setFavorite(.main, index: $0)) })
                swatchRow(Copy.Look.secondaryFill, swatches: look.secondaryFills,
                          selected: look.secondaryFill, current: look.secondaryFillColor,
                          onPick: { onAction(.secondaryFill($0)) },
                          onCustom: { onAction(.secondaryFillColor(red: $0, green: $1, blue: $2)) },
                          onSetFavorite: { onAction(.setFavorite(.secondary, index: $0)) })
                Toggle(Copy.Look.lookSecondarySameAsMain, isOn: Binding(
                    get: { look.secondarySameAsMain }, set: { onAction(.secondarySameAsMain($0)) }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            previewText = look.previewText
            previewSecondaryText = look.previewSecondaryText
        }
    }

    /// 미리보기 — 바꾸는 층이 자막 둘레만 잘라 준 그림이다 (세로 한 장을 통째로 넣으면 납작한 칸에서 자막이 잘려 나갔다).
    private func preview(_ look: CaptionLook) -> some View {
        ThumbnailView(thumbnail: look.preview, cornerRadius: Tokens.Radius.thumbnail)
            .aspectRatio(1080.0 / 360.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black, in: .rect(cornerRadius: Tokens.Radius.thumbnail))
            .accessibilityLabel(Copy.Look.preview)
    }

    @ViewBuilder
    private func fontRow(_ look: CaptionLook) -> some View {
        Picker(Copy.Look.font, selection: Binding<String?>(
            get: { look.font }, set: { onAction(.font($0)) }
        )) {
            Text(Copy.Look.lookFontDefault).tag(String?.none)
            Divider()
            ForEach(look.fonts, id: \.self) { family in
                Text(family).tag(String?.some(family))
            }
            // 저장된 글꼴이 지워졌으면 목록에 없다. 그래도 지금 값으로 보여야 하므로 한 줄 더.
            if look.fontMissing, let missing = look.font, !look.fonts.contains(missing) {
                Text(missing).tag(String?.some(missing))
            }
        }
        if look.fontMissing {
            // 조용히 다른 글꼴로 바꾸지 않는다 (§9). 이유와 다음 행동을 같이.
            Label(Copy.Look.lookFontMissing, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Tokens.Palette.attention)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Copy.Look.lookFontHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 색 — 자주 쓰는 견본 3개 + 컬러 피커(아무 색). 숫자(#RRGGBB)는 보여 주지 않는다.
    private func swatchRow(
        _ title: String, swatches: [CaptionLook.Swatch], selected: CaptionLook.Swatch.ID,
        current: CaptionLook.Swatch,
        onPick: @escaping (CaptionLook.Swatch.ID) -> Void,
        onCustom: @escaping (Double, Double, Double) -> Void,
        onSetFavorite: @escaping (Int) -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: Tokens.Space.inner) {
                ForEach(swatches) { swatch in
                    Button {
                        onPick(swatch.id)
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 20, height: 20)
                            .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
                            .overlay {
                                Circle()
                                    .strokeBorder(Tokens.Palette.accent, lineWidth: 2)
                                    .padding(-4)
                                    .opacity(swatch.id == selected ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // 이 칸을 지금 색으로 — 자주 쓰는 3색은 사람이 바꾼다
                        if let i = swatches.firstIndex(of: swatch) {
                            Button(Copy.Look.setFavorite) { onSetFavorite(i) }
                        }
                    }
                    .help(swatch.label)
                    .accessibilityLabel(swatch.label)
                    .accessibilityAddTraits(swatch.id == selected ? .isSelected : [])
                }
                // 아무 색 — 버튼 밑 말풍선 격자 (iOS 처럼). 말풍선 아래에서 자주 쓰는 3칸을 바꾼다
                ColorGridPicker(
                    current: PickedColor(current), favorites: swatches.map(PickedColor.init),
                    isCustom: selected == CaptionLook.customID,
                    onPick: { onCustom($0.red, $0.green, $0.blue) },
                    onSetFavorite: onSetFavorite
                )
                Text(swatches.first(where: { $0.id == selected })?.label ?? Copy.Look.customColor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .leading)
            }
        }
    }
}

#Preview("설정 · 일반") {
    SettingsScreen(values: SampleData.settings)
}

#Preview("설정 · 자막 모양") {
    SettingsScreen(values: SampleData.settings, initialTab: .look)
}

#Preview("설정 · 연결 안 됨") {
    SettingsScreen(values: SampleData.settingsDisconnected)
}
