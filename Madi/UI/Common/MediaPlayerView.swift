import AVKit
import Combine
import SwiftUI

// 앱 안 재생 — **개발이 넣은 파일** (2026-09-28, 사용자 결정 "개발이 최소로 직접 고침", viewdata-map ⑩).
// 디자인은 이 파일을 다시 그려도 된다. 지키는 것: 내보낸 mp4 를 재생한다 — 자막이 이미 그려져 있다 (§7 내보낸 파일).
// MadiKit 에 의존하지 않는다 (스크린샷 도구 `MadiUIShots` 가 Madi/UI 만 컴파일한다).

/// 재생기 하나. 주소가 같으면 같은 `AVPlayer` 를 쓴다 — 화면이 다시 그려져도 재생이 끊기지 않게.
@MainActor
final class MediaPlayers: ObservableObject {
    private var players: [URL: AVPlayer] = [:]

    func player(for url: URL) -> AVPlayer {
        if let p = players[url] { return p }
        let p = AVPlayer(url: url)
        players[url] = p
        return p
    }

    /// 전부 멈춘다 — 다른 결과물로 옮기거나 화면을 떠날 때. 안 멈추면 안 보이는 영상 소리가 계속 난다.
    func pauseAll() {
        for p in players.values { p.pause() }
    }

    /// 전부 처음부터 같이 튼다 (결과물 "둘 다 처음부터 재생").
    func playAllFromStart() {
        for p in players.values {
            p.seek(to: .zero)
            p.play()
        }
    }
}

/// 영상 그림만. 재생 막대는 그리지 않는다 — 막대는 화면마다 디자인 문법으로 따로 둔다
/// (`AVPlayerView` 의 막대는 좁은 칸에서 버튼이 겹치고, 가장자리에 조각이 비어져 나온다).
struct MediaPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.allowsPictureInPicturePlayback = false
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

/// 재생기 상태를 화면에 내보낸다 — 위치 · 길이 · 재생 중인가.
@MainActor
final class PlayerClock: ObservableObject {
    @Published var position: Double = 0
    @Published var total: Double = 0
    @Published var isPlaying = false

    private weak var player: AVPlayer?
    private var observer: Any?
    private var bag: Set<AnyCancellable> = []

    @Published var isMuted = false

    func attach(_ player: AVPlayer) {
        guard self.player !== player else { return }
        detach()
        self.player = player
        isMuted = player.isMuted
        position = 0
        total = 0
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if let d = player?.currentItem?.duration.seconds, d.isFinite { self.total = d }
            }
        }
        // 길이는 재생 전에도 보여 준다 (0:00 / 0:00 으로 두지 않는다).
        if let asset = player.currentItem?.asset {
            Task { [weak self] in
                guard let d = try? await asset.load(.duration).seconds, d.isFinite else { return }
                self?.total = d
            }
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
            .store(in: &bag)
    }

    /// 재생기를 놓는다 — 멈추고 관찰을 뗀다. 화면이 사라질 때도 부른다.
    func detach() {
        guard let player else { return }
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        bag.removeAll()
        self.player = nil
    }

    func skip(_ delta: Double) {
        let upper = total > 0 ? total : position + delta
        seek(min(max(0, position + delta), upper))
    }

    func toggleMute() {
        guard let player else { return }
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        position = seconds
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // 끝까지 본 뒤 다시 누르면 처음부터.
            if total > 0, position >= total - 0.05 { seek(0) }
            player.play()
        }
    }
}

/// 재생 막대 — QuickTime 문법. **타임라인이 아니다.** 트랙도 눈금자도 없다 (PlanPlayer 의 자리표시 막대와 같은 꼴).
struct PlayerTransport: View {
    @ObservedObject var clock: PlayerClock

    var body: some View {
        VStack(spacing: Tokens.Space.tight) {
            // 위치 막대. 끌어서 옮기는 것 말고는 아무 뜻이 없다.
            Slider(
                value: Binding(get: { min(clock.position, max(clock.total, 0.001)) },
                               set: { clock.seek($0) }),
                in: 0...max(clock.total, 0.001)
            )
            .controlSize(.mini)
            .labelsHidden()

            HStack(spacing: Tokens.Space.inner) {
                Text(Copy.duration(clock.position))
                Spacer(minLength: 0)
                Text(Copy.duration(clock.total))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            // 처음으로 · 10초 뒤로 · 재생/멈춤 · 10초 앞으로 · 소리. QuickTime 과 같은 버튼만 둔다.
            HStack(spacing: Tokens.Space.inner) {
                Button { clock.seek(0) } label: { Image(systemName: "backward.end.fill") }
                    .help(Copy.Plan.Scenes.playFromHere)
                Button { clock.skip(-10) } label: { Image(systemName: "gobackward.10") }
                Button { clock.toggle() } label: {
                    Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                        .imageScale(.large)
                        .frame(width: 18)
                }
                .help(Copy.Action.play)
                Button { clock.skip(10) } label: { Image(systemName: "goforward.10") }
                Button { clock.toggleMute() } label: {
                    Image(systemName: clock.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 16)
                }
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
        }
    }
}

extension Notification.Name {
    /// 편집안 플레이어를 이 위치(초)로 옮겨 재생한다 — "처음부터 보기" · 장면 "여기서 재생".
    /// userInfo `seconds: Double`. 바꾸는 층(개발)이 보낸다.
    static let madiPlayerSeek = Notification.Name("madi.player.seek")
}

/// 편집안 자리의 영상 + 재생 막대 — 위치 옮기기 알림을 받는다.
struct PlanVideo: View {
    let url: URL
    @StateObject private var players = MediaPlayers()
    @StateObject private var clock = PlayerClock()

    var body: some View {
        let player = players.player(for: url)
        VStack(spacing: Tokens.Space.inner) {
            MediaPlayerView(player: player)
                .background(.black)
                .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture { clock.toggle() }

            PlayerTransport(clock: clock)
        }
        .onAppear { clock.attach(player) }
        .onDisappear { clock.detach() }
        .onReceive(NotificationCenter.default.publisher(for: .madiPlayerSeek)) { note in
            clock.seek(note.userInfo?["seconds"] as? Double ?? 0)
            player.play()
        }
    }
}

/// 결과물 칸의 영상 + 재생 막대. 누르면 재생 · 멈춤.
struct ResultVideo: View {
    let player: AVPlayer
    /// 그림 높이. 막대는 그림 폭에 맞춘다.
    var height: CGFloat
    @StateObject private var clock = PlayerClock()

    var body: some View {
        VStack(spacing: Tokens.Space.inner) {
            MediaPlayerView(player: player)
                .background(.black)
                .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                .contentShape(.rect)
                .onTapGesture { clock.toggle() }
                .frame(width: height * Tokens.Ratio.vertical, height: height)
            PlayerTransport(clock: clock)
                .frame(width: height * Tokens.Ratio.vertical)
        }
        .onAppear { clock.attach(player) }
        .onChange(of: ObjectIdentifier(player)) { clock.attach(player) }
        .onDisappear { clock.detach() }
    }
}
