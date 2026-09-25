import SwiftUI

/// 첫 실행. **묻는 것은 셋뿐이다 — 사진 · AI · 이름.**
///
/// 크리에이터에게 설치 이상의 것을 요구하지 않는다 (`AGENTS.md §1-9`).
/// 터미널을 열게 하지 않고, CLI 설치와 로그인 진입은 앱이 대신한다. 사람이 하는 일은
/// 브라우저에서 로그인 버튼을 누르는 것뿐이다.
///
/// 창은 720×540 고정이다. 늘였다 줄였다 할 게 없다.
struct OnboardingWindow: View {
    var state: OnboardingState

    var onAllowPhotos: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}
    var onPick: (AIConnection) -> Void = { _ in }
    var onLogin: () -> Void = {}
    var onCancelLogin: () -> Void = {}
    var onOtherAccount: () -> Void = {}
    var onStudioName: (String) -> Void = { _ in }
    var onNext: () -> Void = {}
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onStart: () -> Void = {}

    @State private var draftName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if state.step == .ready {
                ReadyStep(onStart: onStart)
            } else {
                header
                Divider().opacity(0)
                body(for: state.step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Tokens.Space.page + 8)
                footer
            }
        }
        .frame(
            width: Tokens.Size.onboarding.width,
            height: Tokens.Size.onboarding.height
        )
        .tint(Tokens.Palette.accent)
        .onAppear { draftName = state.studioName }
    }

    // MARK: - 머리 · 발

    private var header: some View {
        HStack {
            Text(Copy.Onboarding.appName)
                .font(.callout.weight(.semibold))
            Spacer()
            if let label = state.step.stepLabel {
                StepDots(step: state.step)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Tokens.Space.page + 8)
        .padding(.top, Tokens.Space.page)
        .padding(.bottom, Tokens.Space.section)
    }

    private var footer: some View {
        HStack {
            if state.step == .photos {
                Button(Copy.Onboarding.skip, action: onSkip)
                    .buttonStyle(.link)
            } else {
                Button(Copy.Onboarding.back, action: onBack)
            }
            if state.step == .studio {
                Text(Copy.Onboarding.Studio.skipHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(nextTitle, action: onNext)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
        .padding(Tokens.Space.page)
    }

    private var nextTitle: String {
        state.step == .studio ? Copy.Onboarding.Studio.start : Copy.Onboarding.next
    }

    /// 넘어갈 수 있는 조건. **사진은 막지 않는다** — 허용 안 해도 쓸 수 있다.
    /// AI 는 막는다. AI 가 없으면 편집안을 만들 수 없고, 그게 이 앱의 전부다 (`§10`).
    private var canContinue: Bool {
        switch state.step {
        case .photos: true
        case .ai: if case .connected = state.ai { true } else { false }
        case .studio, .ready: true
        }
    }

    // MARK: - 단계

    @ViewBuilder
    private func body(for step: OnboardingStep) -> some View {
        switch step {
        case .photos:
            PhotosStep(
                access: state.photos,
                onAllow: onAllowPhotos,
                onOpenSystemSettings: onOpenSystemSettings
            )
        case .ai:
            AIStep(
                setup: state.ai,
                onPick: onPick,
                onLogin: onLogin,
                onCancel: onCancelLogin,
                onOtherAccount: onOtherAccount
            )
        case .studio:
            StudioStep(name: $draftName, onChange: onStudioName)
        case .ready:
            EmptyView()
        }
    }
}

/// 몇 단계인지 점으로도 보여준다. 숫자만 있으면 얼마나 남았는지 감이 안 온다.
private struct StepDots: View {
    var step: OnboardingStep

    var body: some View {
        HStack(spacing: Tokens.Space.tight + 1) {
            ForEach(Array(OnboardingStep.allCases.dropLast().enumerated()), id: \.offset) { pair in
                Capsule()
                    .fill(pair.element == step ? Tokens.Palette.accent : Color.secondary.opacity(0.3))
                    .frame(width: pair.element == step ? 16 : 10, height: 4)
            }
        }
    }
}

// MARK: - 1 / 3 사진

private struct PhotosStep: View {
    var access: PhotoAccess
    var onAllow: () -> Void
    var onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.section) {
            Text(Copy.Onboarding.Photos.title)
                .font(.title2.weight(.semibold))
            Text(Copy.Onboarding.Photos.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 무엇을 읽고 무엇을 안 건드리는지 먼저 말한다. 권한 창이 뜨기 전에.
            VStack(spacing: 0) {
                point("video", Copy.Onboarding.Photos.pointVideoOnly,
                      Copy.Onboarding.Photos.pointVideoOnlyDetail)
                Divider().padding(.leading, 40)
                point("lock.shield", Copy.Onboarding.Photos.pointOriginal,
                      Copy.Onboarding.Photos.pointOriginalDetail)
                Divider().padding(.leading, 40)
                point("switch.2", Copy.Onboarding.Photos.pointAnytime,
                      Copy.Onboarding.Photos.pointAnytimeDetail)
            }
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))

            switch access {
            case .notAsked:
                Button(Copy.Onboarding.Photos.allow, action: onAllow)
                    .buttonStyle(.borderedProminent)
            case .granted:
                Label(Copy.Settings.Shots.photoAccessOn, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Tokens.Palette.ok)
                    .font(.callout)
            case .denied:
                // 막히지 않는다. 다른 길을 바로 알려준다.
                VStack(alignment: .leading, spacing: Tokens.Space.inner) {
                    Text(Copy.Onboarding.Photos.deniedTitle)
                        .font(.callout.weight(.medium))
                    Text(Copy.Onboarding.Photos.deniedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(Copy.Onboarding.Photos.openSystemSettings, action: onOpenSystemSettings)
                        .controlSize(.small)
                }
                .padding(Tokens.Space.between)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.card))
            }
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.between) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.between)
    }
}

