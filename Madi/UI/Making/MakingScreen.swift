import SwiftUI

/// 만드는 중 — 지금 돌고 있는 것, 기다리는 것, 멈춘 것, 오늘 다 만든 것.
///
/// 이 화면이 있는 이유는 하나다. **기다리는 사람이 "멈춘 건가" 를 묻지 않게.**
/// 그래서 기다리는 것도 보여주고, 멈춘 것은 이유와 다음 행동을 같이 준다.
/// 큐는 렌더 1개씩 돈다 (`AGENTS.md §2`).
struct MakingScreen: View {
    var state: MakingState

    var onStop: (MakingJob) -> Void = { _ in }
    var onCancel: (MakingJob) -> Void = { _ in }
    var onChoice: (MakingJob, ChatChoice) -> Void = { _, _ in }
    var onOpenResult: (DoneItem) -> Void = { _ in }

    var body: some View {
        content
            .navigationTitle(Copy.MakingScreen.title)
            .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .empty:
            ContentUnavailableView {
                Label(Copy.MakingScreen.Empty.title, systemImage: "clock")
            } description: {
                Text(Copy.MakingScreen.Empty.message)
            }
        case .loaded(let jobs, let doneToday):
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.page) {
                    section(running(jobs), header: nil)
                    section(queued(jobs), header: Copy.MakingScreen.waitingHeader)
                    section(stopped(jobs), header: Copy.MakingScreen.stoppedHeader)
                    doneSection(doneToday)
                }
                .padding(Tokens.Space.section)
                // 읽기 좋은 폭에서 멈추되 **왼쪽에 붙인다.** maxWidth 만 주면 창 가운데로 몰린다.
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func section(_ jobs: [MakingJob], header: String?) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.between) {
                if let header {
                    Text(header)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(jobs) { job in
                    MakingJobCard(
                        job: job,
                        onStop: { onStop(job) },
                        onCancel: { onCancel(job) },
                        onChoice: { onChoice(job, $0) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func doneSection(_ items: [DoneItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.inner) {
                Text(Copy.MakingScreen.doneTodayHeader)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    HStack(spacing: Tokens.Space.between) {
                        ThumbnailView(thumbnail: item.thumbnail, cornerRadius: 3)
                            .frame(width: 24, height: 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.shotTitle)
                                .font(.callout)
                                .lineLimit(1)
                            Text(item.platform.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Tokens.Space.between)
                        Text(item.when)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(Copy.MakingScreen.openResult) { onOpenResult(item) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        guard case .loaded(let jobs, _) = state else { return "" }
        return Copy.count(jobs.count)
    }

    private func running(_ jobs: [MakingJob]) -> [MakingJob] {
        jobs.filter { if case .running = $0.state { true } else { false } }
    }

    private func queued(_ jobs: [MakingJob]) -> [MakingJob] {
        jobs.filter { if case .queued = $0.state { true } else { false } }
    }

    private func stopped(_ jobs: [MakingJob]) -> [MakingJob] {
        jobs.filter { if case .stopped = $0.state { true } else { false } }
    }
}

/// 만들고 있는 것 하나. 상태에 따라 카드가 달라진다.
private struct MakingJobCard: View {
    var job: MakingJob
    var onStop: () -> Void
    var onCancel: () -> Void
    var onChoice: (ChatChoice) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.between) {
            ThumbnailView(thumbnail: job.thumbnail, cornerRadius: Tokens.Radius.thumbnail)
                .frame(width: 44, height: 78)

            VStack(alignment: .leading, spacing: Tokens.Space.inner) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.shotTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("\(job.platform.label) · \(job.planLabel) · \(Copy.duration(job.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch job.state {
                case .running(let progress):
                    running(progress)
                case .queued(let note):
                    HStack(spacing: Tokens.Space.between) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(Copy.MakingScreen.cancel, action: onCancel)
                            .controlSize(.small)
                    }
                case .stopped(let reason, let actions):
                    stopped(reason, actions)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.between)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
    }

    private func running(_ progress: MakingProgress) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.inner) {
                Text(Copy.Plan.Making.percent(progress.fraction))
                    .font(.title3.monospacedDigit().weight(.semibold))
                if let remaining = progress.remaining {
                    Text(Copy.Plan.Preparing.remaining(remaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(Copy.MakingScreen.stop, action: onStop)
                    .controlSize(.small)
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)

            HStack(spacing: Tokens.Space.section) {
                ForEach(progress.steps) { step in
                    HStack(spacing: Tokens.Space.tight + 1) {
                        StepIcon(state: step.state)
                        Text(step.title)
                            .foregroundStyle(step.state == .waiting ? .secondary : .primary)
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
            }

            Text(Copy.Plan.Making.keepsGoing)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 멈춘 것. **붉은색을 쓰지 않는다** — 사람이 손대면 이어서 만들 수 있으니 실패가 아니다.
    /// 대신 이유를 사람 말로 적고 다음 행동을 버튼으로 준다 (`AGENTS.md §1-6`).
    private func stopped(_ reason: String, _ actions: [ChatChoice]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.inner) {
            HStack(alignment: .top, spacing: Tokens.Space.inner) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(Tokens.Palette.attention)
                Text(reason)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Tokens.Space.inner) {
                ForEach(actions) { action in
                    if action.isPrimary {
                        Button(action.title) { onChoice(action) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button(action.title) { onChoice(action) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

#Preview("만드는 중") {
    MakingScreen(state: .loaded(jobs: SampleData.makingJobs, doneToday: SampleData.doneToday))
        .frame(width: 900, height: 700)
}

#Preview("만드는 중 · 빈 상태") {
    MakingScreen(state: .empty)
        .frame(width: 900, height: 700)
}
