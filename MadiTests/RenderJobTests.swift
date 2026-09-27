import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 렌더 작업 — 가져오기 · 분석 뒤 편집안 하나를 내보내고 리포트를 붙인다. 모델 · 네트워크 없이.
struct RenderJobTests {

    @Test("분석 → 편집안 → 렌더: 키프레임을 되쓰고, 결과물과 게이트 리포트가 남는다")
    func rendersCompositionEndToEnd() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "v.mp4")
        try await TestVideo.makeTwoTone(at: source, seconds: 2, switchAt: 1, size: CGSize(width: 360, height: 640))

        let db = try AppDatabase.inMemory()
        try await db.writer.write { try VideoRecord(id: "v1", source: .folder, sourceRef: source.path, localPath: source.path, status: .ready).insert($0) }
        try await AnalyzeJob(db: db, transcriber: DigestTests.FakeTranscriber(), root: dir.appending(path: "a")).run(videoId: "v1")

        let comp = Composition(
            id: "c1", videoID: "v1", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 1.8), captionSlot: .upperBody,
            scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v1", start: 0, end: 1.8),
                           captions: [Caption(id: "c", start: 0.1, end: 0.6, text: "안녕하세요.")])]
        )
        try db.saveComposition(comp)
        let job = RenderJob(db: db, outputs: dir.appending(path: "out"))
        let output = try await job.run(compositionId: "c1")

        #expect(FileManager.default.fileExists(atPath: output.path))
        let report = try #require(output.reviewReport)
        for key in ["G1", "G2", "G3", "G4.upperBody", "G5", "G6"] { #expect(report.contains("\"\(key)\""), "\(key) 없음") }
        // 합성 영상에는 사람이 없다 — G1 은 통과가 아니라 판정 불가여야 한다 (§8).
        #expect(report.contains("cannotJudge"))
        // auto 장면의 키프레임이 편집안에 되써졌다 (§7-1).
        let saved = try #require(try await db.writer.read { try CompositionRecord.fetchOne($0, key: "c1") }).composition()
        #expect(saved.scenes[0].reframe.mode != .auto)
        // 같은 편집안은 다시 그리지 않는다.
        #expect(try await job.run(compositionId: "c1").id == output.id)
    }
}
