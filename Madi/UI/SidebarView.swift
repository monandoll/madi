import SwiftUI

/// 왼쪽 사이드바. `NavigationSplitView` 의 첫 칸이다.
///
/// 칸은 셋뿐이다 — 촬영본 · 결과물 · 만드는 중. 사람이 하는 일이 셋이라서 그렇다
/// (찍은 것 고르기 → 만드는 중 보기 → 다 된 것 내보내기).
/// 설정은 칸이 아니라 macOS 규칙대로 `설정…` (⌘,) 으로 연다. 푸터에서 누를 수 있다.
struct SidebarView: View {
    var studio: StudioStatus
    @Binding var selection: LibrarySection?
    var onOpenSettings: () -> Void = {}

    var body: some View {
        List(selection: $selection) {
            Section(Copy.Sidebar.libraryHeader) {
                ForEach(LibrarySection.allCases) { section in
                    Label(section.label, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    /// `만드는 중` 은 0 일 때 뱃지를 지운다. 0 을 보여주면 "뭔가 비었다" 로 읽힌다.
    private func badge(for section: LibrarySection) -> Int {
        studio.count(for: section)
    }

    /// 연결됨 초록, 로그인만 하면 되는 상태는 노랑(사람이 손대면 된다), 없음은 회색.
    /// 붉은색은 쓰지 않는다 — 어느 것도 실패가 아니다.
    private var dotColor: Color {
        switch studio.ai {
        case .claude, .codex: Tokens.Palette.ok
        case .notLoggedIn: Tokens.Palette.attention
        case .none: Color.secondary
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 편집 준비 — 첫 실행 직후 수 분. 기다리게 하는 화면이 아니라 **조용한 한 줄**이다 (§1-6).
            // 끝나면 사라진다. 아무 말도 하지 않는 게 "다 됐다" 는 뜻이다.
            if let prep = studio.preparing {
                Divider()
                PrepLine(prep: prep)
                    .padding(.horizontal, Tokens.Space.between)
                    .padding(.vertical, Tokens.Space.inner)
            }
            Divider()
            Button(action: onOpenSettings) {
                HStack(spacing: Tokens.Space.inner) {
                    VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                        Text(studio.studioName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: Tokens.Space.tight + 1) {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 6, height: 6)
                            Text(studio.ai.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: Tokens.Space.tight)
                    // 설정으로 가는 길은 앱 메뉴(⌘,)지만, 크리에이터가 ⌘, 를 알 리 없다.
                    // 누를 수 있다는 걸 보이게만 한다.
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Tokens.Space.between)
            .padding(.vertical, Tokens.Space.inner + 2)
            .help(Copy.Sidebar.openSettings)
        }
    }
}

#Preview("사이드바 · 정상") {
    @Previewable @State var selection: LibrarySection? = .shots
    NavigationSplitView {
        SidebarView(studio: SampleData.studio, selection: $selection)
    } detail: {
        Color.clear
    }
    .frame(width: 560, height: 420)
}

#Preview("사이드바 · 비었고 AI 없음") {
    @Previewable @State var selection: LibrarySection? = .shots
    NavigationSplitView {
        SidebarView(studio: SampleData.studioNoAI, selection: $selection)
    } detail: {
        Color.clear
    }
    .frame(width: 560, height: 420)
}

/// 편집 준비 한 줄. 받는 중이면 진행 막대, 멈췄으면 노란 표시와 이유.
private struct PrepLine: View {
    var prep: EnginePrep

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
            switch prep {
            case .downloading(let fraction):
                Text(Copy.Prep.modelDownloading(fraction))
                    .font(.caption)
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                Text(Copy.Prep.modelDownloadingDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .warming:
                HStack(spacing: Tokens.Space.tight + 1) {
                    ProgressView().controlSize(.mini)
                    Text(Copy.Prep.modelWarming)
                        .font(.caption)
                }
            case .paused:
                // 실패가 아니다. 인터넷이 되면 이어서 받는다.
                Label(Copy.Prep.modelDownloadPaused, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                stopped(Copy.Prep.sidebarNeedsInternet)
            case .diskFull:
                stopped(Copy.Prep.sidebarNeedsSpace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stopped(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(Copy.Prep.sidebarStopped, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tokens.Palette.attention)
                .font(.caption)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
