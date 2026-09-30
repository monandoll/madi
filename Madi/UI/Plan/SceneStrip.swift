import SwiftUI

/// 장면 **가로 띠** — 창이 넓을 때 (2026-09-29 사용자 결정 "창 크기 따라 둘 다", 시안 `02-Editor-v2`).
///
/// 좁은 창에서는 세로 목록(`SceneList`)이다. 가로 띠는 1100pt 창에서 9개 중 2~3개만 보여 훑을 수 없었다
/// (decisions.md "장면을 세로 목록으로"). 넓은 창에서는 편집 앱(캡컷 · 프리미어)처럼 옆으로 늘어선 카드가 익숙해서
/// 둘 다 둔다. **같은 값 · 같은 행동**을 쓴다 — 보이는 모양만 다르다.
///
/// 타임라인이 아니다 (`§16`). 트랙도 눈금자도 없다 — 순서대로 놓인 카드일 뿐이다.
struct SceneStrip: View {
    var plan: PlanView
    @Binding var selectedID: SceneCardItem.ID?
    @Binding var editingID: SceneCardItem.ID?
    var isReadOnly = false
    var readOnlyNote: String?

    var onRemove: (SceneCardItem) -> Void = { _ in }
    var onExtend: (SceneCardItem) -> Void = { _ in }
    var onShorten: (SceneCardItem) -> Void = { _ in }
    var onPlayFrom: (SceneCardItem) -> Void = { _ in }
    var onRestoreGap: (SceneCardItem) -> Void = { _ in }
    var onMove: (IndexSet, Int) -> Void = { _, _ in }
    var onCommitCaption: (SceneCardItem, String, String?) -> Void = { _, _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 6) {
                        ForEach(plan.scenes) { scene in
                            card(scene)
                            // 뺀 쉬는 구간은 지우지 않고 카드로 남긴다 — AI 판단을 되돌릴 유일한 길이다.
                            if let gap = scene.removedGapAfter {
                                GapCard(seconds: gap, isReadOnly: isReadOnly) { onRestoreGap(scene) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
                .onChange(of: selectedID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .disabled(isReadOnly)
            .opacity(isReadOnly ? 0.5 : 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.inner) {
            Text(Copy.Plan.Scenes.header(count: plan.scenes.count, total: Copy.duration(plan.targetDuration)))
                .font(.headline)
            if let hint = isReadOnly ? readOnlyNote : (plan.scenes.count > 1 ? Copy.Plan.Scenes.reorderHint : nil) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func card(_ scene: SceneCardItem) -> some View {
        SceneStripCard(
            scene: scene,
            isSelected: scene.id == selectedID,
            isEditingCaption: scene.id == editingID,
            isReadOnly: isReadOnly,
            onRemove: { onRemove(scene) },
            onExtend: { onExtend(scene) },
            onEditCaption: { editingID = scene.id },
            onCommit: { text in
                editingID = nil
                // 카드에는 영문 칸이 없다 — nil 이면 영문은 그대로 둔다 (SceneEdits)
                onCommitCaption(scene, text, nil)
            }
        )
        .id(scene.id)
        .onTapGesture { selectedID = scene.id }
        .contextMenu {
            if !isReadOnly {
                SceneMenuItems(
                    onEditCaption: { editingID = scene.id }, onExtend: { onExtend(scene) },
                    onShorten: { onShorten(scene) }, onPlayFrom: { onPlayFrom(scene) }, onRemove: { onRemove(scene) }
                )
            }
        }
        // 끌어서 순서 바꾸기 — 다른 카드 위에 놓으면 그 자리로 간다
        .draggable(scene.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, id != scene.id,
                  let from = plan.scenes.firstIndex(where: { $0.id == id }),
                  let to = plan.scenes.firstIndex(where: { $0.id == scene.id }) else { return false }
            onMove(IndexSet(integer: from), to > from ? to + 1 : to)
            return true
        }
    }
}

/// 가로 띠 카드 한 장 — 그림(번호 · 길이) · 역할 · 자막 두 줄 · `− 빼기 | + 늘리기 | ✎ 자막`.
struct SceneStripCard: View {
    var scene: SceneCardItem
    var isSelected: Bool
    var isEditingCaption: Bool
    var isReadOnly: Bool

    var onRemove: () -> Void = {}
    var onExtend: () -> Void = {}
    var onEditCaption: () -> Void = {}
    var onCommit: (String) -> Void = { _ in }

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 세로 영상을 가로 칸에 넣는다 — 얼굴이 보이게 위쪽을 가운데로 (focusY)
            ThumbnailView(thumbnail: scene.thumbnail, cornerRadius: 8, focusY: 0.35)
                .frame(height: 96)
                .overlay(alignment: .topLeading) { badge("\(scene.number)").padding(5) }
                .overlay(alignment: .bottomTrailing) { badge(Copy.shortSeconds(scene.duration)).padding(5) }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Tokens.Palette.accent, lineWidth: 3)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                }

            RoleTag(role: scene.role)

            if isEditingCaption {
                TextField(Copy.Plan.Scenes.captionPlaceholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isFocused)
                    .onSubmit { onCommit(draft) }
                    .onAppear { draft = scene.caption; isFocused = true }
                    .frame(minHeight: 34, alignment: .top)
            } else {
                Text(scene.caption.isEmpty ? Copy.Plan.Scenes.noCaption : scene.caption)
                    .font(.caption)
                    .foregroundStyle(scene.caption.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                    .onTapGesture(count: 2) { if !isReadOnly { onEditCaption() } }
            }

            actions
        }
        .padding(6)
        .frame(width: 172)
        .background(isSelected ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
    }

    /// `− 빼기 | + 늘리기 | ✎ 자막` — 한 덩어리 막대 (시안 22pt).
    private var actions: some View {
        HStack(spacing: 0) {
            segment("minus", Copy.Plan.Scenes.remove, action: onRemove)
            Divider().padding(.vertical, 5)
            segment("plus", Copy.Plan.Scenes.extendShort, action: onExtend)
            Divider().padding(.vertical, 5)
            segment("pencil", Copy.Plan.Scenes.editCaption, action: onEditCaption)
        }
        .frame(height: 22)
        .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: 6))
        .disabled(isReadOnly)
    }

    private func segment(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(title)
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// 가로 띠의 뺀 쉬는 구간 카드 — 좁게, 되돌리기 하나.
private struct GapCard: View {
    var seconds: Double
    var isReadOnly: Bool
    var onRestore: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(Copy.Plan.Scenes.gapTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Copy.shortSeconds(seconds))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if !isReadOnly {
                Button(Copy.Plan.Scenes.bringBack, action: onRestore)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(.background, in: .capsule)
                    .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
                    .padding(.top, 6)
            }
        }
        .padding(8)
        .frame(width: 76, height: 196)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 6))
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
}

#Preview("장면 가로 띠") {
    @Previewable @State var selected: SceneCardItem.ID? = "s4"
    @Previewable @State var editing: SceneCardItem.ID?
    SceneStrip(plan: SampleData.plan, selectedID: $selected, editingID: $editing)
        .frame(width: 900, height: 280)
}
