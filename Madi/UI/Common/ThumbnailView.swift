import SwiftUI

/// 세로(9:16) 미리보기 한 장.
///
/// 그림이 없으면 **회색 자리표시**로 둔다. 자막이나 인물을 비슷하게 흉내 내서 그리지 않는다
/// (design-ai 지침 3 — 영상 안 스타일은 `AGENTS.md §9` 실측값이고 디자인 대상이 아니다).
struct ThumbnailView: View {
    var thumbnail: Thumbnail
    var cornerRadius: CGFloat = Tokens.Radius.thumbnail

    var body: some View {
        Rectangle()
            .fill(Tokens.Palette.placeholder)
            .overlay {
                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
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
