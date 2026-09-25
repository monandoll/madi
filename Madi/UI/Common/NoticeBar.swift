import SwiftUI

/// 화면 위에 서는 한 줄. **막힌 것도 여기서 말한다.**
///
/// 알림창을 띄우지 않고, 붉은색도 쓰지 않는다. 사람이 손대면 되는 일이면 실패가 아니라
/// "다음 행동이 있는 상태" 다 (`AGENTS.md §1-6`). 그래서 이 줄에는 **항상 버튼이 같이 온다.**
///
/// 채팅이 있는 화면(편집안)은 채팅으로 말한다. 이 줄은 채팅이 없는 화면(결과물)이 쓴다.
struct NoticeBar: View {
    var notice: ScreenNotice
    var onAction: (ChatChoice) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.between) {
            Image(systemName: notice.symbol)
                .foregroundStyle(Tokens.Palette.attention)

            Text(notice.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Tokens.Space.between)

            ForEach(notice.actions) { action in
                if action.isPrimary {
                    Button(action.title) { onAction(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button(action.title) { onAction(action) }
                        .controlSize(.small)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.section)
        .padding(.vertical, Tokens.Space.inner + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.attention.opacity(0.10))
    }
}

#Preview("알림 줄") {
    NoticeBar(notice: SampleData.exportFailedNotice)
        .frame(width: 720)
}
