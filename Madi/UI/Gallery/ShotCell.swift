import SwiftUI

/// 갤러리 한 칸. 세로 그림 + 제목 + 한 줄 메타.
///
/// 제목은 두 줄까지 보여준다. 한 줄로 자르면 "골반이 틀어져있다면, 이 동작…" 처럼
/// 제목끼리 구별이 안 된다. 실제 제목이 길다는 걸 샘플 데이터가 알려준다.
struct ShotCell: View {
    var shot: ShotItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner - 2) {
            ThumbnailView(thumbnail: shot.thumbnail)
                .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    DurationBadge(seconds: shot.duration)
                }
                .overlay(alignment: .bottomLeading) {
                    if let fetch = shot.fetchProgress {
                        // 원본을 받는 중 — 얼마나 왔는지 보여 준다. 오래 걸릴 수 있다.
                        ProgressView(value: fetch)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .padding(Tokens.Space.tight + 1)
                    } else if shot.isMaking || shot.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(Tokens.Space.tight + 1)
                    }
                }
                // 받지 못한 원본은 그림을 흐리게 둔다. 붉은 표시는 없다 — 다시 가져오면 된다.
                .opacity(shot.problem == nil ? 1 : 0.45)
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail)
                        .strokeBorder(
                            isSelected ? Tokens.Palette.accent : .clear,
                            lineWidth: 3
                        )
                }

            Text(shot.title)
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            meta
        }
        .padding(Tokens.Space.tight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(isSelected ? Tokens.Palette.accent.opacity(0.10) : .clear)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shot.title)
        .accessibilityValue(Copy.duration(shot.duration))
    }

    private var meta: some View {
        HStack(spacing: Tokens.Space.tight) {
            if shot.problem != nil {
                Label(Copy.Photos.importFailedShort, systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Tokens.Palette.attention)
            } else if let fetch = shot.fetchProgress {
                Text(Copy.Photos.importFetchingOriginal(fetch))
            } else {
                stamp
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var stamp: some View {
        Text(Copy.shotStamp(shot.shotAt))
        if shot.isMaking {
                Text("·")
                Text(Copy.Gallery.Cell.making)
            } else if shot.isPreparing {
                // 넣자마자 도는 받아적기 · 사람 찾기 — 만드는 중이 아니다
                Text("·")
                Text(Copy.Gallery.Cell.preparing)
            } else if shot.hasResult {
                Text("·")
                Label(
                    Copy.Gallery.Cell.results(shot.results.count),
                    systemImage: "square.and.arrow.up.on.square"
                )
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
            }
    }
}

#Preview("칸") {
    HStack(alignment: .top, spacing: Tokens.Space.between) {
        ShotCell(shot: SampleData.shotsToday[0], isSelected: true)
        ShotCell(shot: SampleData.shotsToday[1], isSelected: false)
        ShotCell(shot: SampleData.shotsToday[2], isSelected: false)
    }
    .frame(width: 560)
    .padding()
}
