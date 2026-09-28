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
    /// 머리줄 둘째 줄 — "편집안 2에 대해 이야기 중" · "편집안 만드는 중" · "새 촬영본" (2026-09-29 시안).
    var status: String? = nil

    var onSend: (String) -> Void = { _ in }
    var onChip: (String) -> Void = { _ in }
    var onChoice: (ChatChoice) -> Void = { _ in }
    var onPlayFromStart: () -> Void = {}
    var onUndo: () -> Void = {}
    var onOpenResult: (ResultRef) -> Void = { _ in }
    var onRetrySend: (String) -> Void = { _ in }
    /// 입력칸의 멈추기(■) — AI 가 일하는 동안.
    var onStop: () -> Void = {}

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    // 간격은 줄마다 다르다 — 같은 사람 6 · 말하는 사람이 바뀌면 18 · 날짜 줄 바로 뒤 0 (시안).
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            row(message, index: index)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, Tokens.Space.between)
                }
                .onChange(of: messages.last?.id) { _, last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            composer
        }
    }

    /// 머리줄 — "마디" 와 지금 무엇을 이야기하는지 (시안 48pt).
    private var header: some View {
        VStack(spacing: 2) {
            Text(Copy.Chat.Header.name)
                .font(.callout.weight(.bold))
            if let status {
                HStack(spacing: 5) {
                    Circle().fill(Tokens.Palette.ok).frame(width: 6, height: 6)
                    Text(status)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }

    // MARK: 줄

    private enum Speaker { case user, ai, card }

    private func speaker(_ kind: ChatMessage.Kind) -> Speaker {
        switch kind {
        case .user, .userNotSent: .user
        case .assistant, .typing, .summary, .choices: .ai
        case .result: .card
        }
    }

    /// 위 간격 — 첫 줄 · 날짜 줄 바로 뒤 0, 같은 사람 6, 바뀌면 18, 결과 카드 6.
    private func gap(_ index: Int) -> CGFloat {
        let message = messages[index]
        guard index > 0, message.stamp == nil else { return 0 }
        let now = speaker(message.kind), before = speaker(messages[index - 1].kind)
        if now == .card || before == .card { return 6 }
        return now == before ? 6 : 18
    }

    /// 꼬리 — 같은 사람 말이 이어지는 묶음의 **마지막** 말풍선에만 (메시지 앱처럼).
    private func hasTail(_ index: Int) -> Bool {
        let now = speaker(messages[index].kind)
        guard index + 1 < messages.count else { return true }
        let next = messages[index + 1]
        return next.stamp != nil || speaker(next.kind) != now
    }

    @ViewBuilder
    private func row(_ message: ChatMessage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stamp = message.stamp {
                // "**오늘** 오후 2:20" — 날은 굵게 (시안)
                stampText(stamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            Group {
                switch message.kind {
                case .user(let text):
                    Bubble(text: text, isUser: true, tail: hasTail(index))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                case .userNotSent(let text):
                    // 못 보낸 말도 그대로 남긴다. 사람이 쓴 게 사라지면 다시 쓰게 된다.
                    VStack(alignment: .trailing, spacing: Tokens.Space.tight) {
                        Bubble(text: text, isUser: true, tail: hasTail(index))
                            .opacity(0.5)
                        HStack(spacing: Tokens.Space.inner) {
                            Text(Copy.Chat.NotSent.mark)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(Copy.Chat.NotSent.retry) { onRetrySend(text) }
                                .buttonStyle(.accentLink)
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                case .assistant(let text):
                    Bubble(text: text, isUser: false, tail: hasTail(index))
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
            .padding(.top, gap(index))
        }
    }

    private func stampText(_ stamp: String) -> Text {
        guard let space = stamp.firstIndex(of: " ") else { return Text(stamp) }
        return Text(stamp[..<space]).fontWeight(.semibold) + Text(stamp[space...])
    }

    // MARK: 입력

    private var composer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            // 추천 칩. 말로 하라고만 하면 무엇을 말해야 할지 모른다.
            // **줄바꿈한다.** 가로로 흘리면 오른쪽 끝에서 "유튜…" 처럼 잘려서,
            // 거기 뭐가 더 있는지 모르는 채로 지나간다.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button { onChip(chip) } label: {
                        Text(chip)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(.background, in: .capsule)
                            .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
            .opacity(isBusy ? 0.4 : 1)
            .padding(.horizontal, Tokens.Space.between)

            // 둥근 입력칸 (시안 36pt · 모서리 18). 쓰는 중이면 옅은 강조 테두리.
            HStack(spacing: Tokens.Space.tight) {
                if isBusy {
                    Text(Copy.Chat.inputPromptBusy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onStop) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .frame(width: 26, height: 26)
                            .background(Color.secondary, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help(Copy.Chat.stop)
                } else {
                    TextField(Copy.Chat.inputPrompt, text: $draft)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($fieldFocused)
                        .onSubmit { send() }
                    if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { send() } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Tokens.Palette.accent, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .help(Copy.Chat.send)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .frame(height: 36)
            .background(isBusy ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.background),
                        in: .rect(cornerRadius: Tokens.Radius.bubble))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.bubble)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.bubble)
                    .stroke(Tokens.Palette.accent.opacity(fieldFocused ? 0.18 : 0), lineWidth: 3)
            }
            .padding(.horizontal, Tokens.Space.between)
        }
        .padding(.top, 6)
        .padding(.bottom, Tokens.Space.between)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
        draft = ""
    }
}

/// 말풍선. 사람 말은 오른쪽 · 강조색, AI 말은 왼쪽 · 옅은 면. 메시지 앱과 같은 문법이다.
/// 묶음의 마지막 말풍선에만 꼬리가 붙는다 (2026-09-29 시안).
private struct Bubble: View {
    var text: String
    var isUser: Bool
    var tail: Bool

    var body: some View {
        Text(text)
            .font(.callout)
            .lineSpacing(1)
            .foregroundStyle(isUser ? .white : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.top, 7)
            .padding(.bottom, 8)
            .background(
                BubbleShape(tail: tail ? (isUser ? .right : .left) : nil)
                    .fill(isUser ? AnyShapeStyle(Tokens.Palette.accent) : AnyShapeStyle(.quaternary))
            )
            // 최대 폭 — 사람 76% · AI 80% (시안). 패널 폭(약 300)에 맞춰 점 수로
            .frame(maxWidth: isUser ? 228 : 240, alignment: isUser ? .trailing : .leading)
    }
}

/// 모서리 18 둥근 말풍선 + (있으면) 아래 모서리 꼬리.
private struct BubbleShape: Shape {
    enum Side { case left, right }
    var tail: Side?

    func path(in rect: CGRect) -> Path {
        let p = Path(roundedRect: rect, cornerRadius: Tokens.Radius.bubble)
        guard let tail else { return p }
        let y = rect.maxY
        var t = Path()
        switch tail {
        case .right:
            let x = rect.maxX
            t.move(to: CGPoint(x: x - 14, y: y - 12))
            t.addLine(to: CGPoint(x: x - 2, y: y - 14))
            t.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x - 1, y: y - 3))
            t.addQuadCurve(to: CGPoint(x: x - 14, y: y), control: CGPoint(x: x - 4, y: y + 1))
        case .left:
            let x = rect.minX
            t.move(to: CGPoint(x: x + 14, y: y - 12))
            t.addLine(to: CGPoint(x: x + 2, y: y - 14))
            t.addQuadCurve(to: CGPoint(x: x - 6, y: y), control: CGPoint(x: x + 1, y: y - 3))
            t.addQuadCurve(to: CGPoint(x: x + 14, y: y), control: CGPoint(x: x + 4, y: y + 1))
        }
        t.closeSubpath()
        // 합쳐서 그린다 — 그냥 덧붙이면 그리는 방향이 반대인 겹친 곳이 비어서 꼬리가 떨어져 보였다
        return p.union(t)
    }
}

/// 무엇이 바뀌었는지 — 머리줄(편집안 · 규격 · 길이) + 표 + 아래 반반 버튼 (2026-09-29 시안).
private struct SummaryCard: View {
    var summary: EditSummary
    var onPlayFromStart: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let version = summary.versionLabel {
                HStack(spacing: 10) {
                    ThumbnailView(thumbnail: summary.thumbnail, cornerRadius: 4)
                        .frame(width: 22, height: 39)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version).font(.caption.weight(.bold))
                        if let detail = summary.detail {
                            Text(detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Tokens.Space.between)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.3))
                Divider()
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
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
            .font(.caption)
            .padding(.horizontal, Tokens.Space.between)
            .padding(.vertical, 10)

            Divider()
            HStack(spacing: 0) {
                Button(action: onPlayFromStart) {
                    Text(Copy.Chat.Summary.playFromStart)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(.rect)
                }
                if summary.canUndo {
                    Divider().frame(height: 32)
                    Button(action: onUndo) {
                        Text(Copy.Chat.Summary.undo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(.rect)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .background(.background, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5) }
        .clipShape(.rect(cornerRadius: 16))
        .frame(maxWidth: 240, alignment: .leading)
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

/// AI 가 쓰는 중 — 점 셋이 차례로 통통 (시안 `madiDot` 1.2초). 퍼센트를 지어내지 않는다.
private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Tokens.Space.tight) {
                ForEach(0..<3, id: \.self) { i in
                    // 0 · 60 · 100% 쉬고 30% 에 올라온다 (시안 keyframes)
                    let phase = ((t - Double(i) * 0.15) / 1.2).truncatingRemainder(dividingBy: 1)
                    let lift = phase < 0.3 ? phase / 0.3 : phase < 0.6 ? (0.6 - phase) / 0.3 : 0
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * max(0, lift))
                        .offset(y: -2 * max(0, lift))
                }
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(BubbleShape(tail: .left).fill(.quaternary))
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
