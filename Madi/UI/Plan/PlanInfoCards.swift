import SwiftUI

/// "이 편집안" — AI 가 무엇을 했는지 네 줄로. 채팅을 다시 읽지 않아도 알 수 있어야 한다.
///
/// 자막 자리가 여기 있는 이유: **자막 위치는 영상마다 하나**이지 장면마다 고르는 게 아니다
/// (`CaptionSlot`, `docs/findings/2026-09-25-caption-position-10.md`).
/// 장면 카드에 두면 장면마다 다르게 할 수 있다는 뜻이 되어 버린다.
struct PlanInfoCard: View {
    var plan: PlanView

    var body: some View {
        InfoCard(title: Copy.Plan.Info.header) {
            row(Copy.Plan.Info.length, lengthLine)
            row(Copy.Plan.Info.scenes, sceneLine)
            row(Copy.Plan.Info.format, "\(plan.platform.label) (\(Copy.Platform.verticalNote))")
            // 자막 자리는 **영상이 주로 보여주는 몸의 범위**로 정해진다.
            // "위쪽 · 아래쪽" 같은 위치어를 쓰지 않는다 (기각된 가설 — ViewData 의 CaptionSlot 주석).
            row(Copy.Plan.Info.caption, plan.captionSlot.label)
        }
    }

    /// 짧은 촬영본은 자를 게 없어서 길이가 그대로다. 그때 `0:05 → 0:05` 라고 쓰면
    /// 뭔가 한 것처럼 읽힌다. 바뀐 게 없으면 한 값만 쓴다.
    private var lengthLine: String {
        let source = Copy.duration(plan.sourceDuration)
        let target = Copy.duration(plan.targetDuration)
        return source == target ? target : Copy.Plan.Info.lengthChange(from: source, to: target)
    }

    private var sceneLine: String {
        let scenes = Copy.count(plan.scenes.count)
        guard plan.removedGapCount > 0 else { return scenes }
        return scenes + " · " + Copy.Plan.Info.removedGaps(
            count: plan.removedGapCount, seconds: plan.removedGapSeconds
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "지금 보는 장면" — 재생 막대가 어디를 보고 있는지 글자로도 말한다.
struct NowPlayingCard: View {
    var scene: SceneCardItem

    var body: some View {
        InfoCard(title: Copy.Plan.Info.nowPlaying) {
            GridRow {
                Text("\(scene.number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: Tokens.Space.hairline) {
                    RoleTag(role: scene.role)
                    Text(scene.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondary = scene.secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(Copy.shortSeconds(scene.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(Tokens.Space.between)
        }
    }
}

/// 역할은 색 점 + **글자**로 같이 말한다. 색만으로 뜻을 주지 않는다.
struct RoleTag: View {
    var role: SceneRoleKind

    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            Circle()
                .fill(role.tint)
                .frame(width: 6, height: 6)
            Text(role.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 옅은 면에 제목 한 줄 + 내용. macOS 설정 창의 묶음과 같은 급으로 보이게 둔다.
struct InfoCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.between,
                 verticalSpacing: Tokens.Space.inner - 2) {
                content()
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Space.between)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
    }
}

#Preview("편집안 정보") {
    VStack(spacing: Tokens.Space.between) {
        PlanInfoCard(plan: SampleData.plan)
        NowPlayingCard(scene: SampleData.planScenes[3])
    }
    .frame(width: 360)
    .padding()
}

#Preview("자막을 위로 올린 편집안") {
    PlanInfoCard(plan: SampleData.planUpperCaption)
        .frame(width: 360)
        .padding()
}
