import SwiftUI
import MadiKit

/// 0단계의 프리뷰 창 하나. **본 UI 가 아니다** (docs/stage-0.spec.md 범위 밖).
///
/// 여기 있는 이유는 딱 하나 — `CaptionLayer` 가 화면에서도 같은 그림을 내는지 눈으로 보기 위해서다.
/// 갤러리 · 편집안 · 장면 카드 · 채팅은 6단계다. 여기에 기능을 붙이지 않는다.
@main
struct MadiApp: App {
    // `Scene` 은 SwiftUI 와 `Madi/Model` 양쪽에 있다. 모델 쪽 이름은 AGENTS.md §5 가 정한 것이라
    // 바꾸지 않고, UI 코드에서 SwiftUI 쪽을 명시한다.
    var body: some SwiftUI.Scene {
        Window("마디 — 자막 확인", id: "spike") {
            CaptionPreview()
        }
        .windowResizability(.contentSize)
    }
}

private struct CaptionPreview: View {
    @State private var text = "가능성이 높다는 겁니다"
    @State private var secondary = "is likely misaligned."

    /// 원본 프레임 위에 겹쳐 봐야 어긋난 게 보인다 (docs/style-authoring.md §3).
    private var backdrop: URL? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // Madi
            .deletingLastPathComponent()  // repo
        let url = repoRoot.appending(path: "reference/yt_15s.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if let image {
                Image(image, scale: 1, label: Text("자막 미리보기"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 720)
            } else {
                Text("자막을 그리지 못했어요")
                    .frame(height: 720)
            }
            TextField("자막", text: $text)
            TextField("보조 문구", text: $secondary)
        }
        .padding(16)
        .frame(width: 460)
    }

    private var image: CGImage? {
        guard let style = try? StyleStore.load() else { return nil }
        let caption = Caption(id: "preview", start: 0, end: 2, text: text, secondary: secondary)
        return try? StillRenderer.renderCaption(
            caption,
            size: CGSize(width: 1080, height: 1920),
            style: style.values,
            backdrop: backdrop.map { .image($0) } ?? .solid(RGBA(0.13, 0.13, 0.15, 1))
        )
    }
}
