import Foundation
import GRDB

// 테이블 한 줄 = 구조체 하나. 저장 · 큐 · 화면이 같은 타입을 쓴다 (AGENTS.md §14 — 새 기능은 Model 타입부터).

public struct VideoRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "video"

    public enum Source: String, Codable, Sendable { case photos, folder }
    public enum Status: String, Codable, Sendable {
        /// 행은 생겼고 원본 사본을 받는 중 (iCloud "저장 공간 최적화" 면 오래 걸린다).
        case importing
        case ready
        case failed
    }

    public var id: String
    public var source: Source
    public var sourceRef: String
    public var localPath: String?
    public var durationSec: Double?
    public var width: Int?
    public var height: Int?
    public var capturedAt: Date?
    public var importedAt: Date
    public var status: Status
    public var error: String?

    public init(
        id: String = UUID().uuidString, source: Source, sourceRef: String, localPath: String? = nil,
        durationSec: Double? = nil, width: Int? = nil, height: Int? = nil,
        capturedAt: Date? = nil, importedAt: Date = Date(), status: Status = .importing, error: String? = nil
    ) {
        self.id = id; self.source = source; self.sourceRef = sourceRef; self.localPath = localPath
        self.durationSec = durationSec; self.width = width; self.height = height
        self.capturedAt = capturedAt; self.importedAt = importedAt; self.status = status; self.error = error
    }
}

public struct DigestRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "digest"
    public var videoId: String
    /// 다이제스트 형식 버전. 형식이 바뀌면 올리고, 옛 버전은 다시 만든다.
    public var version: Int
    /// 원본이 같은지 가르는 값. 같으면 다시 만들지 않는다 (§6).
    public var sourceFingerprint: String
    public var text: String
    public var sheetPaths: [String]
    public var transcript: Transcript
    public var subject: SubjectTrack
    public var createdAt: Date
}

/// 편집안. **직접 만들지 말고** `AppDatabase.saveComposition` 을 쓴다 — 검증을 거친다.
public struct CompositionRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "composition"
    public var id: String
    public var videoId: String
    public var json: String
    public var revisionOf: String?
    public var createdAt: Date

    public func composition() throws -> Composition { try parseComposition(Data(json.utf8)) }
}

public struct OutputRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "output"
    public var id: String
    public var compositionId: String
    public var path: String
    public var reviewReport: String?
    public var arch: String
    public var createdAt: Date
}

public struct JobRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "job"
    public enum Kind: String, Codable, Sendable { case analyze, render }
    public enum State: String, Codable, Sendable { case queued, running, done, failed }

    public var id: Int64?
    public var kind: Kind
    public var targetId: String
    public var state: State
    public var attempts: Int
    public var error: String?
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(kind: Kind, targetId: String, createdAt: Date = Date()) {
        self.kind = kind; self.targetId = targetId; self.state = .queued; self.attempts = 0
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct EventRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "event"
    public var id: Int64?
    public var kind: String
    public var subjectId: String?
    public var payload: String?
    public var arch: String
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - 쓰기

extension AppDatabase {

    /// 편집안 저장. **검증을 통과한 것만** 들어간다 (`parseComposition` 과 같은 검사).
    /// JSON 은 이 함수가 다시 직렬화한다 — 들어온 문자열을 그대로 믿지 않는다.
    @discardableResult
    public func saveComposition(_ comp: Composition, createdAt: Date = Date()) throws -> CompositionRecord {
        try validate(comp)
        try assertNoStyleValues(comp)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(comp), as: UTF8.self)
        let record = CompositionRecord(
            id: comp.id, videoId: comp.videoID, json: json, revisionOf: comp.revisionOf, createdAt: createdAt
        )
        try writer.write { db in try record.save(db) }
        return record
    }

    /// 사용 이벤트. 외부로 보내지 않는다 (§14).
    public func log(_ kind: String, subject: String? = nil, payload: [String: JSONValue]? = nil, at: Date = Date()) throws {
        let body = try payload.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        var event = EventRecord(kind: kind, subjectId: subject, payload: body, arch: MachineArch.current, createdAt: at)
        try writer.write { db in try event.insert(db) }
    }
}
