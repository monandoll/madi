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

    var onOpenPlan: () -> Void = {}
    var onExport: (ExportTarget) -> Void = { _ in }
    var onShowShots: () -> Void = {}

    /// 프리뷰 · 스크린샷용.
    var initialSelection: ResultRef.ID?
    var showsExportSheet = false

    @State private var selectedID: ResultRef.ID?
    @State private var mode: CompareMode = .sideBySide
    @State private var isExporting = false

    var body: some View {
        content
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
            .onAppear {
                if selectedID == nil { selectedID = initialSelection }
                if showsExportSheet { isExporting = true }
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
