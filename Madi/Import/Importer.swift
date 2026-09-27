import Foundation
import GRDB

/// 들어온 영상 하나. 사진 앱(PhotoKit)과 폴더 감시가 이걸 만들어 `Importer` 에 넘긴다.
///
/// 원본을 받는 방법만 다르다 — iCloud 에서 받거나(사진) 파일을 복사하거나(폴더).
/// 새 추상화(프로토콜)를 만들지 않는다 (§3 — 추상화는 두 개만). 받는 함수를 값으로 들고 다닌다.
public struct IncomingVideo: Sendable {
    public var source: VideoRecord.Source
    /// 사진: PHAsset.localIdentifier · 폴더: 파일 경로. 같은 영상을 두 번 들이지 않는 키다.
    public var sourceRef: String
    /// 원본 파일 확장자 (`mov` · `mp4`).
    public var fileExtension: String
    public var capturedAt: Date?
    /// 원본을 `destination` 에 쓴다. 진행률 0~1 을 알린다.
    public var fetch: @Sendable (_ destination: URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> Void

    public init(
        source: VideoRecord.Source, sourceRef: String, fileExtension: String, capturedAt: Date?,
        fetch: @escaping @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> Void
    ) {
        self.source = source; self.sourceRef = sourceRef; self.fileExtension = fileExtension
        self.capturedAt = capturedAt; self.fetch = fetch
    }
}

/// 가져오기 (AGENTS.md §2 촬영본이 들어오는 길).
///
/// ```
/// 행 생성(importing) → 원본 사본 받기 → 크기 · 길이 읽기 → ready → 분석 작업
/// ```
/// - 행은 **원본을 받기 전에** 만든다 — "앱에 떴다" 는 이 시각이다 (3단계 3분 판정의 t1)
/// - 원본 사본은 앱 폴더에 둔다. 사진 앱에서 지우거나 폴더에서 옮겨도 편집안을 다시 그릴 수 있어야 한다 (§1-8)
/// - 받다가 실패한 영상은 다음에 같은 영상이 다시 보이면 이어 받는다
public struct Importer: Sendable {
    public let db: AppDatabase
    public let queue: JobQueue?
    public let originals: URL

    public init(db: AppDatabase, queue: JobQueue?, originals: URL = Importer.defaultOriginals) {
        self.db = db; self.queue = queue; self.originals = originals
    }

    public static var defaultOriginals: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/originals", directoryHint: .isDirectory)
    }

    /// - Returns: 새로 들였거나 이어 받은 영상. 이미 준비된 영상이면 nil.
    @discardableResult
    public func receive(_ item: IncomingVideo, progress: (@Sendable (Double) -> Void)? = nil) async throws -> VideoRecord? {
        var video: VideoRecord = try await db.writer.write { db in
            if let known = try VideoRecord.filter(Column("sourceRef") == item.sourceRef).fetchOne(db) {
                return known
            }
            let fresh = VideoRecord(source: item.source, sourceRef: item.sourceRef,
                                    capturedAt: item.capturedAt, status: .importing)
            try fresh.insert(db)
            return fresh
        }
        if video.status == .ready { return nil }
        try db.log("import.seen", subject: video.id, payload: ["source": .string(item.source.rawValue)])

        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let destination = originals.appending(path: "\(video.id).\(item.fileExtension.lowercased())")
        do {
            try? FileManager.default.removeItem(at: destination)   // 받다 만 조각
            try await item.fetch(destination) { progress?($0) }
            let info = try await FrameSheet.info(of: destination)
            video.localPath = destination.path
            video.durationSec = info.duration
            video.width = Int(info.size.width.rounded())
            video.height = Int(info.size.height.rounded())
            video.status = .ready
            video.error = nil
        } catch {
            video.status = .failed
            video.error = "\(error)"
        }
        let saved = video
        try await db.writer.write { try saved.update($0) }

        guard saved.status == .ready else {
            try db.log("import.failed", subject: saved.id, payload: ["error": .string(saved.error ?? "")])
            return saved
        }
        try db.log("import.ready", subject: saved.id,
                   payload: ["durationSec": .number(saved.durationSec ?? 0)])
        try await queue?.enqueue(.analyze, targetId: saved.id)
        return saved
    }
}
