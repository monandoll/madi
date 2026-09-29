import SwiftUI

/// 세로(9:16) 미리보기 한 장.
///
/// 그림이 없으면 **회색 자리표시**로 둔다. 자막이나 인물을 비슷하게 흉내 내서 그리지 않는다
/// (design-ai 지침 3 — 영상 안 스타일은 `AGENTS.md §9` 실측값이고 디자인 대상이 아니다).
struct ThumbnailView: View {
    var thumbnail: Thumbnail
    var cornerRadius: CGFloat = Tokens.Radius.thumbnail
    /// 그림이 칸보다 길쭉해서 잘릴 때 **어디를 가운데로** 둘지 (0 위 · 0.5 가운데 · 1 아래).
    /// 세로 영상을 가로 칸(가로 장면 띠)에 넣으면 가운데만 남아 얼굴이 잘린다 — 그때 위쪽으로 당긴다.
    var focusY: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(Tokens.Palette.placeholder)
            .overlay {
                if let image = nsImage {
                    if focusY == 0.5 {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        GeometryReader { box in
                            let scale = max(box.size.width / image.size.width, box.size.height / image.size.height)
                            let h = image.size.height * scale
                            let offset = min(0, max(box.size.height - h, box.size.height / 2 - h * focusY))
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: box.size.width, height: h)
                                .offset(y: offset)
                        }
                    }
                } else {
                    Image(systemName: "video")
                        .imageScale(.large)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }

    private var nsImage: NSImage? {
        guard let url = thumbnail.fileURL else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// 썸네일 위 오른쪽 아래에 앉는 길이 뱃지. 사진 앱 동영상 칸과 같은 자리.
struct DurationBadge: View {
    var seconds: Double

    var body: some View {
        Text(Copy.duration(seconds))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Space.tight + 1)
            .padding(.vertical, Tokens.Space.hairline)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(Tokens.Space.tight + 1)
    }
}

#Preview("썸네일") {
    HStack(spacing: Tokens.Space.between) {
        ThumbnailView(thumbnail: SampleData.shotsToday[0].thumbnail)
            .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) { DurationBadge(seconds: 42) }
        ThumbnailView(thumbnail: .none)
            .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
    }
    .frame(height: 220)
    .padding()
}
