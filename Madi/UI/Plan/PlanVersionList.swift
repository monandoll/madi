import SwiftUI

/// 편집안 고르기. 툴바의 `편집안 2 ⌄` 를 누르면 나온다.
///
/// 편집안은 고칠 때마다 **새로 생기고 이전 것을 지우지 않는다** (`AGENTS.md §1-8`).
/// 그래서 몇 판이 쌓이고, 이름(`편집안 1` · `편집안 2`)만으로는 뭐가 뭔지 모른다.
/// 길이 · 장면 수 · 언제 만들었는지 · 결과물이 있는지를 같이 보여줘야 고를 수 있다.
///
/// **결과물이 있는 판을 표시하는 이유**: 이미 내보낸 편집안을 고르면 그건 "그때 올린 그것" 이다.
/// 사람이 찾는 게 대개 그거다.
struct PlanVersionList: View {
    var versions: [PlanVersion]
    var onPick: (PlanVersion) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Plan.Versions.header)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Tokens.Space.between)
                .padding(.top, Tokens.Space.between)
                .padding(.bottom, Tokens.Space.inner)

            ForEach(versions) { version in
                Button {
                    onPick(version)
                } label: {
                    HStack(alignment: .top, spacing: Tokens.Space.inner) {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(Tokens.Palette.accent)
                            .opacity(version.isCurrent ? 1 : 0)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(version.label)
                                .font(.callout.weight(version.isCurrent ? .semibold : .regular))
                            Text(Copy.Plan.Versions.meta(
                                duration: Copy.duration(version.duration),
                                scenes: Copy.scenes(version.sceneCount),
                                when: version.when
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: Tokens.Space.between)

                        if version.resultCount > 0 {
                            // 글자만 쓴다. 공유 아이콘을 붙였더니 누르면 내보내는 버튼으로 읽혔다.
                            Text(Copy.Plan.Versions.results(version.resultCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Tokens.Space.between)
                    .padding(.vertical, Tokens.Space.inner - 1)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(
                    version.isCurrent
                        ? AnyShapeStyle(Tokens.Palette.accent.opacity(0.10))
                        : AnyShapeStyle(Color.clear)
                )
            }

            Divider()
                .padding(.top, Tokens.Space.inner)

            Text(Copy.Plan.Versions.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Tokens.Space.between)
        }
        .frame(width: 300)
    }
}

#Preview("편집안 고르기") {
    PlanVersionList(versions: SampleData.planVersions)
}
