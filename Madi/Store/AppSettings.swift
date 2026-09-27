import Foundation

/// 사람이 고르는 설정값 (ViewData `SettingsValues` · `StudioStatus`). **이름을 코드에 박지 않는다** (§1-7).
public struct AppSettings: Sendable {
    public static let studioNameKey = "madi.studioName"
    public static let keepDaysKey = "madi.keepDays"
    /// 설정 화면 기본값 90일 (docs/design/decisions.md 5단계). 0 이면 계속 둔다.
    public static let defaultKeepDays = 90

    public init() {}

    public var studioName: String {
        get { UserDefaults.standard.string(forKey: Self.studioNameKey) ?? "" }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.studioNameKey) }
    }

    public var keepDays: Int {
        get { UserDefaults.standard.object(forKey: Self.keepDaysKey) as? Int ?? Self.defaultKeepDays }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.keepDaysKey) }
    }
}

/// 보관 기간이 지난 촬영본의 **앱 사본만** 지운다. 사진 앱 원본과 결과물은 그대로다
/// (docs/design/decisions.md 5단계 답 — 확인 없이 조용히, 앱 사본만).
public enum Retention {
    /// 지운 영상 id 들. 작업이 걸려 있는 영상은 건너뛴다.
    @discardableResult
    public static func sweep(_ db: AppDatabase, keepDays: Int, now: Date = Date()) async throws -> [String] {
        guard keepDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86400)
        let (videos, jobs) = try await db.writer.read { db in
            (try VideoRecord.fetchAll(db), try JobRecord.fetchAll(db).filter { $0.state == .queued || $0.state == .running })
        }
        let busy = Set(jobs.map(\.targetId))
        var removed: [String] = []
        for v in videos where (v.capturedAt ?? v.importedAt) < cutoff && v.localPath != nil && !busy.contains(v.id) {
            if let path = v.localPath { try? FileManager.default.removeItem(atPath: path) }
            try await db.writer.write { db in
                try db.execute(sql: "UPDATE video SET localPath = NULL WHERE id = ?", arguments: [v.id])
            }
            removed.append(v.id)
        }
        if !removed.isEmpty { try? db.log("retention.swept", payload: ["count": .number(Double(removed.count))]) }
        return removed
    }
}
