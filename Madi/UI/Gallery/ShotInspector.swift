import SwiftUI

/// 오른쪽 정보 패널. 고른 촬영본 하나에 대해 "이게 뭐고, 이걸로 뭘 만들었나" 를 답한다.
///
/// 보여주는 넷은 사람이 실제로 묻는 것들이다 — 언제 찍었나 · 얼마나 기나 ·
/// 말소리가 쓸 만한가 (자막이 되나) · 이걸로 이미 만든 게 있나.
/// 코덱 · 해상도 · 비트레이트는 보여주지 않는다 (AGENTS.md §1-5).
struct ShotInspector: View {
    var shot: ShotItem?
    /// 촬영본에서 나가는 길은 하나다 — 누르면 편집안이 열리고 AI 가 초안을 짜기 시작한다.
    /// 실제로 영상을 만드는 것은 장면 카드를 본 뒤 편집안 안에서 한다.
    var onMakeShort: (ShotItem) -> Void = { _ in }

    var body: some View {
        Group {
            if let shot {
                filled(shot)
            } else {
                ContentUnavailableView {
                    Label(Copy.Gallery.Info.noSelection, systemImage: "hand.tap")
                } description: {
                    EmptyView()
                }
            }
        }
    }

    private func filled(_ shot: ShotItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.section) {
                    ThumbnailView(thumbnail: shot.thumbnail)
                        .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                        .frame(maxWidth: 150)
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white, .black.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)

                    Text(shot.title)
                        .font(.headline)
                        .textSelection(.enabled)

                    facts(shot)

                    if !shot.results.isEmpty {
                        Divider()
                        results(shot)
                    }
                }
                .padding(Tokens.Space.section)
            }

            Divider()
            actions(shot)
        }
    }

    private func facts(_ shot: ShotItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Tokens.Space.between,
             verticalSpacing: Tokens.Space.inner - 2) {
            row(Copy.Gallery.Info.shotAt, Copy.dayTime(shot.shotAt))
            row(Copy.Gallery.Info.duration, Copy.duration(shot.duration))
            row(Copy.Gallery.Info.speech, shot.speech.label)
            row(Copy.Gallery.Info.results,
                shot.results.isEmpty
                    ? Copy.Gallery.Info.noResultYet
                    : Copy.count(shot.results.count))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
        }
        .font(.callout)
    }

    private func results(_ shot: ShotItem) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            ForEach(shot.results) { result in
                HStack(spacing: Tokens.Space.inner) {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.platform.label)
                        Text(result.planLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Tokens.Space.inner)
                    Text(result.when)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private func actions(_ shot: ShotItem) -> some View {
        Button {
            onMakeShort(shot)
        } label: {
            // 라벨을 늘려야 버튼이 패널 폭을 다 쓴다. 버튼에 `.frame` 을 걸면 버튼만 늘고
            // 안쪽 배경은 글자 폭에 붙어 있는다.
            Text(Copy.Action.makeShort)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(Tokens.Space.between)
    }
}

#Preview("정보 패널 · 결과물 있음") {
    ShotInspector(shot: SampleData.shotsToday[0])
        .frame(width: 280, height: 640)
}

#Preview("정보 패널 · 결과물 없음") {
    ShotInspector(shot: SampleData.shotsToday[1])
        .frame(width: 280, height: 640)
}

#Preview("정보 패널 · 고른 것 없음") {
    ShotInspector(shot: nil)
        .frame(width: 280, height: 640)
}
