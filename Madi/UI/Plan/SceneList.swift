import SwiftUI

/// 장면 목록. **이 제품에서 사람이 "틀린 곳을 짚는" 유일한 자리다** (AGENTS.md §1-3).
///
/// 타임라인이 아니다. 트랙도 눈금자도 키프레임도 없다 (`§16`). 순서대로 놓인 줄일 뿐이고,
/// 한 줄이 "몇 번째 · 무슨 역할 · 뭐라고 말하는지 · 몇 초" 를 통째로 말한다.
///
/// **가로 띠가 아니라 세로 목록인 이유**: 1100pt 창에서 가로로 놓으면 9개 중 2~3개만 보인다.
/// 편집안을 훑는 게 이 화면의 일인데 훑을 수가 없다.
///
/// 평소에는 줄을 접어 두고(자막 첫 덩어리만), **고른 줄만 펼친다** — 자막 전부 · 영문 보조 ·
/// 버튼이 그때 나온다. 아홉 줄이 전부 펼쳐져 있으면 훑을 수가 없다.
///
/// 순서는 **끌어서** 바꾼다. `List` 의 기본 이동이라 손잡이를 따로 그리지 않는다.
/// 말로도 된다 ("3번이랑 4번 바꿔줘") — 둘 다 같은 결과다.
struct SceneList: View {
    var plan: PlanView
    @Binding var selectedID: SceneCardItem.ID?
    /// 자막을 고치는 중인 줄. 한 번에 하나만.
    @Binding var editingID: SceneCardItem.ID?
    /// 만드는 중에는 읽기만 한다. 흐리게 두고 손대지 못하게 막는다.
    var isReadOnly = false

