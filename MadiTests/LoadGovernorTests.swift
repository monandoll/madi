import Testing
import Foundation
import GRDB
@testable import MadiKit

/// 맥이 뜨겁거나 메모리가 모자라면 앱이 스스로 덜 일한다 (`LoadGovernor`).
struct LoadGovernorTests {

    private func inputs(thermal: Int = 0, lowPower: Bool = false, memory: MemoryPressure = .normal, gb: Double = 32) -> LoadInputs {
        LoadInputs(thermal: thermal, lowPower: lowPower, memory: memory, physicalMemoryGB: gb)
    }

    @Test("단계 — 보통이면 full, 약간 · 저전력 · 8GB 는 하나씩, 뜨거움 · 메모리 경고는 쉬어 가기, 위험은 멈춤")
    func levels() {
        #expect(LoadGovernor.level(inputs()) == .full)
        #expect(LoadGovernor.level(inputs(thermal: 1)) == .eased)
        #expect(LoadGovernor.level(inputs(lowPower: true)) == .eased)
        #expect(LoadGovernor.level(inputs(gb: 8)) == .eased)          // 8GB 맥북 에어 — 처음부터 하나씩
        #expect(LoadGovernor.level(inputs(gb: 16)) == .full)
        #expect(LoadGovernor.level(inputs(thermal: 2)) == .gentle)
        #expect(LoadGovernor.level(inputs(memory: .warning)) == .gentle)
        #expect(LoadGovernor.level(inputs(thermal: 3)) == .paused)
        #expect(LoadGovernor.level(inputs(memory: .critical, gb: 8)) == .paused)
    }

    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var running = 0, maxHeavy = 0, started: [String] = []
        var level: LoadLevel = .full
    }

    private func queue(_ db: AppDatabase, _ box: Box, hold: Duration = .milliseconds(150)) -> JobQueue {
        let heavy: JobQueue.Handler = { job in
            box.lock.withLock { box.running += 1; box.maxHeavy = max(box.maxHeavy, box.running); box.started.append(job.targetId) }
            try await Task.sleep(for: hold)
            box.lock.withLock { box.running -= 1 }
        }
        return JobQueue(db: db, handlers: [.analyze: heavy, .render: heavy],
                        loadLevel: { box.lock.withLock { box.level } }, recheckAfter: .milliseconds(50))
    }

    @Test("여유가 없으면 무거운 일(분석 · 렌더)은 하나씩만 돈다")
    func heavySingleFlight() async throws {
        let db = try AppDatabase.inMemory()
        let box = Box(); box.level = .eased
        let q = queue(db, box)
        try await q.enqueue(.analyze, targetId: "v1")
        try await q.enqueue(.render, targetId: "c1")
        await q.waitUntilIdle()
        #expect(box.started.count == 2 && box.maxHeavy == 1)
    }

    @Test("위험하면 식을 때까지 새로 시작하지 않고, 식으면 이어 한다")
    func pausedWaits() async throws {
        let db = try AppDatabase.inMemory()
        let box = Box(); box.level = .paused
        let q = queue(db, box, hold: .milliseconds(10))
        try await q.enqueue(.analyze, targetId: "v1")
        try await Task.sleep(for: .milliseconds(300))
        #expect(box.started.isEmpty)                    // 멈춰 있다
        box.lock.withLock { box.level = .full }         // 식었다
        await q.waitUntilIdle()
        #expect(box.started == ["v1"])
    }

    @Test("영상 읽기는 프레임마다 쉬어 갈 기회를 준다 — 조절기가 멈추면 읽기도 멈춰 기다린다")
    func scanPaces() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "madi-pace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "v.mp4")
        try await TestVideo.makeSolid(at: url, seconds: 1)
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        let started = Date()
        _ = try await VideoScan.run(url: url, subjectTimes: [0, 0.5], cutFPS: 5, onSubject: { _, _ in },
                                    pace: { _ in count.n += 1; if count.n == 3 { try? await Task.sleep(for: .milliseconds(300)) } })
        #expect(count.n > 3)                                          // 프레임마다 불렀다
        #expect(Date().timeIntervalSince(started) >= 0.3)             // 쉬는 동안 읽기가 기다렸다
    }
}
