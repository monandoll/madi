import SwiftUI

/// 갤러리 — 아이폰으로 찍은 촬영본이 저절로 모이는 곳. 앱을 열면 여기부터 본다.
///
/// 사진 앱 문법을 그대로 따른다. 날짜로 묶고, 세로 그리드로 놓고, 고르면 오른쪽에 정보가 뜨고,
/// 우클릭으로 할 일을 고른다. **새 문법을 만들지 않는다** — 이 사람은 이미 사진 앱을 쓴다.
///
/// 업로드 버튼이 주인공이 아니다. "찍으면 들어와 있다" 가 이 제품의 약속이고
/// (AGENTS.md §1-11 파일을 옮기게 하지 않는다), 그래서 빈 상태 문구가 그 말을 한다.
struct GalleryScreen: View {
    var state: GalleryState
    var studio: StudioStatus

    /// 촬영본에서 나가는 길은 이것 하나다. 편집안이 열리고 AI 가 초안을 짠다.
    var onMakeShort: (ShotItem) -> Void = { _ in }
    var onPlay: (ShotItem) -> Void = { _ in }
    var onRevealInPhotos: (ShotItem) -> Void = { _ in }
    var onHide: (ShotItem) -> Void = { _ in }
    var onAddFromMac: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}
    /// 화면을 열 때 이미 고를 촬영본. 프리뷰 · 스크린샷에서 정보 패널이 채워진 모습을 보려고 둔다.
    var initialSelection: ShotItem.ID?
    /// 방금 한 일을 상태줄에 한 줄로 알린다 (숨김 등). 알림창을 띄우지 않는다.
    var notice: String?
    /// 프리뷰 · 스크린샷용. 찾는 말과 거르개를 미리 걸어 둔다.
    var initialQuery: String?
    var initialFilter: GalleryFilter?

    @State private var selectedID: ShotItem.ID?
    @State private var filter: GalleryFilter = .all
    @State private var query: String = ""
    @State private var showsInspector = true

    var body: some View {
        contentFillsColumn
            // 상태줄은 **그리드 밑에만** 깐다. 화면 전체에 깔면 정보 패널 아래 버튼을 덮는다.
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            .navigationTitle(Copy.Gallery.title)
            .navigationSubtitle(Copy.count(totalCount))
            .toolbar { toolbar }
            .searchable(text: $query, placement: .toolbar, prompt: Copy.Action.search)
            .inspector(isPresented: $showsInspector) {
                ShotInspector(shot: selectedShot, onMakeShort: onMakeShort)
                .inspectorColumnWidth(
                    min: Tokens.Size.inspectorMin,
                    ideal: Tokens.Size.inspectorIdeal,
                    max: 360
                )
            }
            .onAppear {
                if selectedID == nil { selectedID = initialSelection }
                if let initialQuery { query = initialQuery }
                if let initialFilter { filter = initialFilter }
            }
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            GallerySkeleton()
        case .empty:
            ContentUnavailableView {
                Label(Copy.Gallery.Empty.title, systemImage: "iphone.gen3")
            } description: {
                Text(Copy.Gallery.Empty.message)
            } actions: {
                Button(Copy.Gallery.Empty.addFromMac, action: onAddFromMac)
            }
        case .noPhotoAccess:
            ContentUnavailableView {
                Label(Copy.Gallery.NoAccess.title, systemImage: "photo.on.rectangle")
            } description: {
                Text(Copy.Gallery.NoAccess.message)
            } actions: {
                Button(Copy.Gallery.Empty.addFromMac, action: onAddFromMac)
                    .buttonStyle(.borderedProminent)
                Button(Copy.Gallery.NoAccess.openSystemSettings, action: onOpenSystemSettings)
            }
        case .importing(_, _, let groups), .loaded(let groups):
            grid(groups)
        }
    }

    /// 빈 상태 · 실패 화면은 저절로 늘어나지 않는다. 늘려 두지 않으면 아래 상태줄이
    /// 창 바닥이 아니라 글자 바로 밑에 붙는다.
    private var contentFillsColumn: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(_ groups: [ShotGroup]) -> some View {
        GeometryReader { proxy in
            gridBody(groups, columns: columnCount(for: proxy.size.width))
        }
    }

    /// 칸 수를 직접 센다. `.adaptive` 는 남는 폭을 오른쪽에 빈 공간으로 흘려서
    /// 1440 에서 그리드 오른쪽이 휑하게 빈다. `.flexible` 로 칸이 폭을 나눠 갖게 한다.
    ///
    /// 세로 칸이라 한 줄에 적게 놓으면 한 화면에 몇 개 안 보인다. 그래서 **최소 4칸**이다
    /// (1100pt 창 기준). 넓어지면 칸을 키우지 않고 수를 늘린다.
    private func columnCount(for width: CGFloat) -> Int {
        let usable = width - Tokens.Space.section * 2
        let fit = Int((usable + Tokens.Space.between)
            / (Tokens.Size.gridItemIdeal + Tokens.Space.between))
        return max(4, fit)
    }

    @ViewBuilder
    private func gridBody(_ groups: [ShotGroup], columns count: Int) -> some View {
        let shown = filtered(groups)
        if shown.isEmpty {
            // 왜 없는지 말한다. 거르개 때문이면 그것부터 말하고 푸는 버튼을 준다.
            ContentUnavailableView {
                Label(Copy.Gallery.NoResults.title(query), systemImage: "magnifyingglass")
            } description: {
                VStack(spacing: Tokens.Space.tight) {
                    Text(Copy.Gallery.NoResults.message)
                    if filter != .all {
                        Text(Copy.Gallery.NoResults.filterNote(filter.label))
                    }
                }
            } actions: {
                if filter != .all {
                    Button(Copy.Gallery.NoResults.showAll) { filter = .all }
                }
            }
        } else {
            grid(shown, columns: count)
        }
    }

    private func grid(_ shown: [ShotGroup], columns count: Int) -> some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tokens.Space.between, alignment: .top),
                    count: count
                ),
                alignment: .leading,
                spacing: Tokens.Space.section
            ) {
                ForEach(shown) { group in
                    Section {
                        ForEach(group.shots) { shot in
                            cell(shot)
                        }
                    } header: {
                        GroupHeader(title: group.title, subtitle: group.subtitle)
                    }
                }
            }
            .padding(Tokens.Space.section)
        }
        // 빈 곳을 누르면 선택이 풀린다. 사진 앱과 같다.
        .contentShape(.rect)
        .onTapGesture { selectedID = nil }
    }

    private func cell(_ shot: ShotItem) -> some View {
        ShotCell(shot: shot, isSelected: shot.id == selectedID)
            .onTapGesture { selectedID = shot.id }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onMakeShort(shot) })
            .contextMenu {
                Button(Copy.Action.makeShort) { onMakeShort(shot) }
                    .keyboardShortcut("o")
                Divider()
                Button(Copy.Action.play) { onPlay(shot) }
                    .keyboardShortcut(.space, modifiers: [])
                Button(Copy.Action.openInPhotos) { onRevealInPhotos(shot) }
                Divider()
                // 지우는 게 아니다. 사진 앱 원본은 그대로 남는다 — 누른 뒤 상태줄이 그렇게 말한다.
                Button(Copy.Action.hideFromList) { onHide(shot) }
            } preview: {
                // 우클릭 미리보기. 세로 그림 한 장이면 충분하다.
                ThumbnailView(thumbnail: shot.thumbnail, cornerRadius: 0)
                    .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                    .frame(height: 420)
            }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(Copy.Gallery.Filter.all, selection: $filter) {
                ForEach(GalleryFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        ToolbarItem {
            Button(action: onAddFromMac) {
                Label(Copy.Gallery.Empty.addFromMac, systemImage: "plus")
            }
            .help(Copy.Gallery.Empty.addFromMac)
        }
        ToolbarItem {
            Button {
                showsInspector.toggle()
            } label: {
                Label(Copy.Gallery.Info.toggle, systemImage: "sidebar.trailing")
            }
            .help(Copy.Gallery.Info.toggle)
        }
    }

    // MARK: - 아래 상태줄

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Tokens.Space.inner) {
                if case .importing(let done, let total, _) = state {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                    Text(Copy.Gallery.Importing.progress(done: done, total: total))
                } else if case .loading = state {
                    ProgressView().controlSize(.small)
                    Text(Copy.Gallery.Loading.title)
                } else if let notice {
                    Text(notice)
                    Button(Copy.Action.undo) {}
                        .buttonStyle(.link)
                        .font(.caption)
                } else {
                    Text(Copy.Gallery.Status.selection(
                        total: totalCount,
                        selected: selectedID == nil ? 0 : 1
                    ))
                    Text("·")
                    Text(Copy.Gallery.Status.syncedWithICloud)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Tokens.Space.between)
            .padding(.vertical, Tokens.Space.inner - 1)
        }
        .background(.bar)
    }

    // MARK: - 거르기

    private func filtered(_ groups: [ShotGroup]) -> [ShotGroup] {
        groups.compactMap { group in
            let shots = group.shots.filter { shot in
                filter.keeps(shot) && matchesQuery(shot)
            }
            return shots.isEmpty ? nil : ShotGroup(
                title: group.title, subtitle: group.subtitle, shots: shots
            )
        }
    }

    private func matchesQuery(_ shot: ShotItem) -> Bool {
        query.isEmpty || shot.title.localizedStandardContains(query)
    }

    private var totalCount: Int {
        state.groups.reduce(0) { $0 + $1.shots.count }
    }

    private var selectedShot: ShotItem? {
        state.groups.lazy.flatMap(\.shots).first { $0.id == selectedID }
    }
}

