import SwiftUI

/// 내보내기 — 이 앱에서 **밖으로 나가는 유일한 문**이다.
///
/// 코덱 · 비트레이트 · 파일 이름을 묻지 않는다. 묻는 건 "어디로" 하나다.
/// 아이폰에서 확인하려면 사진 앱으로 가야 하므로 그게 첫 줄이다 (`AGENTS.md §2`).
struct ExportSheet: View {
    var targets: [ExportTarget]
    var onExport: (ExportTarget) -> Void
    var onCancel: () -> Void

    @State private var selected: ExportTarget.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.section) {
            Text(Copy.Results.Export.title)
                .font(.headline)

            VStack(spacing: Tokens.Space.inner) {
                ForEach(targets) { target in
                    row(target)
                }
            }

            HStack {
                Spacer()
                Button(Copy.Action.cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(Copy.Results.Export.confirm) {
                    if let target = targets.first(where: { $0.id == selected }) {
                        onExport(target)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding(Tokens.Space.page)
        .frame(width: 420)
        .onAppear { selected = targets.first?.id }
    }

    private func row(_ target: ExportTarget) -> some View {
        Button {
            selected = target.id
        } label: {
            HStack(spacing: Tokens.Space.between) {
                Image(systemName: target.symbol)
                    .imageScale(.large)
                    .frame(width: 24)
                    .foregroundStyle(selected == target.id ? Tokens.Palette.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.title)
                        .font(.callout.weight(.medium))
                    Text(target.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected == target.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Tokens.Palette.accent)
                }
            }
            .padding(Tokens.Space.between)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            selected == target.id
                ? AnyShapeStyle(Tokens.Palette.accent.opacity(0.12))
                : AnyShapeStyle(.quaternary.opacity(0.4)),
            in: .rect(cornerRadius: Tokens.Radius.card)
        )
    }
}

#Preview("내보내기") {
    ExportSheet(targets: SampleData.exportTargets, onExport: { _ in }, onCancel: {})
}
