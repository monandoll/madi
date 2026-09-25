import SwiftUI

/// 장면 목록. **이 제품에서 사람이 "틀린 곳을 짚는" 유일한 자리다** (AGENTS.md §1-3).
///
/// 타임라인이 아니다. 트랙도 눈금자도 키프레임도 없다 (`§16`). 순서대로 놓인 줄일 뿐이고,
/// 한 줄이 "몇 번째 · 무슨 역할 · 뭐라고 말하는지 · 몇 초" 를 통째로 말한다.
///
/// **가로 띠가 아니라 세로 목록인 이유**: 1100pt 창에서 가로로 놓으면 9개 중 2~3개만 보인다.
/// 편집안을 훑는 게 이 화면의 일인데 훑을 수가 없다. 세로로 놓으면 같은 창에서 6~7개가 보이고,
/// 위에서 아래로 읽는 순서가 영상 순서와 같아 "몇 번째 장면" 을 세기도 쉽다.
///
/// 뺀 쉬는 구간은 **지우지 않고 줄 사이에 자국으로 남긴다** — 되돌릴 수 있어야 한다.
struct SceneList: View {
    var plan: PlanView
    @Binding var selectedID: SceneCardItem.ID?
    /// 자막을 고치는 중인 줄. 한 번에 하나만.
    @Binding var editingID: SceneCardItem.ID?

    var onRemove: (SceneCardItem) -> Void = { _ in }
    var onExtend: (SceneCardItem) -> Void = { _ in }
    var onShorten: (SceneCardItem) -> Void = { _ in }
    var onPlayFrom: (SceneCardItem) -> Void = { _ in }
    var onRestoreGap: (SceneCardItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Plan.Scenes.header(
                count: plan.scenes.count,
                total: Copy.duration(plan.targetDuration)
            ))
            .font(.headline)
            .padding(.horizontal, Tokens.Space.section)
            .padding(.vertical, Tokens.Space.inner)

            ScrollView {
                LazyVStack(spacing: Tokens.Space.tight) {
                    ForEach(plan.scenes) { scene in
                        row(scene)
                        if let gap = scene.removedGapAfter {
                            RemovedGapRow(seconds: gap) { onRestoreGap(scene) }
                        }
                    }
                }
                .padding(.horizontal, Tokens.Space.between)
                .padding(.bottom, Tokens.Space.between)
            }
        }
    }

    private func row(_ scene: SceneCardItem) -> some View {
        SceneRow(
            scene: scene,
            isSelected: scene.id == selectedID,
            isEditingCaption: scene.id == editingID,
            onRemove: { onRemove(scene) },
            onExtend: { onExtend(scene) },
            onEditCaption: { editingID = scene.id },
            onEndEditing: { editingID = nil }
        )
        .onTapGesture { selectedID = scene.id }
        .contextMenu {
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

/// 장면 한 줄.
struct SceneRow: View {
    var scene: SceneCardItem
    var isSelected: Bool
    var isEditingCaption: Bool

    var onRemove: () -> Void = {}
    var onExtend: () -> Void = {}
    var onEditCaption: () -> Void = {}
    var onEndEditing: () -> Void = {}

    /// 고치는 중에만 쓰는 임시 글자. 저장은 개발이 붙인다.
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.between) {
            Text("\(scene.number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
                .padding(.top, 2)

            ThumbnailView(thumbnail: scene.thumbnail, cornerRadius: Tokens.Radius.thumbnail - 2)
                .frame(width: 44, height: 78)

            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                HStack(spacing: Tokens.Space.inner) {
                    RoleTag(role: scene.role)
                    Text(Copy.shortSeconds(scene.duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                caption
                actions
            }

            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.inner)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(isSelected ? Tokens.Palette.accent.opacity(0.10) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .strokeBorder(isSelected ? Tokens.Palette.accent : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var caption: some View {
        if isEditingCaption {
            // 고치기는 줄 **안에서** 한다. 따로 창을 띄우면 앞뒤 장면을 못 보면서 고치게 된다.
            TextField(Copy.Plan.Scenes.captionPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(1...3)
                .focused($isFocused)
                .onSubmit(onEndEditing)
                .onAppear {
                    draft = scene.caption
                    isFocused = true
                }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.caption.isEmpty ? Copy.Plan.Scenes.noCaption : scene.caption)
                    .font(.callout)
                    .foregroundStyle(scene.caption.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = scene.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if scene.captionCount > 1 {
                    Text(Copy.Plan.Scenes.moreCaptions(scene.captionCount))
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
    var onRestore: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.inner) {
            Image(systemName: "scissors")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(Copy.Plan.Scenes.removedGap(seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(Copy.Plan.Scenes.bringBack, action: onRestore)
                .buttonStyle(.link)
                .font(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.inner)
        .padding(.vertical, Tokens.Space.tight)
    }
}

#Preview("장면 목록") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID?
    SceneList(plan: SampleData.plan, selectedID: $selected, editingID: $editing)
        .frame(width: 420, height: 620)
}

#Preview("자막 고치는 중") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID? = "s4"
    SceneList(plan: SampleData.plan, selectedID: $selected, editingID: $editing)
        .frame(width: 420, height: 620)
}
