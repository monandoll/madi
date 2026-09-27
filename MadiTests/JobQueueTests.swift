import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 작업 큐 — 분석 1 · 렌더 1 동시, 재시작 이어 하기, 실패 기록.
struct JobQueueTests {

    /// 동시에 몇 개가 돌고 있었는지 센다.
    actor Meter {
        var now: [JobRecord.Kind: Int] = [:]
        var peak: [JobRecord.Kind: Int] = [:]
        var peakTotal = 0
        var order: [String] = []
        func enter(_ job: JobRecord) {
            now[job.kind, default: 0] += 1
            peak[job.kind] = max(peak[job.kind] ?? 0, now[job.kind]!)
            peakTotal = max(peakTotal, now.values.reduce(0, +))
            order.append(job.targetId)
        }
        func leave(_ job: JobRecord) { now[job.kind, default: 0] -= 1 }
    }

    private func handler(_ meter: Meter, sleepMs: UInt64 = 40) -> JobQueue.Handler {
        { job in
            await meter.enter(job)
            try await Task.sleep(nanoseconds: sleepMs * 1_000_000)
            await meter.leave(job)
        }
    }

    @Test("분석 1 · 렌더 1 — 같은 종류는 하나씩, 다른 종류는 같이 돈다")
    func concurrencyLimits() async throws {
        let db = try AppDatabase.inMemory()
        let meter = Meter()
        let queue = JobQueue(db: db, handlers: [.analyze: handler(meter), .render: handler(meter)])
        try await queue.start()
        for i in 0..<3 {
            try await queue.enqueue(.analyze, targetId: "v\(i)")
            try await queue.enqueue(.render, targetId: "c\(i)")
        }
        await queue.waitUntilIdle()
        #expect(await meter.peak[.analyze] == 1)
        #expect(await meter.peak[.render] == 1)
        #expect(await meter.peakTotal == 2)
        let done = try await db.writer.read { try JobRecord.filter(Column("state") == "done").fetchCount($0) }
        #expect(done == 6)
        // 먼저 건 것이 먼저 돈다.
        let analyzed = await meter.order.filter { $0.hasPrefix("v") }
        #expect(analyzed == ["v0", "v1", "v2"])
    }

    @Test("같은 대상에 두 번 걸어도 한 번만 돈다")
    func deduplicatesLiveJobs() async throws {
        let db = try AppDatabase.inMemory()
        let meter = Meter()
        let queue = JobQueue(db: db, handlers: [.analyze: handler(meter)])
        let a = try await queue.enqueue(.analyze, targetId: "v1")
        let b = try await queue.enqueue(.analyze, targetId: "v1")
        #expect(a.id == b.id)
        try await queue.start()
        await queue.waitUntilIdle()
        #expect(await meter.order == ["v1"])
    }

    @Test("도중에 죽은 작업은 다시 켜면 이어 한다")
    func resumesAfterCrash() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            var job = JobRecord(kind: .render, targetId: "c1")
            job.state = .running
            job.attempts = 1
            try job.insert(db)
        }
        let meter = Meter()
        let queue = JobQueue(db: db, handlers: [.render: handler(meter)])
        try await queue.start()
        await queue.waitUntilIdle()
        #expect(await meter.order == ["c1"])
        let job = try #require(try await db.writer.read { try JobRecord.fetchOne($0) })
        #expect(job.state == .done)
        #expect(job.attempts == 2)
    }

    @Test("실패는 에러와 함께 남고, 다음 작업은 계속 돈다")
    func failureIsRecordedAndQueueContinues() async throws {
        struct Boom: Error, CustomStringConvertible { var description: String { "원본을 못 읽음" } }
        let db = try AppDatabase.inMemory()
        let meter = Meter()
        let queue = JobQueue(db: db, handlers: [.analyze: { job in
            if job.targetId == "bad" { throw Boom() }
            await meter.enter(job); await meter.leave(job)
        }])
        try await queue.start()
        try await queue.enqueue(.analyze, targetId: "bad")
        try await queue.enqueue(.analyze, targetId: "good")
        await queue.waitUntilIdle()
        let jobs = try await db.writer.read { try JobRecord.order(Column("id")).fetchAll($0) }
        #expect(jobs.map(\.state) == [.failed, .done])
        #expect(jobs[0].error == "원본을 못 읽음")
        // 걸린 시간이 이벤트로 남는다 (§14).
        let events = try await db.writer.read { try EventRecord.fetchAll($0) }.map(\.kind)
        #expect(events.contains("job.failed") && events.contains("job.done"))
    }
}
