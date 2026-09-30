import Testing
import Foundation
@testable import MadiKit
@testable import MadiBridgeTests

/// 화면이 보는 스냅숏 — 새 스냅숏과 진행률 칠하기가 서로 덮지 않는다 (2026-09-30 "만드는 중" 에 갇힘).
@MainActor
struct SnapshotBoxTests {

    func snap(renderRunning: Bool) -> LibrarySnapshot {
        var j = JobRecord(kind: .render, targetId: "c1", createdAt: Date())
        j.state = .running
        j.id = 1
        return LibrarySnapshot(jobs: renderRunning ? [j] : [])
    }

    @Test("진행률을 읽는 사이 렌더가 끝난 스냅숏이 들어오면 그게 남는다 — 옛 사본(도는 중)으로 덮지 않는다")
    func refreshKeepsNewerSnapshot() async {
        let box = SnapshotBox()
        await box.receive(snap(renderRunning: true)) { ProgressReading(render: ["c1": 0.5]) }
        #expect(box.isBusy)

        // 타이머가 게시판을 읽는 동안(await) DB 가 바뀌어 새 스냅숏이 들어온다
        await box.refresh {
            await box.receive(self.snap(renderRunning: false)) { ProgressReading() }
            return ProgressReading(render: ["c1": 1])
        }
        #expect(box.current?.jobs.isEmpty == true)
        #expect(!box.isBusy)                         // 타이머가 멈출 수 있다
        #expect(box.current?.progress == ["c1": 1])  // 진행률은 새 스냅숏에 칠해졌다
    }

    @Test("늦게 끝난 옛 스냅숏이 새 스냅숏을 덮지 않는다")
    func olderReceiveLoses() async {
        let box = SnapshotBox()
        await box.receive(snap(renderRunning: true)) {
            await box.receive(self.snap(renderRunning: false)) { ProgressReading() }
            return ProgressReading()
        }
        #expect(box.current?.jobs.isEmpty == true)
    }

    @Test("스냅숏이 오기 전에는 칠할 것이 없다 — 타이머는 멈춘다")
    func refreshWithoutSnapshot() async {
        let box = SnapshotBox()
        #expect(await box.refresh { ProgressReading() } == false)
        #expect(!box.isBusy)
    }

    @Test("원본을 받는 중이면 작업이 없어도 바쁘다 — 받기 진행률이 움직인다")
    func importingIsBusy() async {
        let box = SnapshotBox()
        await box.receive(snap(renderRunning: false)) { ProgressReading(imports: ["v": 0.3]) }
        #expect(box.isBusy)
        await box.refresh { ProgressReading() }
        #expect(!box.isBusy)
    }

    @Test("그림이 늘었다는 알림은 들어오는 중인 새 스냅숏을 밀어내지 않는다 — 보관함 목록이 0개로 남던 것")
    func rethumbDoesNotDropIncomingSnapshot() async {
        let box = SnapshotBox()
        await box.receive(LibrarySnapshot()) { ProgressReading() }          // 옛 것 — 촬영본 0개
        let listed = LibrarySnapshot(videos: [VideoRecord(id: "a", source: .photos, sourceRef: "ph:a", status: .listed)])
        // 새 스냅숏이 진행률을 읽는 사이(await)에 그림 알림이 온다
        await box.receive(listed) {
            box.reattachThumbnails(Thumbnails(root: FileManager.default.temporaryDirectory.appending(path: "none-\(UUID().uuidString)")))
            return ProgressReading()
        }
        #expect(box.current?.videos.count == 1)
        // 그림만 다시 골라도 진행률은 그대로다
        var busy = listed
        busy.setProgress(render: ["c": 0.4], import: ["a": 0.7], analysis: [:])
        await box.receive(busy) { ProgressReading(render: ["c": 0.4], imports: ["a": 0.7]) }
        box.reattachThumbnails(Thumbnails(root: FileManager.default.temporaryDirectory.appending(path: "none-\(UUID().uuidString)")))
        #expect(box.current?.progress["c"] == 0.4 && box.current?.importProgress["a"] == 0.7)
    }
}
