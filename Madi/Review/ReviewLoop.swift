import Foundation
import GRDB

/// 렌더가 끝난 결과물을 보여 줄지, 되먹임을 걸지 정한다 (AGENTS.md §7-6 · §8, docs/stage-5.spec.md 3번).
///
/// ```
/// 렌더 → 리포트 selfEval 목록 → ┬ 비었다                      → 보여 준다
///                               ├ 남았고 되먹임 2회 미만        → 숨기고 selfEval 작업
///                               └ 2회 다 썼다 ┬ 소프트만 남음   → 보여 준다 (채팅에 한 줄)
///                                             └ 하드가 남음     → 사슬에서 하드 실패 없는 앞 판을 보여 주거나, 끝내 실패
/// ```
/// - 되먹임 횟수는 연속된 `selfEval` 조상으로 센다 — 6단계 채팅 수정(`chat`)은 세지 않는다
/// - 보여 주기를 막는 것은 하드(G1 · G4 · G6) `fail` 뿐이다 (§8). 소프트는 되먹임만 부른다 (결정 ②)
public struct ReviewLoop: Sendable {
    public static let maxRounds = 2

    public enum Decision: Equatable, Sendable {
        case show
        case retry
        case gaveUp
    }

    let db: AppDatabase
    let enqueueSelfEval: @Sendable (String) async throws -> Void

    public init(db: AppDatabase, enqueueSelfEval: @escaping @Sendable (String) async throws -> Void) {
        self.db = db; self.enqueueSelfEval = enqueueSelfEval
    }

    /// 되먹임 항목 중 보여 주기를 막는 것.
    public static func hardItems(_ items: [String]) -> [String] {
        items.filter { item in RenderJob.hardGates.contains { item == $0 || item.hasPrefix($0 + ".") } }
    }

    public static func decide(items: [String], rounds: Int) -> Decision {
        if items.isEmpty { return .show }
        if rounds < maxRounds { return .retry }
        return hardItems(items).isEmpty ? .show : .gaveUp
    }

    /// 이 편집안까지 이어진 self-eval 횟수.
    public static func rounds(_ db: Database, compositionID: String) throws -> Int {
        var n = 0
        var id: String? = compositionID
        while let current = id, let rec = try CompositionRecord.fetchOne(db, key: current), rec.origin == .selfEval {
            n += 1
            id = rec.revisionOf
        }
        return n
    }

    static func items(_ output: OutputRecord) -> [String] {
        guard let json = output.reviewReport,
              let report = try? JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8)),
              case .array(let list)? = report["selfEval"] else { return [] }
        return list.compactMap { if case .string(let s) = $0 { s } else { nil } }
    }

    @discardableResult
    public func afterRender(_ output: OutputRecord) async throws -> Decision {
        let items = Self.items(output)
        let rounds = try await db.writer.read { try Self.rounds($0, compositionID: output.compositionId) }
        let decision = Self.decide(items: items, rounds: rounds)
        let payload: [String: JSONValue] = [
            "output": .string(output.id), "rounds": .number(Double(rounds)),
            "items": .array(items.map { .string($0) }),
        ]
        switch decision {
        case .show:
            try await setVerdict(output.id, .shown)
            try db.log("review.shown", subject: output.compositionId, payload: payload)
        case .retry:
            try await setVerdict(output.id, .hidden)
            try db.log("review.retry", subject: output.compositionId, payload: payload)
            try await enqueueSelfEval(output.compositionId)
        case .gaveUp:
            // 사슬에서 하드 실패가 없는 가장 늦은 앞 판이 있으면 그걸 보여 준다 (소프트 때문에 되먹임을 걸었던 판).
            let fallback = try await db.writer.read { db -> OutputRecord? in
                var id = try CompositionRecord.fetchOne(db, key: output.compositionId)?.revisionOf
                while let current = id {
                    if let o = try OutputRecord.filter(Column("compositionId") == current).fetchOne(db),
                       Self.hardItems(Self.items(o)).isEmpty { return o }
                    id = try CompositionRecord.fetchOne(db, key: current)?.revisionOf
                }
                return nil
            }
            if let fallback {
                try await setVerdict(output.id, .hidden)
                try await setVerdict(fallback.id, .shown)
            } else {
                try await setVerdict(output.id, .failed)
            }
            var p = payload
            p["fallback"] = .string(fallback?.id ?? "")
            try db.log("review.gaveUp", subject: output.compositionId, payload: p)
        }
        return decision
    }

    private func setVerdict(_ outputID: String, _ verdict: OutputRecord.Verdict) async throws {
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE output SET verdict = ? WHERE id = ?", arguments: [verdict.rawValue, outputID])
        }
    }
}
