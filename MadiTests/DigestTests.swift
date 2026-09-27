import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 다이제스트 (§6) 부품과 분석 작업.
struct DigestTests {

    @Test("무음은 기준 아래가 0.5초 이상 이어진 곳이다")
    func silences() {
        // 창 0.05초. 0.3초 무음(무시) · 0.6초 무음 · 끝까지 이어진 무음.
        let loud = [Double](repeating: -20, count: 10)
        let rms = loud + [Double](repeating: -60, count: 6) + loud + [Double](repeating: -60, count: 12)
            + loud + [Double](repeating: -60, count: 10)
        let s = AudioAnalyzer.silences(in: rms)
        #expect(s.count == 2)
        #expect(abs(s[0].lowerBound - 1.3) < 1e-9 && abs(s[0].upperBound - 1.9) < 1e-9)
        #expect(abs(s[1].upperBound - 2.9) < 1e-9)   // 끝에서 닫힌다
    }

    @Test("컷은 기준을 넘는 차분의 가장 큰 곳 하나다")
    func cutsFromDiffs() {
        #expect(SceneCutDetector.cuts(in: [0.01, 0.02, 0.4, 0.01], stepSec: 0.2) == [0.6000000000000001])
        // 페이드처럼 여러 표본에 걸친 변화 → 하나
        #expect(SceneCutDetector.cuts(in: [0.01, 0.15, 0.3, 0.15, 0.01], stepSec: 0.2).count == 1)
        #expect(SceneCutDetector.cuts(in: [0.01, 0.05, 0.02], stepSec: 0.2).isEmpty)
    }

    @Test("합성 영상에서 밝기가 바뀌는 곳을 컷으로 찾는다")
    func detectsCutInVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "madi-cut-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await TestVideo.makeTwoTone(at: url, seconds: 2, switchAt: 1)
        let r = try await SceneCutDetector.detect(url)
        #expect(r.cuts.count == 1)
        #expect(abs((r.cuts.first ?? 0) - 1.0) <= 0.2, "컷 \(r.cuts) · 차분 \(r.diffs)")
    }

    @Test("문장은 끝 문장부호나 0.5초 넘는 쉼에서 끊는다")
    func sentences() {
        let words = [
            Word(text: "오늘은", start: 0, end: 0.4), Word(text: "스트레칭.", start: 0.4, end: 0.9),
            Word(text: "먼저", start: 1.0, end: 1.3), Word(text: "앉아요", start: 2.0, end: 2.4),
        ]
        let s = DigestBuilder.sentences(words)
        #expect(s.map(\.text) == ["오늘은 스트레칭.", "먼저", "앉아요"])
    }

    /// 모델 없이 도는 가짜 전사기.
    struct FakeTranscriber: TranscriptionProvider {
        func transcribe(_ url: URL, languageCode: String) async throws -> Transcript {
            Transcript(videoID: "v", words: [Word(text: "안녕하세요.", start: 0.1, end: 0.6)])
        }
    }

    @Test("분석 작업은 다이제스트를 저장하고, 원본이 그대로면 다시 만들지 않는다")
    func analyzeJobCaches() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-analyze-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "v.mp4")
        try await TestVideo.makeTwoTone(at: source, seconds: 2, switchAt: 1)

        let db = try AppDatabase.inMemory()
        let video = VideoRecord(id: "v1", source: .folder, sourceRef: source.path, localPath: source.path, status: .ready)
        try await db.writer.write { try video.insert($0) }
        let job = AnalyzeJob(db: db, transcriber: FakeTranscriber(), root: dir.appending(path: "analysis"))

        #expect(try await job.run(videoId: "v1") == true)
        let d = try #require(try await db.writer.read { try DigestRecord.fetchOne($0, key: "v1") })
        #expect(d.text.contains("## TRANSCRIPT") && d.text.contains("안녕하세요."))
        #expect(d.text.contains("(오디오 트랙 없음)"))
        #expect(d.text.contains("cut 001.0"))
        #expect(!d.sheetPaths.isEmpty && d.sheetPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) })

        #expect(try await job.run(videoId: "v1") == false)   // 캐시
    }

    @Test("원본 사본이 없으면 분석하지 않는다")
    func analyzeNeedsLocalCopy() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try VideoRecord(id: "v1", source: .photos, sourceRef: "ph:1").insert($0) }
        let job = AnalyzeJob(db: db, transcriber: FakeTranscriber())
        await #expect(throws: AnalyzeJob.Failure.self) { try await job.run(videoId: "v1") }
    }
}