/// 위쪽 거르개. 편집 전 / 결과물 있음은 "이거 이미 만들었나?" 하나를 푸는 장치다.
enum GalleryFilter: Hashable, CaseIterable, Identifiable {
    case all, notEdited, hasResult

    var id: Self { self }

    var label: String {
        switch self {
        case .all: Copy.Gallery.Filter.all
        case .notEdited: Copy.Gallery.Filter.notEdited
        case .hasResult: Copy.Gallery.Filter.hasResult
        }
    }

    func keeps(_ shot: ShotItem) -> Bool {
        switch self {
        case .all: true
        case .notEdited: !shot.hasResult
        case .hasResult: shot.hasResult
        }
    }
}

private struct GroupHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.inner) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, Tokens.Space.inner)
    }
}

/// 불러오는 중. 숫자나 퍼센트를 보여줄 게 없어서 자리만 잡아 둔다.
private struct GallerySkeleton: View {
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tokens.Space.between, alignment: .top),
                    count: 4
                ),
                alignment: .leading, spacing: Tokens.Space.section
            ) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Tokens.Space.inner - 2) {
                        RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail)
                            .fill(Tokens.Palette.placeholder)
                            .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Tokens.Palette.placeholder)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Tokens.Palette.placeholder)
                            .frame(width: 60, height: 8)
                    }
                }
            }
            .padding(Tokens.Space.section)
        }
        .accessibilityLabel(Copy.Gallery.Loading.title)
    }
}

// MARK: - 프리뷰

#Preview("갤러리 · 정상 1440×900") {
    RootView(studio: SampleData.studio, gallery: .loaded(SampleData.groups))
        .frame(width: 1440, height: 900)
}

#Preview("갤러리 · 정상 1100×700") {
    RootView(studio: SampleData.studio, gallery: .loaded(SampleData.groups))
        .frame(width: 1100, height: 700)
}

#Preview("갤러리 · 빈 상태") {
    RootView(studio: SampleData.studioEmpty, gallery: .empty)
        .frame(width: 1100, height: 700)
}

#Preview("갤러리 · 가져오는 중") {
    RootView(
        studio: SampleData.studio,
        gallery: .importing(done: 3, total: 7, groups: SampleData.importingGroups)
    )
    .frame(width: 1100, height: 700)
}

#Preview("갤러리 · 불러오는 중") {
    RootView(studio: SampleData.studio, gallery: .loading)
        .frame(width: 1100, height: 700)
}

#Preview("갤러리 · 사진 접근 없음") {
    RootView(studio: SampleData.studioEmpty, gallery: .noPhotoAccess)
        .frame(width: 1100, height: 700)
}
