import Foundation
import GRDB

/// 바꾸는 층(앱 `Madi/App/Bridge`)의 입력 — DB 를 **한 번에** 읽은 값 (docs/stage-6.spec.md 6번, `docs/design/viewdata-map.md`).
///
/// 화면은 `ViewData`(Madi/UI — 디자인 소유)만 받는다. 이 값에서 `ViewDataMapper` 가 ViewData 를 만든다.
/// 한 트랜잭션에서 읽어 서로 어긋나지 않게 한다 (예: 편집안은 있는데 결과물 행이 아직 없는 틈).
public struct LibrarySnapshot: Sendable {
    public var videos: [VideoRecord]
    public var compositions: [CompositionRecord]
    public var outputs: [OutputRecord]
    /// 살아 있는 작업 (queued · running) + 오늘 실패한 작업
    public var jobs: [JobRecord]
    public var chats: [ChatRecord]
    public var exports: [ExportRecord] = []
    /// 영상마다 전사 낱말 수. 다이제스트가 없으면 없다.
    public var wordCounts: [String: Int]
    public var now: Date
    /// 만드는 중 진행률 (편집안 id → 0…1). 메모리 게시판에서 온다 — DB 가 아니다.
    public var progress: [String: Double] = [:]
    /// 있는 그림 파일 경로. 없는 그림은 화면이 회색 자리표시로 그린다.
    public var thumbnails: Set<String> = []
    /// 그림 자리를 정하는 곳 (경로 규칙).
    public var thumbnailStore = Thumbnails()

    public init(videos: [VideoRecord] = [], compositions: [CompositionRecord] = [], outputs: [OutputRecord] = [],
                jobs: [JobRecord] = [], chats: [ChatRecord] = [], wordCounts: [String: Int] = [:], now: Date = Date(),
                exports: [ExportRecord] = []) {
        self.videos = videos; self.compositions = compositions
        // 휴지통으로 옮긴 결과물은 어디에도 안 나온다 — 여기서 한 번 거른다
        self.outputs = outputs.filter { $0.trashedAt == nil }
        self.jobs = jobs; self.chats = chats; self.wordCounts = wordCounts; self.now = now; self.exports = exports
    }

    /// 있는 그림만 골라 둔다 (파일을 한 번씩 본다).
    public mutating func attach(thumbnails store: Thumbnails, progress: [String: Double]) {
        self.progress = progress
        thumbnailStore = store
        var paths: [URL] = videos.map { store.video($0.id) } + outputs.map { store.output($0.id) }
        for c in compositions {
            if let comp = try? c.composition() { paths += comp.scenes.map { store.scene(c.id, $0.id) } }
        }
        thumbnails = Set(paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) })
    }

    public static func read(_ db: Database, now: Date = Date()) throws -> LibrarySnapshot {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let jobs = try JobRecord.fetchAll(db).filter {
            $0.state == .queued || $0.state == .running || ($0.state == .failed && ($0.finishedAt ?? .distantPast) >= startOfDay)
        }
        var words: [String: Int] = [:]
        for d in try DigestRecord.fetchAll(db) { words[d.videoId] = d.transcript.words.count }
        return LibrarySnapshot(
            videos: try VideoRecord.fetchAll(db),
            compositions: try CompositionRecord.order(Column("createdAt")).fetchAll(db),
            outputs: try OutputRecord.order(Column("createdAt")).fetchAll(db),
            jobs: jobs,
            chats: try ChatRecord.order(Column("createdAt")).fetchAll(db),
            wordCounts: words,
            now: now,
            exports: try ExportRecord.order(Column("createdAt")).fetchAll(db)
        )
    }

    // MARK: - 자주 쓰는 물음

    public func compositions(of videoID: String) -> [CompositionRecord] {
        compositions.filter { $0.videoId == videoID }
    }

    public func output(of compositionID: String) -> OutputRecord? {
        outputs.first { $0.compositionId == compositionID }
    }

    /// 사람이 본 판 — 초안 · 채팅 수정. 되먹임 판(`selfEval`)은 번호를 받지 않는다.
    public func visibleVersions(of videoID: String) -> [CompositionRecord] {
        compositions(of: videoID).filter { $0.origin != .selfEval }
    }

    /// 되먹임 판이면 그 판이 나온 사람이 본 판(가장 가까운 draft · chat 조상).
    public func versionRoot(of compositionID: String) -> CompositionRecord? {
        var id: String? = compositionID
        while let current = id, let rec = compositions.first(where: { $0.id == current }) {
            if rec.origin != .selfEval { return rec }
            id = rec.revisionOf
        }
        return nil
    }

    /// 사람이 본 판 하나에서 나온(되먹임 포함) 결과물 중 보여 주는 것.
    public func shownOutput(forVersion versionID: String) -> OutputRecord? {
        outputs.last { $0.verdict == .shown && versionRoot(of: $0.compositionId)?.id == versionID }
    }

    /// 이 영상에 걸린 살아 있는 작업.
    public func liveJobs(of videoID: String) -> [JobRecord] {
        let comps = Set(compositions(of: videoID).map(\.id))
        let chatIDs = Set(chats.filter { $0.videoId == videoID }.map(\.id))
        return jobs.filter { job in
            guard job.state == .queued || job.state == .running else { return false }
            switch job.kind {
            case .analyze, .agent: return job.targetId == videoID
            case .render, .selfEval: return comps.contains(job.targetId)
            case .chat: return chatIDs.contains(job.targetId)
            }
        }
    }
}
