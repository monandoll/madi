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
    /// 도는 작업 — 멈추기(■) · 촬영본 삭제가 대상 id 로 찾아 취소한다.
    private var running: [Int64: (targetId: String, task: Task<Void, Never>)] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// 이 Mac 이 지금 무거운 일을 얼마나 받을 수 있나 (`LoadGovernor`). 없으면 언제나 `full` — 테스트 기본값.
    private let loadLevel: @Sendable () -> LoadLevel
    /// 무거운 일을 미뤄 뒀을 때 다시 볼 간격.
    private let recheckAfter: Duration
    private var recheckScheduled = false

    /// 무거운 일 — 영상을 통째로 읽거나 새로 만든다. 맥에 여유가 없으면 이 둘은 **하나씩만** 돈다.
    /// AI 턴(agent · selfEval · chat)은 다른 프로세스(CLI)가 하고 가벼워서 그대로 둔다.
    static func isHeavy(_ kind: JobRecord.Kind) -> Bool { kind == .analyze || kind == .render }

    public init(db: AppDatabase, handlers: [JobRecord.Kind: Handler],
                loadLevel: @escaping @Sendable () -> LoadLevel = { .full },
                recheckAfter: Duration = .seconds(3)) {
        self.db = db
        self.handlers = handlers
        self.loadLevel = loadLevel
        self.recheckAfter = recheckAfter
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

    /// 대상의 작업을 멈춘다 ("멈추기" · 촬영본 삭제). 줄 선 작업은 바로, **도는 작업은 취소를 보내** 끊는다 —
    /// 분석은 프레임마다, AI 턴은 CLI 를 바로 끝내서 멈춘다 (전에는 도는 작업이 끝까지 갔다 — 2026-09-30 실제 앱에서
    /// ■ 를 눌러도 codex 가 끝까지 돌았다). 멈춘 작업은 `failed` + 이유 "멈춤" 으로 남는다 (자동으로 다시 하지 않는다).
    @discardableResult
    public func cancel(targetIds: Set<String>) throws -> Int {
        var stopping = 0
        for (_, r) in running where targetIds.contains(r.targetId) {
            r.task.cancel()
            stopping += 1
        }
        guard !targetIds.isEmpty else { return 0 }
        let ids = Array(targetIds)
        let n = try db.writer.write { db -> Int in
            try db.execute(sql: """
                UPDATE job SET state = 'failed', error = '멈춤', finishedAt = ?
                WHERE state = 'queued' AND targetId IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """, arguments: StatementArguments([Date()] + ids)!)
            return db.changesCount
        }
        if n + stopping > 0 { try? db.log("job.cancelled", payload: ["count": .number(Double(n + stopping))]) }
        pump()
        return n + stopping
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
        // 단, 맥에 여유가 없으면(LoadGovernor) 무거운 일(분석 · 렌더)은 하나씩, 위험하면 식을 때까지 새로 시작하지 않는다.
        let level = loadLevel()
        var heldBack = false
        for kind in JobRecord.Kind.allCases where !busy.contains(kind) {
            if Self.isHeavy(kind), level >= .eased,
               level == .paused || busy.contains(where: Self.isHeavy) {
                if hasQueued(kind) { heldBack = true }
                continue
            }
            guard let job = try? claimNext(kind) else { continue }
            busy.insert(kind)
            // 사람이 기다리는 일이다 — 우선순위를 명시한다. 물려받으면 부른 쪽(폴더 · 사진 감시)의 낮은 우선순위로
            // 효율 코어에 밀릴 수 있다
            let task = Task(priority: .userInitiated) { await self.run(job) }
            if let id = job.id { running[id] = (job.targetId, task) }
        }
        // 미뤄 둔 무거운 일 — 식었는지 조금 뒤에 다시 본다 (끝난 일이 없어도)
        if heldBack, !recheckScheduled {
            recheckScheduled = true
            Task { [recheckAfter] in
                try? await Task.sleep(for: recheckAfter)
                await self.recheck()
            }
        }
        if isIdle() {
            let waiters = idleWaiters
            idleWaiters = []
            for w in waiters { w.resume() }
        }
    }

    private func recheck() {
        recheckScheduled = false
        pump()
    }

    private func hasQueued(_ kind: JobRecord.Kind) -> Bool {
        ((try? db.writer.read {
            try JobRecord.filter(Column("kind") == kind.rawValue && Column("state") == "queued").fetchCount($0)
        }) ?? 0) > 0
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
            // 멈춰서 끝난 것은 이유를 "멈춤" 으로 — 화면은 이걸 실패가 아니라 사람이 멈춘 것으로 본다
            do { try await handler(job) } catch { failure = Task.isCancelled ? "멈춤" : "\(error)" }
        } else {
            failure = "\(job.kind.rawValue) 작업을 처리할 곳이 없다"
        }
        let seconds = Date().timeIntervalSince(started)
        record(job, failure: failure)
        try? db.log(
            failure == nil ? "job.done" : "job.failed", subject: job.targetId,
            payload: ["kind": .string(job.kind.rawValue), "seconds": .number(seconds)]
        )
        if let id = job.id { running[id] = nil }
        busy.remove(job.kind)
        pump()
    }

    /// 끝난 작업을 적는다 — **동기 쓰기.** 멈춘(취소된) 작업 안에서 `await` 쓰기는 GRDB 가 CancellationError 로
    /// 거절해, 작업이 DB 에 영영 `running` 으로 남았다.
    private func record(_ job: JobRecord, failure: String?) {
        try? db.writer.write { db in
            var done = job
            done.state = failure == nil ? .done : .failed
            done.error = failure
            done.finishedAt = Date()
            try done.update(db)
        }
    }
}
