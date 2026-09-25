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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Button(action: onOpenSettings) {
                VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                    Text(studio.studioName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: Tokens.Space.tight + 1) {
                        Circle()
                            .fill(studio.ai.isConnected ? Tokens.Palette.ok : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(studio.ai.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
