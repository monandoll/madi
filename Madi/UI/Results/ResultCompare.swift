import SwiftUI

/// 결과물 하나를 펼쳐 본 것. **이전 버전과 나란히 두는 게 기본이다.**
///
/// 크리에이터가 결과물 화면에서 진짜 묻는 건 "이게 저번 것보다 나아졌나" 하나다.
/// 글로 설명하는 것보다 두 개를 같이 보여주는 게 빠르다. 이전 버전이 없으면 하나만 보여준다.
struct ResultCompare: View {
    var detail: ResultDetail
    var mode: CompareMode

    var onPlay: () -> Void = {}

    var body: some View {
        // 스크롤로 감싼다. 창이 낮을 때 늘어난 미리보기가 툴바 밑으로 비집고 들어가는 걸 막는다.
        ScrollView {
            VStack(spacing: Tokens.Space.section) {
                Text(detail.shotTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: Tokens.Space.section) {
                    if showsPrevious, let previous = detail.previous {
                        pane(previous, label: Copy.Results.Compare.before, isCurrent: false)
                    }
                    pane(detail.current, label: Copy.Results.Compare.now, isCurrent: true)
                }

                Button(showsPrevious ? Copy.Results.Compare.playBoth : Copy.Results.Compare.play,
                       systemImage: "play.fill",
                       action: onPlay)
                .controlSize(.small)

                changes
            }
            .padding(Tokens.Space.section)
        }
    }

    private var showsPrevious: Bool { mode == .sideBySide && detail.previous != nil }

    private func pane(_ result: ResultRef, label: String, isCurrent: Bool) -> some View {
        VStack(spacing: Tokens.Space.inner) {
            HStack(spacing: Tokens.Space.tight + 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? Tokens.Palette.accent : .secondary)
                Text(result.planLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 세로 그림이라 키우면 금방 화면을 다 먹는다. 견줄 수 있을 만큼만 키운다.
            ThumbnailView(thumbnail: result.thumbnail, cornerRadius: Tokens.Radius.card)
                .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                .frame(maxHeight: 300)

            Text("\(Copy.duration(result.duration)) · \(Copy.scenes(result.sceneCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var changes: some View {
        if detail.previous != nil, !detail.changes.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.inner) {
                Text(Copy.Results.Compare.changesFrom(detail.previous?.planLabel ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 달라진 점은 **사람 말로** 쓴다. "cropFocus 0.42 → 0.55" 같은 건 안 쓴다.
                // `Grid` 를 쓰면 행 안의 `Spacer` 가 줄을 세로로도 늘려서 표가 벌어진다.
                VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                    ForEach(detail.changes) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.section) {
                            Text(line.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Text(line.value)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .font(.callout)
            }
            .padding(Tokens.Space.between)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
        } else {
            Text(Copy.Results.Compare.firstResult)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("나란히") {
    ResultCompare(detail: SampleData.resultDetail, mode: .sideBySide)
        .frame(width: 620, height: 620)
}

#Preview("하나만") {
    ResultCompare(detail: SampleData.resultDetail, mode: .single)
        .frame(width: 620, height: 620)
}

#Preview("첫 결과물") {
    ResultCompare(detail: SampleData.resultDetailFirst, mode: .sideBySide)
        .frame(width: 620, height: 620)
}
