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
    /// 재생할 영상 (이 판의 결과물). 있으면 썸네일 · 자리표시 막대 대신 **앱 안에서 재생**한다 (개발이 넣음, viewdata-map ⑩).
    var url: URL? = nil

    var body: some View {
        if let url {
            // 영상 + 같은 꼴의 재생 막대 (MediaPlayerView.swift)
            PlanVideo(url: url)
                .id(url)   // 다른 판으로 바뀌면 옛 재생기를 멈추고 새로 만든다
        } else {
            // 아직 영상이 없는 판 (사람이 고친 판 · 만드는 중). 누를 수 없는 재생 막대를 두면 눌러도 아무 일이 없어
            // 고장 난 것처럼 보였다 — 그림과 한 줄만 둔다 (2026-09-30)
            VStack(spacing: Tokens.Space.inner) {
                ThumbnailView(thumbnail: thumbnail, cornerRadius: Tokens.Radius.card)
                    .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                    .frame(maxHeight: .infinity)

                Text(Copy.Player.notMadeYet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
