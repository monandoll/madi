import Foundation
import MadiKit

/// 진행률 게시판(메모리)에서 읽은 값 — DB 에 없는 것들.
struct ProgressReading: Sendable {
    var render: [String: Double] = [:]
    var imports: [String: Double] = [:]
    var analysis: [String: AnalysisProgress] = [:]
    var cooling = false
}

/// 화면이 보는 가장 최근 스냅숏 (`AppController`).
///
/// 새 스냅숏은 DB 가 바뀔 때 들어오고(`receive`), 작업이 도는 동안에는 0.5초마다 진행률만 다시 칠한다(`refresh`).
/// 진행률 게시판은 액터라 **읽는 동안(await) 새 스냅숏이 들어올 수 있다.** 그래서 다 읽은 뒤 그때의 최신 스냅숏에 칠한다.
/// 전에는 읽기 전에 사본을 잡아 두고 읽은 뒤 되써서, 그사이 들어온 새 스냅숏(렌더 끝남 · 삭제)을 옛 사본으로 덮었다 —
/// 화면이 "만드는 중 0%" 에 갇히고 지운 촬영본이 목록에 남았다 (2026-09-30 실제 앱, DB 에는 도는 작업이 없었다).
@MainActor
final class SnapshotBox {
    private(set) var current: LibrarySnapshot?
    private var received = 0

    /// 새 스냅숏. 진행률을 읽어 칠한 뒤 둔다 — 읽는 사이 더 새 스냅숏이 들어왔으면 이건 버린다.
    func receive(_ snap: LibrarySnapshot, reading: () async -> ProgressReading) async {
        received += 1
        let mine = received
        let r = await reading()
        guard mine == received else { return }
        var s = snap
        s.apply(r)
        current = s
    }

    /// 진행률만 다시 칠한다 — 읽은 **뒤의** 최신 스냅숏에. 스냅숏이 아직 없으면 false.
    @discardableResult
    func refresh(now: Date = Date(), reading: () async -> ProgressReading) async -> Bool {
        let r = await reading()
        guard var s = current else { return false }
        s.apply(r)
        s.now = now
        current = s
        return true
    }

    /// 작업이 줄 서 있거나 돌거나, 원본을 받는 중 — 진행률 타이머를 돌릴 때다.
    var isBusy: Bool {
        guard let s = current else { return false }
        return s.jobs.contains { $0.state == .queued || $0.state == .running } || !s.importProgress.isEmpty
    }
}

private extension LibrarySnapshot {
    mutating func apply(_ r: ProgressReading) {
        setProgress(render: r.render, import: r.imports, analysis: r.analysis)
        cooling = r.cooling
    }
}
