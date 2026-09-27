import Foundation
import GRDB

/// 큐의 **분석** 작업 — 영상 한 편의 다이제스트를 만들어 저장한다 (AGENTS.md §6).
///
/// 원본이 그대로면(지문 · 형식 버전이 같으면) 다시 만들지 않는다.
public struct AnalyzeJob: Sendable {
    public let db: AppDatabase
    public let transcriber: any TranscriptionProvider
    /// 다이제스트 시트를 남기는 곳. 기본 `~/Library/Application Support/madi/analysis/`.
    public let root: URL

    public init(db: AppDatabase, transcriber: any TranscriptionProvider, root: URL = AnalyzeJob.defaultRoot) {
        self.db = db; self.transcriber = transcriber; self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/analysis", directoryHint: .isDirectory)
    }

    public enum Failure: Error, CustomStringConvertible {
        case noVideo(String), notReady(String)
        public var description: String {
            switch self {
            case .noVideo(let id): "영상 \(id) 이 저장소에 없다"
            case .notReady(let id): "영상 \(id) 의 원본 사본이 아직 없다"
            }
        }
    }

    /// `JobQueue` 처리기로 쓴다.
    public var handler: JobQueue.Handler {
        { job in try await run(videoId: job.targetId) }
    }

    /// - Returns: 새로 만들었으면 true, 캐시를 썼으면 false.
    @discardableResult
    public func run(videoId: String) async throws -> Bool {
        guard let video = try await db.writer.read({ try VideoRecord.fetchOne($0, key: videoId) }) else {
            throw Failure.noVideo(videoId)
        }
        guard video.status == .ready, let path = video.localPath else { throw Failure.notReady(videoId) }
        let url = URL(fileURLWithPath: path)
        let fingerprint = try DigestBuilder.fingerprint(of: url)

        let existing = try await db.writer.read { try DigestRecord.fetchOne($0, key: videoId) }
        if let existing, existing.sourceFingerprint == fingerprint, existing.version == DigestBuilder.version {
            try db.log("digest.cached", subject: videoId)
            return false
        }

        let digest = try await DigestBuilder.build(
            videoID: videoId, url: url, transcriber: transcriber, workDir: root.appending(path: videoId)
        )
        let record = DigestRecord(
            videoId: videoId, version: DigestBuilder.version, sourceFingerprint: fingerprint,
            text: digest.text, sheetPaths: digest.sheetPaths,
            transcript: digest.transcript, subject: digest.subject, createdAt: Date()
        )
        try await db.writer.write { try record.save($0) }
        try db.log("digest.done", subject: videoId,
                   payload: digest.timings.mapValues { JSONValue.number($0) })
        return true
    }
}
