import Testing
import Foundation
import AVFoundation
@testable import MadiKit

/// **여러 장면을 붙인 결과물의 소리는 이어진 한 트랙이다.**
///
/// 한동안 아니었다. 원본이 AAC 면 내보내기가 소리를 다시 인코딩하지 않고 장면마다 조각째 붙여, 오디오 트랙이 장면 수만큼의
/// 편집 목록이 됐다. CoreAudio 파일 읽기(`AVAudioFile`)는 **첫 장면 소리만** 읽었다 — 19.1초 결과물이 1.90초
/// (2026-09-30, `Renderer.continuousAudio`). 올리는 곳이 어떻게 읽을지 모르는 파일을 내보내지 않는다.
struct AudioContinuityTests {

    @Test("떨어진 구간 세 장면 — 오디오 트랙 하나 · 편집 조각 하나 · AVAudioFile 로 끝까지 읽힌다")
    func continuousAudioAcrossScenes() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "tone.mp4")
        try await TestVideo.makeWithTone(at: source, seconds: 3)
        #expect(try await !AVURLAsset(url: source).loadTracks(withMediaType: .audio).isEmpty)   // 전제 — 소리가 있다

        let comp = Composition(
            id: "tone", videoID: "tone", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            size: Composition.Size(w: 128, h: 224), fps: 30,
            meta: Composition.Meta(title: "소리", targetDurationSec: 1.5),
            captionSlot: .fullBody,
            scenes: [(0.0, 0.5), (1.0, 1.5), (2.0, 2.5)].enumerated().map { i, r in
                Scene(id: "s\(i)", role: i == 0 ? .hook : .demo, source: Scene.Source(videoID: "tone", start: r.0, end: r.1))
            }
        )
        let out = dir.appending(path: "out.mp4")
        try await Renderer().render(comp, sources: ["tone": source], style: try StyleStore.load(StyleStore.defaultID).values, to: out)

        let audio = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        let segments = try #require(try await audio.first?.load(.segments))
        #expect(segments.filter { !$0.isEmpty }.count == 1, "편집 조각 \(segments.count)개")
        let file = try AVAudioFile(forReading: out)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(seconds - comp.duration) < 0.15, "AVAudioFile 이 읽은 길이 \(seconds)초")
    }
}
