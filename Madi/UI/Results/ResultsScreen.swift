import SwiftUI

/// 결과물 — 다 만든 영상이 모이는 곳. 여기서 하는 일은 둘뿐이다.
/// **골라서 보고, 내보낸다.**
///
/// 왼쪽은 촬영본별 묶음 목록, 오른쪽은 고른 것 하나. 메일 앱과 같은 문법이다.
/// 편집은 여기서 하지 않는다 — 고치려면 `편집안 열기` 로 돌아간다.
struct ResultsScreen: View {
    var state: ResultsState
    /// 고른 결과물의 펼친 내용. 개발이 붙을 때 목록 선택에서 만들어 넣는다.
    var detail: ResultDetail?
    var exportTargets: [ExportTarget] = []
    /// 화면 위에 서는 한 줄. 내보내다 막힌 경우가 여기로 온다.
    /// 이 화면에는 채팅이 없어서 말할 자리가 필요하다.
    var notice: ScreenNotice?

    var onOpenPlan: () -> Void = {}
    var onExport: (ExportTarget) -> Void = { _ in }
    var onShowShots: () -> Void = {}
    var onTrash: (ResultRef) -> Void = { _ in }
    var onNoticeAction: (ChatChoice) -> Void = { _ in }
    var onDismissNotice: () -> Void = {}

    /// 프리뷰 · 스크린샷용.
    var initialSelection: ResultRef.ID?
    var showsExportSheet = false
    var showsTrashConfirm = false

    @State private var selectedID: ResultRef.ID?
    @State private var mode: CompareMode = .sideBySide
    @State private var isExporting = false
    @State private var trashing: ResultRef?

    var body: some View {
        VStack(spacing: 0) {
            if let notice {
                NoticeBar(notice: notice, onAction: onNoticeAction, onDismiss: onDismissNotice)
                Divider()
            }
            content
        }
            .navigationTitle(Copy.Results.title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .sheet(isPresented: $isExporting) {
                ExportSheet(targets: exportTargets) { target in
                    isExporting = false
                    onExport(target)
                } onCancel: {
                    isExporting = false
                }
            }
            .confirmationDialog(
                Copy.Results.Trash.confirmTitle,
                isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
                presenting: trashing
            ) { result in
                Button(Copy.Results.Trash.action) {
                    onTrash(result)
                    trashing = nil
                }
                Button(Copy.Action.cancel, role: .cancel) { trashing = nil }
            } message: { _ in
                Text(Copy.Results.Trash.confirmMessage)
            }
            .onAppear {
                if selectedID == nil { selectedID = initialSelection }
                if showsExportSheet { isExporting = true }
                if showsTrashConfirm {
                    trashing = state.allItems.first { $0.id == initialSelection }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ResultsSkeleton()
        case .empty:
            ContentUnavailableView {
                Label(Copy.Results.Empty.title, systemImage: "square.and.arrow.up.on.square")
            } description: {
                Text(Copy.Results.Empty.message)
            } actions: {
                Button(Copy.Results.Empty.action, action: onShowShots)
            }
        case .loaded(let groups):
            HStack(spacing: 0) {
                list(groups)
                    .frame(width: 260)
                Divider()
                detailPane
            }
        }
    }

    private func list(_ groups: [ResultGroup]) -> some View {
        List(selection: $selectedID) {
            ForEach(groups) { group in
                Section(group.shotTitle) {
                    ForEach(group.items) { item in
                        ResultRow(result: item)
                            .tag(item.id)
                            .contextMenu {
                                Button(Copy.Results.Export.action) {
                                    selectedID = item.id
                                    isExporting = true
                                }
                                Divider()
                                // 결과물은 우리가 만든 파일이라 지울 수 있다. 다만 되살릴 수
                                // 있어야 해서 macOS 휴지통으로 보낸다 ("삭제" 라고 쓰지 않는다).
                                Button(Copy.Results.Trash.action) { trashing = item }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let detail {
            ResultCompare(detail: detail, mode: mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(Copy.Results.noSelection, systemImage: "hand.tap")
            } description: {
                EmptyView()
            }
        }
    }

    private var subtitle: String {
        guard case .loaded(let groups) = state else { return "" }
        return Copy.count(groups.reduce(0) { $0 + $1.items.count })
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if detail?.previous != nil {
            ToolbarItem(placement: .principal) {
                Picker(Copy.Results.Compare.sideBySide, selection: $mode) {
                    ForEach(CompareMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        if detail != nil {
            ToolbarItem {
                Button(Copy.Action.openPlanFromResult, action: onOpenPlan)
            }
            ToolbarItem {
                Button(Copy.Results.Export.action) { isExporting = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

enum CompareMode: Hashable, CaseIterable, Identifiable {
    case sideBySide, single

    var id: Self { self }

    var label: String {
        switch self {
        case .sideBySide: Copy.Results.Compare.sideBySide
        case .single: Copy.Results.Compare.single
        }
    }
}

/// 목록 한 줄. 규격 · 편집안 · 길이 · 언제.
private struct ResultRow: View {
    var result: ResultRef

    var body: some View {
        HStack(spacing: Tokens.Space.inner) {
            ThumbnailView(thumbnail: result.thumbnail, cornerRadius: 3)
                .frame(width: 24, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Tokens.Space.tight + 1) {
                    Text(result.platform.label)
                        .font(.callout)
                    if result.isNew {
                        Text(Copy.Results.isNew)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Tokens.Palette.accent)
                    }
                }
                Text("\(result.planLabel) · \(Copy.duration(result.duration)) · \(result.when)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // 내보낸 것은 줄에 그대로 남긴다. "이거 올렸었나" 를 묻지 않게.
                if let note = result.exportedNote {
                    Label(note, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// 불러오는 중. 개수도 모르는 상태라 자리만 잡는다.
private struct ResultsSkeleton: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: Tokens.Space.between) {
                ForEach(0..<8, id: \.self) { _ in
                    HStack(spacing: Tokens.Space.inner) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Tokens.Palette.placeholder)
                            .frame(width: 24, height: 42)
                        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Tokens.Palette.placeholder)
                                .frame(width: 90, height: 10)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Tokens.Palette.placeholder)
                                .frame(width: 140, height: 8)
                        }
                        Spacer()
                    }
                }
                Spacer()
            }
            .padding(Tokens.Space.between)
            .frame(width: 260)

            Divider()

            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text(Copy.Results.Loading.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, Tokens.Space.inner)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview("결과물 · 나란히") {
    ResultsScreen(
        state: .loaded(SampleData.resultGroups),
        detail: SampleData.resultDetail,
        exportTargets: SampleData.exportTargets,
        initialSelection: SampleData.results[0].id
    )
    .frame(width: 1100, height: 700)
}

#Preview("결과물 · 빈 상태") {
    ResultsScreen(state: .empty)
        .frame(width: 900, height: 600)
}