// MARK: - 2 / 3 AI

private struct AIStep: View {
    var setup: AISetup
    var onPick: (AIConnection) -> Void
    var onLogin: () -> Void
    var onCancel: () -> Void
    var onOtherAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.section) {
            Text(Copy.Onboarding.AI.title)
                .font(.title2.weight(.semibold))
            Text(Copy.Onboarding.AI.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Space.between) {
                card(.claude, Copy.Onboarding.AI.claude, Copy.Onboarding.AI.claudeDetail)
                card(.codex, Copy.Onboarding.AI.codex, Copy.Onboarding.AI.codexDetail)
            }

            switch setup {
            case .notPicked:
                EmptyView()
            case .picked(let ai):
                HStack(spacing: Tokens.Space.between) {
                    Button(Copy.Onboarding.AI.login(name(ai)), action: onLogin)
                        .buttonStyle(.borderedProminent)
                    Text(Copy.Onboarding.AI.loginHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .waiting:
                HStack(spacing: Tokens.Space.between) {
                    ProgressView().controlSize(.small)
                    Text(Copy.Onboarding.AI.waiting)
                        .font(.callout)
                    Button(Copy.Onboarding.AI.waitingCancel, action: onCancel)
                        .buttonStyle(.link)
                }
            case .connected(let ai, let account):
                HStack(spacing: Tokens.Space.inner) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Tokens.Palette.ok)
                    Text(Copy.Onboarding.AI.connected(name(ai)))
                        .font(.callout.weight(.medium))
                    Text("· \(account)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(Copy.Onboarding.AI.otherAccount, action: onOtherAccount)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                if setup.picked == nil {
                    Text(Copy.Onboarding.AI.needed)
                }
                // 막되 가두지 않는다. 창을 닫고 나중에 이어서 할 수 있다는 걸 여기서 말한다.
                Text(Copy.Onboarding.AI.closeHint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func name(_ ai: AIConnection) -> String {
        ai == .codex ? Copy.Onboarding.AI.codex : Copy.Onboarding.AI.claude
    }

    private func card(_ ai: AIConnection, _ title: String, _ detail: String) -> some View {
        let isPicked = setup.picked == ai
        return Button {
            onPick(ai)
        } label: {
            HStack(spacing: Tokens.Space.inner) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isPicked ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isPicked ? Tokens.Palette.accent : .secondary)
            }
            .padding(Tokens.Space.between)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isPicked
                ? AnyShapeStyle(Tokens.Palette.accent.opacity(0.10))
                : AnyShapeStyle(.quaternary.opacity(0.4)),
            in: .rect(cornerRadius: Tokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .strokeBorder(isPicked ? Tokens.Palette.accent : .clear, lineWidth: 1.5)
        }
    }
}

// MARK: - 3 / 3 스튜디오 이름

private struct StudioStep: View {
    @Binding var name: String
    var onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.section) {
            Text(Copy.Onboarding.Studio.title)
                .font(.title2.weight(.semibold))
            Text(Copy.Onboarding.Studio.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(Copy.Onboarding.Studio.placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onChange(of: name) { _, new in onChange(new) }

            // 이름이 어디에 쓰이는지 바로 보여준다. 설명보다 빠르다.
            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                Text(Copy.Onboarding.Studio.previewLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(displayName) · 골반이 틀어져있다면, 이 동작 안되실걸요?")
                    .font(.callout)
                    .lineLimit(1)
                    .padding(Tokens.Space.inner)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.thumbnail))
            }
        }
    }

    private var displayName: String {
        name.isEmpty ? Copy.Onboarding.Studio.defaultName : name
    }
}

// MARK: - 준비됐어요

private struct ReadyStep: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.section) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Tokens.Palette.ok)
            Text(Copy.Onboarding.Ready.title)
                .font(.title.weight(.semibold))
            Text(Copy.Onboarding.Ready.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button(Copy.Onboarding.Ready.start, action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, Tokens.Space.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Tokens.Space.page)
    }
}

// MARK: - 프리뷰

#Preview("1/3 사진") {
    OnboardingWindow(state: OnboardingState(step: .photos))
}

#Preview("1/3 사진 · 허용 안 함") {
    OnboardingWindow(state: OnboardingState(step: .photos, photos: .denied))
}

#Preview("2/3 AI") {
    OnboardingWindow(state: OnboardingState(step: .ai, photos: .granted, ai: .picked(.claude)))
}

#Preview("2/3 AI · 기다리는 중") {
    OnboardingWindow(state: OnboardingState(step: .ai, photos: .granted, ai: .waiting(.claude)))
}

#Preview("3/3 이름") {
    OnboardingWindow(state: SampleData.onboardingStudio)
}

#Preview("준비됐어요") {
    OnboardingWindow(state: OnboardingState(step: .ready))
}
