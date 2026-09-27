import SwiftUI

/// 오른쪽 대화 패널. 요청도 여기서 하고, **막힌 것도 여기서 말한다.**
///
/// 알림창(`NSAlert`)을 띄우지 않는다. 오류는 AI 말투로 대화 안에 들어오고 다음 행동 버튼이
/// 같이 온다 (AGENTS.md §1-6). 붉은색은 진짜 실패에만 쓰는데, 지금까지 나온 상황 중
/// 붉은색을 쓸 만한 건 하나도 없었다 — 소리가 없는 것도, AI 미연결도 실패가 아니다.
struct ChatPanel: View {
    var messages: [ChatMessage]
    var chips: [String]
    /// 지금 AI 가 일하는 중이면 입력칸 문구가 바뀌고 보내기가 잠긴다.
    var isBusy: Bool = false

    var onSend: (String) -> Void = { _ in }
    var onChip: (String) -> Void = { _ in }
    var onChoice: (ChatChoice) -> Void = { _ in }
    var onPlayFromStart: () -> Void = {}
    var onUndo: () -> Void = {}
    var onOpenResult: (ResultRef) -> Void = { _ in }
    var onRetrySend: (String) -> Void = { _ in }

    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.between) {
                    ForEach(messages) { message in
                        row(message)
                    }
                }
                .padding(Tokens.Space.between)
            }

            Divider()
            composer
        }
    }

    @ViewBuilder
    private func row(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
            if let stamp = message.stamp {
                Text(stamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            switch message.kind {
            case .user(let text):
                Bubble(text: text, isUser: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .userNotSent(let text):
                // 못 보낸 말도 그대로 남긴다. 사람이 쓴 게 사라지면 다시 쓰게 된다.
                VStack(alignment: .trailing, spacing: Tokens.Space.tight) {
                    Bubble(text: text, isUser: true)
                        .opacity(0.5)
                    HStack(spacing: Tokens.Space.inner) {
                        Text(Copy.Chat.NotSent.mark)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(Copy.Chat.NotSent.retry) { onRetrySend(text) }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            case .assistant(let text):
                Bubble(text: text, isUser: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .summary(let summary):
                SummaryCard(summary: summary, onPlayFromStart: onPlayFromStart, onUndo: onUndo)
            case .choices(let choices):
                VStack(alignment: .leading, spacing: Tokens.Space.inner) {
                    ForEach(choices) { choice in
                        ChoiceButton(choice: choice) { onChoice(choice) }
                    }
                }
            case .result(let result):
                ResultCard(result: result) { onOpenResult(result) }
            case .typing:
                TypingDots()
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            // 추천 칩. 말로 하라고만 하면 무엇을 말해야 할지 모른다.
            // **줄바꿈한다.** 가로로 흘리면 오른쪽 끝에서 "유튜…" 처럼 잘려서,
            // 거기 뭐가 더 있는지 모르는 채로 지나간다.
            FlowLayout(spacing: Tokens.Space.inner - 2, lineSpacing: Tokens.Space.inner - 2) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip) { onChip(chip) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .disabled(isBusy)
                }
            }
            .padding(.horizontal, Tokens.Space.between)

            HStack(spacing: Tokens.Space.inner) {
                TextField(
                    isBusy ? Copy.Chat.inputPromptBusy : Copy.Chat.inputPrompt,
                    text: $draft
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .help(Copy.Chat.send)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Tokens.Space.between)
        }
        .padding(.vertical, Tokens.Space.between)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
        draft = ""
    }
}

/// 말풍선. 사람 말은 오른쪽 · 진한 면, AI 말은 왼쪽 · 옅은 면. 메시지 앱과 같은 문법이다.
private struct Bubble: View {
    var text: String
    var isUser: Bool

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(isUser ? .white : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Tokens.Space.between)
            .padding(.vertical, Tokens.Space.inner)
            .background(
                isUser ? AnyShapeStyle(Tokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: .rect(cornerRadius: Tokens.Radius.card + 4)
            )
            .frame(maxWidth: 240, alignment: isUser ? .trailing : .leading)
    }
}

/// 무엇이 바뀌었는지 표로. 문장으로 풀면 길고, 숫자만 있으면 무슨 뜻인지 모른다.
private struct SummaryCard: View {
    var summary: EditSummary
    var onPlayFromStart: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.inner,
                 verticalSpacing: Tokens.Space.tight) {
                ForEach(summary.lines) { line in
                    GridRow {
                        Text(line.label)
                        Spacer(minLength: Tokens.Space.inner)
                        Text(line.value)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)

            HStack(spacing: Tokens.Space.inner) {
                Button(Copy.Chat.Summary.playFromStart, action: onPlayFromStart)
                if summary.canUndo {
                    Button(Copy.Chat.Summary.undo, action: onUndo)
                }
            }
            .controlSize(.small)
        }
        .padding(Tokens.Space.between)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
    }
}

/// 막혔을 때 주는 다음 행동. **버튼만 주지 않고 왜 그걸 고르는지 한 줄을 같이 준다.**
private struct ChoiceButton: View {
    var choice: ChatChoice
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                Text(choice.title)
                    .font(.callout.weight(.medium))
                if let detail = choice.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.inner + 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            choice.isPrimary
                ? AnyShapeStyle(Tokens.Palette.accent.opacity(0.12))
                : AnyShapeStyle(.quaternary.opacity(0.4)),
            in: .rect(cornerRadius: Tokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .strokeBorder(
                    choice.isPrimary ? Tokens.Palette.accent.opacity(0.5) : .clear,
                    lineWidth: 1
                )
        }
    }
}

/// 다 만든 영상. 만들기가 끝나면 대화에 **카드로** 붙는다 — 화면을 옮기지 않아도
/// 방금 만든 게 뭔지 보이고, 결과물 칸으로 갈 수 있다.
private struct ResultCard: View {
    var result: ResultRef
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.between) {
            ThumbnailView(thumbnail: result.thumbnail, cornerRadius: Tokens.Radius.thumbnail)
                .frame(width: 44, height: 78)

            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                Text(Copy.Chat.Result.done)
                    .font(.callout.weight(.medium))
                Text("\(result.platform.label) · \(Copy.duration(result.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(Copy.Chat.Result.open, action: onOpen)
                    .controlSize(.small)
                    .padding(.top, Tokens.Space.hairline)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.between)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
    }
}

/// AI 가 쓰는 중. 퍼센트를 지어내지 않는다.
private struct TypingDots: View {
    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, Tokens.Space.between)
        .padding(.vertical, Tokens.Space.inner + 2)
        .background(.quaternary, in: .rect(cornerRadius: Tokens.Radius.card + 4))
    }
}

#Preview("대화 · 편집안 나옴") {
    ChatPanel(messages: SampleData.chat, chips: SampleData.chatChips)
        .frame(width: 300, height: 620)
}

#Preview("대화 · 만드는 중") {
    ChatPanel(messages: SampleData.chatPreparing, chips: SampleData.chatChips, isBusy: true)
        .frame(width: 300, height: 620)
}

#Preview("대화 · 다 만듦") {
    ChatPanel(messages: SampleData.chatMade, chips: SampleData.chatChips)
        .frame(width: 320, height: 620)
}

#Preview("대화 · 막힘") {
    ChatPanel(messages: SampleData.chatStuck, chips: SampleData.chatChips)
        .frame(width: 300, height: 620)
}
