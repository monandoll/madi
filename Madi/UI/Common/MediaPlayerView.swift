import AVKit
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

    /// 전부 처음부터 같이 튼다 (결과물 "둘 다 처음부터 재생").
    func playAllFromStart() {
        for p in players.values {
            p.seek(to: .zero)
            p.play()
        }
    }
}

/// `AVPlayerView` (재생 막대 포함). 세로 · 가로 어느 영상이든 맞춰 보인다.
struct MediaPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .inline
        v.videoGravity = .resizeAspect
        v.showsFullScreenToggleButton = true
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

extension Notification.Name {
    /// 편집안 플레이어를 이 위치(초)로 옮겨 재생한다 — "처음부터 보기" · 장면 "여기서 재생".
    /// userInfo `seconds: Double`. 바꾸는 층(개발)이 보낸다.
    static let madiPlayerSeek = Notification.Name("madi.player.seek")
}

/// 편집안 자리의 영상 — 위치 옮기기 알림을 받는다.
struct PlanVideo: View {
    let url: URL
    @StateObject private var players = MediaPlayers()

    var body: some View {
        MediaPlayerView(player: players.player(for: url))
            .onReceive(NotificationCenter.default.publisher(for: .madiPlayerSeek)) { note in
                let seconds = note.userInfo?["seconds"] as? Double ?? 0
                let p = players.player(for: url)
                p.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                p.play()
            }
    }
}
