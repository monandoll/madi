import AVKit
import Photos
import SwiftUI

// 사진 보관함에서 바로 트는 미리보기 — **개발이 넣은 파일** (2026-10-01, viewdata-map ㉚).
// 앱 사본이 아직 없는 촬영본(사진 앱을 연결했을 때 보관함에 이미 있던 영상)은 정보 칸에 그림만 나오고 재생 버튼이 없었다.
// 원본을 앱으로 받지 않고 사진 보관함의 재생 항목으로 튼다. 디자인은 다시 그려도 된다 — 지킬 것: 누르기 전에는 아무것도 받지 않는다.
// MadiKit 에 의존하지 않는다 (스크린샷 도구 `MadiUIShots` 가 Madi/UI 만 컴파일한다).

/// 사진 보관함 영상 하나의 재생기를 준비한다. 누를 때 요청한다 — 고르기만 해도 iCloud 에서 받기 시작하면 안 된다.
@MainActor
final class PhotoPreview: ObservableObject {
    enum State {
        case idle
        case loading
        case ready(AVPlayer)
        /// 사진 앱 연결이 풀렸거나 사진 앱에서 지운 영상.
        case failed
    }

    @Published private(set) var state: State = .idle
    private var request: PHImageRequestID?

    var isLoading: Bool { if case .loading = state { true } else { false } }
    var isFailed: Bool { if case .failed = state { true } else { false } }

    func load(assetID: String, then ready: @escaping @MainActor (AVPlayer) -> Void) {
        switch state {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        // 권한이 없으면 묻지 않고 그만둔다 — 미리보기를 눌렀다고 권한 창이 뜨면 안 된다 (연결은 갤러리 · 설정에서 한다)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            state = .failed
            return
        }
        state = .loading
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true      // 원본이 iCloud 에만 있으면 받아 가며 튼다
        options.deliveryMode = .automatic
        request = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            nonisolated(unsafe) let item = item    // 받은 그대로 메인으로 넘기기만 한다
            Task { @MainActor in
                guard let self, case .loading = self.state else { return }
                guard let item else { self.state = .failed; return }
                let player = AVPlayer(playerItem: item)
                self.state = .ready(player)
                ready(player)
            }
        }
    }

    /// 화면을 떠난다 — 요청을 거두고 재생을 멈춘다.
    func stop() {
        if let request { PHImageManager.default().cancelImageRequest(request) }
        request = nil
        if case .ready(let player) = state { player.pause() }
        if case .loading = state { state = .idle }
    }
}

/// 누르면 사진 보관함에서 불러와 그 자리에서 재생한다. 누르기 전에는 그림 + ▶.
struct InlinePhotoVideo: View {
    let assetID: String
    /// 이 촬영본을 틀라는 알림(`.madiShotPlay`)을 알아볼 id.
    var id: String
    var poster: Thumbnail
    @StateObject private var preview = PhotoPreview()
    @StateObject private var clock = PlayerClock()

    var body: some View {
        VStack(spacing: Tokens.Space.inner) {
            if case .ready(let player) = preview.state {
                MediaPlayerView(player: player)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                    .aspectRatio(clock.aspect ?? Tokens.Ratio.vertical, contentMode: .fit)
                    .overlay {
                        if !clock.isPlaying { playMark }
                    }
                    .contentShape(.rect)
                    .onTapGesture { clock.toggle() }
                PlayerTransport(clock: clock)
            } else {
                // 진짜 버튼이다 — 탭 제스처만 두면 접근성(VoiceOver · 자동 누르기)으로는 안 눌린다
                Button(action: start) {
                    ThumbnailView(thumbnail: poster, cornerRadius: Tokens.Radius.card)
                        .aspectRatio(Tokens.Ratio.vertical, contentMode: .fit)
                        .overlay {
                            if preview.isLoading {
                                ProgressView().controlSize(.regular)
                            } else {
                                playMark
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Copy.Player.play)
                .accessibilityLabel(Copy.Player.play)
                if preview.isLoading {
                    Text(Copy.Player.loadingFromPhotos)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if preview.isFailed {
                    Text(Copy.Player.cantPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            clock.detach()
            preview.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .madiShotPlay)) { note in
            guard note.userInfo?["id"] as? String == id else { return }
            if case .ready = preview.state { clock.toggle() } else { start() }
        }
    }

    private var playMark: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(.white, .black.opacity(0.35))
    }

    private func start() {
        preview.load(assetID: assetID) { player in
            clock.attach(player)
            player.play()
        }
    }
}