    var onRemove: (SceneCardItem) -> Void = { _ in }
    var onExtend: (SceneCardItem) -> Void = { _ in }
    var onShorten: (SceneCardItem) -> Void = { _ in }
    var onPlayFrom: (SceneCardItem) -> Void = { _ in }
    var onRestoreGap: (SceneCardItem) -> Void = { _ in }
    var onMove: (IndexSet, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List(selection: $selectedID) {
                ForEach(plan.scenes) { scene in
                    VStack(alignment: .leading, spacing: 0) {
                        row(scene)
                        // 뺀 쉬는 구간은 **지우지 않고 자국으로 남긴다.**
                        // 사용자가 AI 의 판단을 되돌릴 유일한 길이다.
                        if let gap = scene.removedGapAfter {
                            RemovedGapRow(seconds: gap, isReadOnly: isReadOnly) {
                                onRestoreGap(scene)
                            }
                        }
                    }
                    .tag(scene.id)
                    // 줄 높이를 1pt 단위로 아꼈다. 1100×700 에서 장면 6개가 보이는지가 기준이고,
                    // 안 보이면 이 화면은 훑는 일을 못 한다.
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowSeparator(.hidden)
                    .contextMenu { menu(scene) }
                }
                .onMove { from, to in onMove(from, to) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .disabled(isReadOnly)
            .opacity(isReadOnly ? 0.5 : 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.inner) {
            Text(Copy.Plan.Scenes.header(
                count: plan.scenes.count,
                total: Copy.duration(plan.targetDuration)
            ))
            .font(.headline)

            // 줄이 하나면 순서를 바꿀 것도 없다. 안내를 띄우면 없는 기능을 찾게 된다.
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, Tokens.Space.section)
        .padding(.top, Tokens.Space.inner)
        .padding(.bottom, Tokens.Space.tight)
    }

    private var hint: String? {
        if isReadOnly { return Copy.Plan.Making.readOnly }
        return plan.scenes.count > 1 ? Copy.Plan.Scenes.reorderHint : nil
    }

    private func row(_ scene: SceneCardItem) -> some View {
        SceneRow(
            scene: scene,
            isSelected: scene.id == selectedID,
            isEditingCaption: scene.id == editingID,
            isReadOnly: isReadOnly,
            onRemove: { onRemove(scene) },
            onExtend: { onExtend(scene) },
            onEditCaption: { editingID = scene.id },
            onEndEditing: { editingID = nil }
        )
    }

    @ViewBuilder
    private func menu(_ scene: SceneCardItem) -> some View {
        if !isReadOnly {
            Button(Copy.Plan.Scenes.editCaptionFull) { editingID = scene.id }
                .keyboardShortcut(.return, modifiers: [])
            Divider()
            Button(Copy.Plan.Scenes.extendOne) { onExtend(scene) }
                .keyboardShortcut("]")
            Button(Copy.Plan.Scenes.shortenOne) { onShorten(scene) }
                .keyboardShortcut("[")
            Button(Copy.Plan.Scenes.playFromHere) { onPlayFrom(scene) }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button(Copy.Plan.Scenes.removeScene) { onRemove(scene) }
                .keyboardShortcut(.delete)
        }
    }
}

/// 장면 한 줄. 접힌 모습이 기본이고, 고른 줄만 펼친다.
struct SceneRow: View {
    var scene: SceneCardItem
    var isSelected: Bool
    var isEditingCaption: Bool
    var isReadOnly: Bool

    var onRemove: () -> Void = {}
    var onExtend: () -> Void = {}
    var onEditCaption: () -> Void = {}
    var onEndEditing: () -> Void = {}

    /// 고치는 중에만 쓰는 임시 글자. 저장은 개발이 붙인다.
    @State private var draft: String = ""
    @State private var secondaryDraft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.inner + 2) {
            Text("\(scene.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 1)

            ThumbnailView(thumbnail: scene.thumbnail, cornerRadius: 3)
                .frame(width: 26, height: 46)

            VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                HStack(spacing: Tokens.Space.inner) {
                    RoleTag(role: scene.role)
                    Text(Copy.shortSeconds(scene.duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                caption
                if isSelected && !isReadOnly && !isEditingCaption {
                    actions
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Tokens.Space.tight)
        .padding(.horizontal, Tokens.Space.inner - 2)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var caption: some View {
        if isEditingCaption {
            // 고치기는 줄 **안에서** 한다. 따로 창을 띄우면 앞뒤 장면을 못 보면서 고치게 된다.
            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                TextField(Copy.Plan.Scenes.captionPlaceholder, text: $draft, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .onSubmit(onEndEditing)

                // 영문 보조도 직접 고칠 수 있다. 손대지 않으면 AI 가 본문에 맞춰 다시 만든다.
                TextField(Copy.Plan.Scenes.secondaryPlaceholder, text: $secondaryDraft)
                    .font(.caption)

                HStack(spacing: Tokens.Space.inner) {
                    Text(Copy.Plan.Scenes.secondaryHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(Copy.Plan.Scenes.doneEditing, action: onEndEditing)
                        .controlSize(.small)
                }
            }
            .textFieldStyle(.roundedBorder)
            .onAppear {
                draft = scene.caption
                secondaryDraft = scene.secondary ?? ""
                isFocused = true
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.caption.isEmpty ? Copy.Plan.Scenes.noCaption : scene.caption)
                    .font(.callout)
                    .foregroundStyle(scene.caption.isEmpty ? .secondary : .primary)
                    .lineLimit(isSelected ? nil : 1)
                    .fixedSize(horizontal: false, vertical: isSelected)

                if isSelected {
                    // 고른 줄만 펼친다 — 영문 보조와 나머지 자막 덩어리가 여기서 나온다.
                    if let secondary = scene.secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(scene.moreCaptions, id: \.self) { chunk in
                        Text(chunk)
                            .font(.callout)
                    }
                } else if scene.captionCount > 1 {
                    Text(Copy.Plan.Scenes.moreCaptions(scene.captionCount - 1))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Tokens.Space.between) {
            Button(Copy.Plan.Scenes.remove, action: onRemove)
            Button(Copy.Plan.Scenes.extend, action: onExtend)
            Button(Copy.Plan.Scenes.editCaption, action: onEditCaption)
        }
        .buttonStyle(.link)
        .font(.caption)
        .padding(.top, Tokens.Space.hairline)
    }
}

/// 뺀 쉬는 구간 자국. 줄 사이에 얇게 선다.
struct RemovedGapRow: View {
    var seconds: Double
    var isReadOnly: Bool
    var onRestore: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.inner) {
            Image(systemName: "scissors")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(Copy.Plan.Scenes.removedGap(seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isReadOnly {
                Button(Copy.Plan.Scenes.bringBack, action: onRestore)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Tokens.Space.inner - 2)
        .padding(.bottom, Tokens.Space.hairline)
    }
}

#Preview("장면 목록") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID?
    SceneList(plan: SampleData.plan, selectedID: $selected, editingID: $editing)
        .frame(width: 420, height: 400)
}

#Preview("자막 고치는 중") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID? = "s4"
    SceneList(plan: SampleData.plan, selectedID: $selected, editingID: $editing)
        .frame(width: 420, height: 400)
}

#Preview("만드는 중 · 읽기 전용") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID?
    SceneList(plan: SampleData.plan, selectedID: $selected, editingID: $editing, isReadOnly: true)
        .frame(width: 420, height: 400)
}
