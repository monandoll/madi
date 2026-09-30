import AVFoundation
import Combine

// 앱 안 재생 — **개발이 넣은 파일** (viewdata-map ⑩). `MediaPlayerView.swift` 에서 떼어 냈다 — 화면 없이 테스트하려고
// (MadiBridgeTests 가 이 파일만 컴파일한다). MadiKit 에 의존하지 않는다.

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

    /// **보이는 것만** 처음부터 같이 튼다 (결과물 "둘 다 처음부터 재생" · "처음부터 재생").
    /// 소리는 `soundFrom` 하나만 — 두 영상 말소리가 겹치면 어느 쪽도 못 알아듣는다. 나머지는 소리를 끈다 (각자 켤 수 있다).
    ///
    /// 전에는 이 화면에서 한 번이라도 만든 재생기를 **전부** 틀었다 — "하나만" 으로 바꿔 숨긴 이전 판, 전에 골랐던
    /// 다른 결과물까지 안 보이는 채로 소리가 났다 (2026-09-30).
    func playFromStart(_ urls: [URL], soundFrom: URL?) {
        let visible = Set(urls)
        for (url, p) in players where !visible.contains(url) { p.pause() }
        for url in urls {
            let p = player(for: url)
            p.isMuted = url != soundFrom
            p.seek(to: .zero)
            p.play()
        }
    }
}
