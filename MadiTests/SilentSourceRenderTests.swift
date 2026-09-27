import Testing
import Foundation
import AVFoundation
import CoreGraphics
@testable import MadiKit

/// **오디오가 없는 원본도 렌더된다.**
///
/// 한동안 안 됐다. `compose` 가 오디오 트랙을 미리 만들어 두고 넣을 오디오가 없으면
/// **빈 트랙**이 남았는데, `AVAssetExportSession` 이 그걸 보면 "Operation Stopped" 로
/// 실패한다. 무음 스톡 영상은 통째로 렌더 불가였다
/// (`docs/findings/2026-09-26-vertical-substitutes.md §4`).
///
/// 크리에이터 촬영본에는 항상 소리가 있지만, 대용 원본·해부학 그림 장면(`§5 Source.image`)은
/// 무음이다. 여기서 막아 둔다.
struct SilentSourceRenderTests {

    @Test("오디오 트랙이 없는 원본도 내보내진다")
    func rendersSourceWithoutAudio() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "madi-silent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "silent.mp4")
        try await TestVideo.makeSolid(at: source)
        // 먼저 전제를 확인한다 — 정말 오디오가 없어야 이 테스트가 의미 있다.
        let audio = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio)
        #expect(audio.isEmpty)

        let comp = Composition(
            id: "silent", videoID: "silent", templateID: "short",style: StyleRef(id: "short.v1", version: 1),
            size: Composition.Size(w: 128, h: 224), fps: 30,
            meta: Composition.Meta(title: "무음", targetDurationSec: 0.4),
            captionSlot: .fullBody,
            scenes: [Scene(
                id: "s1", role: .demo,
                source: Scene.Source(videoID: "silent", start: 0, end: 0.4)
            )]
        )
        let out = dir.appending(path: "out.mp4")
        let values = try StyleStore.load(StyleStore.defaultID).values
        try await Renderer().render(comp, sources: ["silent": source], style: values, to: out)

        #expect(FileManager.default.fileExists(atPath: out.path))
        let made = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
        #expect(made.count == 1)
    }
}
