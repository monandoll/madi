import SwiftUI

/// 편집안 미리보기. **결과가 어떻게 생겼는지** 보여주는 자리다.
///
/// 여기 보이는 그림에는 자막이 들어 있다. 촬영본 썸네일(자막 없음)과 달라야 한다 —
/// 사람이 "지금 보는 게 원본인가 만든 건가" 를 헷갈리면 화면이 실패한 것이다.
/// 디자인 단계에서는 크리에이터 공개본 프레임을 그대로 읽는다. 자막을 흉내 내 그리지 않는다
/// (design-ai 지침 3 — 영상 안 자막은 `AGENTS.md §9` 실측값이고 디자인 대상이 아니다).
///
/// 개발이 붙을 때 이 자리는 `AVPlayer` + `AVSynchronizedLayer` 가 된다 (`AGENTS.md §7`).
/// 재생 막대는 QuickTime 문법 그대로다 — **타임라인이 아니다.** 트랙도 눈금자도 없다.
struct PlanPlayer: View {
    var thumbnail: Thumbnail
    /// 지금 위치와 전체 길이. 실제 재생은 개발이 붙인다.
    var position: Double
    var total: Double
    var onPlay: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        VStack(spacing: Tokens.Space.inner) {
            ThumbnailView(thumbnail: thumbnail, cornerRadius: Tokens.Radius.card)
                .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                .frame(maxHeight: .infinity)

            transport
        }
    }

    private var transport: some View {
        VStack(spacing: Tokens.Space.tight) {
            // 위치 막대. 끌어서 옮기는 것 말고는 아무 뜻이 없다.
            ProgressView(value: min(position, total), total: max(total, 0.001))
                .progressViewStyle(.linear)
                .controlSize(.small)

            HStack(spacing: Tokens.Space.inner) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill")
                }
                .help(Copy.Plan.Scenes.playFromHere)

                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                }
                .help(Copy.Action.play)

                Button(action: onNext) {
                    Image(systemName: "forward.end.fill")
                }

                Spacer()

                Text("\(Copy.duration(position)) / \(Copy.duration(total))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .imageScale(.small)
        }
    }
}

#Preview("재생 막대") {
    PlanPlayer(
        thumbnail: SampleData.planScenes[3].thumbnail,
        position: 6, total: 27
    )
    .frame(width: 220, height: 420)
    .padding()
}
