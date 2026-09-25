import SwiftUI

/// 편집안 상세 — **이 제품의 본체다.**
///
/// 왼쪽 위는 "지금 어떻게 생겼나"(재생 막대 + 편집안 요약), 왼쪽 아래는 "무엇으로 이뤄졌나"
/// (장면 카드), 오른쪽은 "어떻게 고칠까"(대화). 셋이 한 화면에 같이 있어야 한다 —
/// 카드를 보고 틀린 곳을 짚은 다음 바로 말로 고치는 게 이 화면의 전부다.
///
/// `만들기` 는 여기에만 있다. 갤러리에서 바로 영상이 나오는 길은 없다 (`§1-3`, `§10`).
struct PlanScreen: View {
    var state: PlanState
    var messages: [ChatMessage]
    var chips: [String]

    var onBack: () -> Void = {}
    var onMake: () -> Void = {}
    var onStop: () -> Void = {}
    var onOpenResults: () -> Void = {}
    var onConnectAI: () -> Void = {}

    /// 프리뷰 · 스크린샷용 초기 상태.
    var initialSceneID: SceneCardItem.ID?
    var initialEditingID: SceneCardItem.ID?

    @State private var selectedID: SceneCardItem.ID?
    @State private var editingID: SceneCardItem.ID?
    @State private var showsChat = true

