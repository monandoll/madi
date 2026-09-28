import Foundation
import GRDB

/// 작업 큐 (AGENTS.md §2 Queue). **분석 1 · 렌더 1 · AI 1** 이 동시에 돈다.
///
/// - 상태는 전부 DB(`job`)에 있다. 앱이 도중에 죽어도 다시 켜면 이어 한다
/// - 실패는 에러와 함께 남기고 다음 작업으로 넘어간다. 자동으로 다시 시도하지 않는다 —
///   같은 입력은 같은 이유로 또 실패한다. 다시 할지는 사람이(또는 상위 로직이) 정한다
/// - 작업마다 걸린 시간을 `event` 에 남긴다 — "편집 10분" 과 3단계 3분 판정이 이걸 읽는다 (§14)
public actor JobQueue {
    public typealias Handler = @Sendable (JobRecord) async throws -> Void

    private let db: AppDatabase
    private let handlers: [JobRecord.Kind: Handler]
    private var busy: Set<JobRecord.Kind> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(db: AppDatabase, handlers: [JobRecord.Kind: Handler]) {
        self.db = db
        self.handlers = handlers
    }

    /// 앱 시작 때 한 번. 지난 실행에서 `running` 으로 남은 작업은 도중에 죽은 것이다 — 다시 줄 세운다.
    public func start() throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE job SET state = 'queued', startedAt = NULL WHERE state = 'running'")
        }
        pump()
    }

    /// 작업을 건다. 같은 대상에 같은 종류의 작업이 이미 살아 있으면 **그걸 돌려준다** (두 번 돌지 않는다).
    @discardableResult
    public func enqueue(_ kind: JobRecord.Kind, targetId: String) throws -> JobRecord {
        let job = try db.writer.write { db -> JobRecord in
            if let live = try JobRecord
                .filter(Column("kind") == kind.rawValue && Column("targetId") == targetId)
                .filter([JobRecord.State.queued.rawValue, JobRecord.State.running.rawValue].contains(Column("state")))
                .fetchOne(db) {
                return live
            }
            var job = JobRecord(kind: kind, targetId: targetId)
            try job.insert(db)
            return job
        }
        pump()
        return job
    }

    /// 줄 선 작업을 멈춘다 ("멈추기"). **이미 도는 작업은 끝까지 간다** — 도중에 끊는 길은 아직 없다.
    /// 멈춘 작업은 `failed` + 이유 "멈춤" 으로 남는다 (자동으로 다시 하지 않는다).
    @discardableResult
    public func cancel(targetIds: Set<String>) throws -> Int {
        guard !targetIds.isEmpty else { return 0 }
        let ids = Array(targetIds)
        let n = try db.writer.write { db -> Int in
            try db.execute(sql: """
                UPDATE job SET state = 'failed', error = '멈춤', finishedAt = ?
                WHERE state = 'queued' AND targetId IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """, arguments: StatementArguments([Date()] + ids)!)
            return db.changesCount
        }
        if n > 0 { try? db.log("job.cancelled", payload: ["count": .number(Double(n))]) }
        pump()
        return n
    }

    /// 실패한 작업을 다시 줄 세운다.
    public func retry(jobId: Int64) throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE job SET state = 'queued', error = NULL WHERE id = ? AND state = 'failed'",
                           arguments: [jobId])
        }
        pump()
    }

    /// 줄 선 작업도 도는 작업도 없어질 때까지 기다린다. 테스트 · 스파이크용.
    public func waitUntilIdle() async {
        if isIdle() { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: -

    private func isIdle() -> Bool {
        guard busy.isEmpty else { return false }
        let queued = (try? db.writer.read { try JobRecord.filter(Column("state") == "queued").fetchCount($0) }) ?? 0
        return queued == 0
    }

    private func pump() {
        // 종류마다 하나씩 동시에 돈다 — 분석 1 · 렌더 1 (§2) · AI 1 (4단계).
        for kind in JobRecord.Kind.allCases where !busy.contains(kind) {
            guard let job = try? claimNext(kind) else { continue }
            busy.insert(kind)
            // 사람이 기다리는 일이다 — 우선순위를 명시한다. 물려받으면 부른 쪽(폴더 · 사진 감시)의 낮은 우선순위로
            // 효율 코어에 밀릴 수 있다
            Task(priority: .userInitiated) { await self.run(job) }
        }
        if isIdle() {
            let waiters = idleWaiters
            idleWaiters = []
            for w in waiters { w.resume() }
        }
    }

    /// 가장 오래된 줄 선 작업을 잡는다. 잡는 것과 `running` 표시는 한 트랜잭션이다.
    private func claimNext(_ kind: JobRecord.Kind) throws -> JobRecord? {
        try db.writer.write { db -> JobRecord? in
            guard var job = try JobRecord
                .filter(Column("kind") == kind.rawValue && Column("state") == "queued")
                .order(Column("createdAt"), Column("id"))
                .fetchOne(db) else { return nil }
            job.state = .running
            job.startedAt = Date()
            job.attempts += 1
            try job.update(db)
            return job
        }
    }

    private func run(_ job: JobRecord) async {
        let started = Date()
        var failure: String?
        if let handler = handlers[job.kind] {
            do { try await handler(job) } catch { failure = "\(error)" }
        } else {
            failure = "\(job.kind.rawValue) 작업을 처리할 곳이 없다"
        }
        let seconds = Date().timeIntervalSince(started)
        let failed = failure
        try? await db.writer.write { db in
            var done = job
            done.state = failed == nil ? .done : .failed
            done.error = failed
            done.finishedAt = Date()
            try done.update(db)
        }
        try? db.log(
            failure == nil ? "job.done" : "job.failed", subject: job.targetId,
            payload: ["kind": .string(job.kind.rawValue), "seconds": .number(seconds)]
        )
        busy.remove(job.kind)
        pump()
    }
}
