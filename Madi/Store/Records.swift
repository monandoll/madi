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

    /// 누가 만들었나. self-eval 횟수는 연속된 `selfEval` 조상으로 센다 (§7 최대 2회).
    public enum Origin: String, Codable, Sendable { case draft, selfEval, chat }

    public var id: String
    public var videoId: String
    public var json: String
    public var revisionOf: String?
    public var createdAt: Date
    public var origin: Origin

    public func composition() throws -> Composition { try parseComposition(Data(json.utf8)) }
}

public struct OutputRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "output"

    /// 보여 줄 수 있나 (§8 · §10 "검사한 결과만 보여 준다"). 갤러리는 `shown` 만 읽는다.
    public enum Verdict: String, Codable, Sendable {
        /// 하드 게이트 통과, 또는 `원본 한계` · `판정 불가`
        case shown
        /// 되먹임 중이거나, 뒤 판이 대신 보여진다
        case hidden
        /// 되먹임 2회 뒤에도 하드 실패 — 보여 주지 않고 채팅에 한 줄
        case failed
    }

    public var id: String
    public var compositionId: String
    public var path: String
    public var reviewReport: String?
    public var arch: String
    public var createdAt: Date
    public var verdict: Verdict = .shown
    public var seenAt: Date?
    public var trashedAt: Date?
}

public struct JobRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "job"
    /// analyze · agent → video.id, render · selfEval → composition.id, chat → chat.id
    public enum Kind: String, Codable, Sendable, CaseIterable { case analyze, render, agent, selfEval, chat }
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

/// 채팅 한 줄 (§10 · ViewData `ChatMessage`). 앱이 붙이는 줄은 문구 **키**만 들고 있다.
public struct ChatRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "chat"
    public enum Kind: String, Codable, Sendable {
        /// 크리에이터가 보낸 말
        case creator
        /// 보내지 못한 말 — 지우지 않는다 (ViewData `userNotSent`)
        case creatorNotSent
        /// AI 가 크리에이터에게 한 말 (되먹임 턴의 말은 들어오지 않는다, §10)
        case assistant
        /// 다음 행동 버튼. payload `{"ask": 키, …}`
        case choices
        /// 앱이 붙이는 한 줄. payload `{"key": 문구 키, "detail": …}`
        case notice
    }
    public var id: String
    public var videoId: String
    public var kind: Kind
    public var text: String?
    public var payload: String?
    public var compositionId: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, videoId: String, kind: Kind, text: String? = nil,
                payload: [String: JSONValue]? = nil, compositionId: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.videoId = videoId; self.kind = kind; self.text = text
        self.payload = payload.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) }
        self.compositionId = compositionId; self.createdAt = createdAt
    }

    public var payloadValues: [String: JSONValue] {
        payload.flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) } ?? [:]
    }
}

/// 내보낸 이력 한 줄.
public struct ExportRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "export"
    public enum Target: String, Codable, Sendable { case photos, folder }
    public var id: Int64?
    public var outputId: String
    public var target: Target
    public var location: String?
    public var createdAt: Date

    public init(outputId: String, target: Target, location: String?, createdAt: Date = Date()) {
        self.outputId = outputId; self.target = target; self.location = location; self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// 사용자 규칙 (§10 컨텍스트 4번 — 세기가 가장 세다).
public struct RuleRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "rule"
    public var id: Int64?
    public var text: String
    public var sourceChatId: String?
    public var createdAt: Date

    public init(text: String, sourceChatId: String?, createdAt: Date = Date()) {
        self.text = text; self.sourceChatId = sourceChatId; self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - 쓰기

extension AppDatabase {

    /// 편집안 저장. **검증을 통과한 것만** 들어간다 (`parseComposition` 과 같은 검사).
    /// JSON 은 이 함수가 다시 직렬화한다 — 들어온 문자열을 그대로 믿지 않는다.
    @discardableResult
    public func saveComposition(
        _ comp: Composition, createdAt: Date = Date(), origin: CompositionRecord.Origin = .draft
    ) throws -> CompositionRecord {
        try validate(comp)
        try assertNoStyleValues(comp)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(comp), as: UTF8.self)
        let record = CompositionRecord(
            id: comp.id, videoId: comp.videoID, json: json, revisionOf: comp.revisionOf, createdAt: createdAt,
            origin: origin
        )
        try writer.write { db in try record.save(db) }
        return record
    }

    /// 사용자 규칙 — 프롬프트 4번 칸에 들어간다.
    public func userRules() throws -> [String] {
        try writer.read { try RuleRecord.order(Column("createdAt")).fetchAll($0).map(\.text) }
    }

    /// 사용 이벤트. 외부로 보내지 않는다 (§14).
    public func log(_ kind: String, subject: String? = nil, payload: [String: JSONValue]? = nil, at: Date = Date()) throws {
        let body = try payload.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        var event = EventRecord(kind: kind, subjectId: subject, payload: body, arch: MachineArch.current, createdAt: at)
        try writer.write { db in try event.insert(db) }
    }
}