    var body: some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .inspector(isPresented: $showsChat) {
                ChatPanel(messages: messages, chips: chips, isBusy: isBusy)
                    .inspectorColumnWidth(
                        min: Tokens.Size.chatMin,
                        ideal: Tokens.Size.chatIdeal,
                        max: 420
                    )
            }
            .onAppear {
                if selectedID == nil { selectedID = initialSceneID }
                if editingID == nil { editingID = initialEditingID }
            }
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        switch state {
        case .ready(let plan):
            ready(plan)
        case .preparing(let steps):
            PlanPreparingView(steps: steps, onStop: onStop)
        case .noAI:
            // 한 줄만 말한다. AI 없이 도는 다른 길을 만들지 않는다 (AGENTS.md §10, §16).
            ContentUnavailableView {
                Label(Copy.Plan.NoAI.title, systemImage: "sparkles")
            } description: {
                EmptyView()
            } actions: {
                Button(Copy.Plan.NoAI.action, action: onConnectAI)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func ready(_ plan: PlanView) -> some View {
        GeometryReader { proxy in
            readyBody(plan, topHeight: topHeight(for: proxy.size.height))
        }
    }

    /// 창이 낮으면 위쪽(재생 막대 + 요약)부터 줄인다. 장면 목록은 마지막까지 지킨다 —
    /// 훑을 수 없으면 이 화면은 할 일을 못 한다.
    private func topHeight(for height: CGFloat) -> CGFloat {
        min(300, max(230, height * 0.36))
    }

    private func readyBody(_ plan: PlanView, topHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 위: 지금 어떻게 생겼나. 아래: 무엇으로 이뤄졌나.
            // 위쪽 높이를 고정한다 — 창이 낮아질 때 줄어들어야 하는 건 장면 목록이 아니다.
            HStack(alignment: .top, spacing: Tokens.Space.section) {
                PlanPlayer(
                    thumbnail: currentScene(plan).thumbnail,
                    position: position(in: plan),
                    total: plan.targetDuration
                )
                .frame(width: 158)

                PlanInfoCard(plan: plan)
                    // 넓은 창에서 카드가 끝까지 늘어나면 한 줄에 글자 몇 개만 남고 오른쪽이 휑해진다.
                    .frame(maxWidth: 460, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.section)
            .frame(height: topHeight)

            Divider()

            // "지금 보는 장면" 카드를 따로 두지 않는다. 목록에서 고른 줄이 그 자리다 —
            // 같은 것을 두 군데 보여주면 어느 쪽을 봐야 하는지 묻게 된다.
            SceneList(plan: plan, selectedID: $selectedID, editingID: $editingID)
        }
    }

    private func currentScene(_ plan: PlanView) -> SceneCardItem {
        plan.scenes.first { $0.id == selectedID } ?? plan.scenes[0]
    }

    /// 고른 장면이 시작하는 지점. 실제 재생 위치는 개발이 붙인다.
    private func position(in plan: PlanView) -> Double {
        var elapsed: Double = 0
        for scene in plan.scenes {
            if scene.id == currentScene(plan).id { break }
            elapsed += scene.duration
        }
        return elapsed
    }

    // MARK: - 툴바

    private var title: String {
        switch state {
        case .ready(let plan): plan.shotTitle
        case .preparing, .noAI: SampleTitlePlaceholder.title
        }
    }

    private var subtitle: String {
        switch state {
        case .ready(let plan):
            "\(plan.platform.label) · \(Copy.duration(plan.targetDuration))"
        case .preparing:
            Copy.Plan.Preparing.title
        case .noAI:
            ""
        }
    }

    private var isBusy: Bool {
        if case .preparing = state { return true }
        return false
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onBack) {
                Label(Copy.Plan.backToGallery, systemImage: "chevron.backward")
            }
            .help(Copy.Plan.backToGallery)
        }

        if case .ready(let plan) = state {
            ToolbarItem {
                // 편집안은 고칠 때마다 새로 생긴다. 이전 것을 지우지 않으므로 고를 수 있어야 한다.
                Menu(plan.versionLabel) {
                    ForEach(1...max(plan.versionCount, 1), id: \.self) { n in
                        Button(Copy.Plan.version(n)) {}
                    }
                }
                .fixedSize()
            }
            if plan.resultCount > 0 {
                ToolbarItem {
                    Button(action: onOpenResults) {
                        Label(
                            Copy.results(plan.resultCount),
                            systemImage: "square.and.arrow.up.on.square"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
        }

        ToolbarItem {
            Button {
                showsChat.toggle()
            } label: {
                Label(Copy.Chat.header, systemImage: "bubble.left.and.bubble.right")
            }
            .help(Copy.Chat.header)
        }

        ToolbarItem {
            if isBusy {
                Button(Copy.Plan.Preparing.stop, action: onStop)
            } else {
                Button(Copy.Action.make, action: onMake)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady)
            }
        }
    }

    private var isReady: Bool {
        if case .ready = state { return true }
        return false
    }
}

/// 편집안을 짜는 동안. 퍼센트 하나 대신 **무슨 일을 하는지** 를 순서대로 보여준다.
/// "20초쯤 남음" 은 있을 때만 붙인다 — 틀린 숫자를 보여주느니 없는 게 낫다.
private struct PlanPreparingView: View {
    var steps: [PrepareStep]
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.section) {
            Spacer()
            VStack(alignment: .leading, spacing: Tokens.Space.between) {
                Text(Copy.Plan.Preparing.header)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(steps) { step in
                    HStack(spacing: Tokens.Space.inner) {
                        icon(for: step.state)
                            .frame(width: 16)
                        Text(step.title)
                            .foregroundStyle(step.state == .waiting ? .secondary : .primary)
                        Spacer(minLength: Tokens.Space.section)
                        if step.state == .done {
                            Text(Copy.Plan.Preparing.done)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let remaining = step.remaining {
                            Text(Copy.Plan.Preparing.remaining(remaining))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }
            .padding(Tokens.Space.section)
            .frame(maxWidth: 380)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))

            Button(Copy.Plan.Preparing.stop, action: onStop)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func icon(for state: PrepareStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .foregroundStyle(Tokens.Palette.ok)
        case .running:
            ProgressView().controlSize(.small)
        case .waiting:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tertiary)
        }
    }
}

/// 편집안이 아직 없을 때도 제목은 촬영본 제목이다. 샘플에서만 쓰는 자리표시.
private enum SampleTitlePlaceholder {
    static let title = SampleData.plan.shotTitle
}

// MARK: - 프리뷰

#Preview("편집안 · 1440×900") {
    PlanScreen(
        state: .ready(SampleData.plan),
        messages: SampleData.chat,
        chips: SampleData.chatChips,
        initialSceneID: "s4"
    )
    .frame(width: 1440 - 210, height: 900)
}

#Preview("편집안 · 1100×700") {
    PlanScreen(
        state: .ready(SampleData.plan),
        messages: SampleData.chat,
        chips: SampleData.chatChips,
        initialSceneID: "s4"
    )
    .frame(width: 1100 - 210, height: 700)
}

#Preview("편집안 · 만드는 중") {
    PlanScreen(
        state: .preparing(SampleData.prepareSteps),
        messages: SampleData.chatPreparing,
        chips: SampleData.chatChips
    )
    .frame(width: 1100 - 210, height: 700)
}

#Preview("편집안 · AI 연결 안 됨") {
    PlanScreen(state: .noAI, messages: [], chips: [])
        .frame(width: 1100 - 210, height: 700)
}
