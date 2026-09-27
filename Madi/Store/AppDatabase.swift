import Foundation
import GRDB

/// 앱의 SQLite. **미디어 · 다이제스트 · 편집안 · 작업 · 결과물 · 이벤트** (AGENTS.md §2 · §14).
///
/// ★ 스키마는 마이그레이션으로만 바꾼다. 이미 배포된 마이그레이션은 고치지 않고 새 것을 더한다.
/// ★ 원칙 몇 개는 코드 약속이 아니라 **DB 가 막는다** — 트리거 · 외래 키 · CHECK.
///   리포지토리를 거치지 않는 경로(다음 사람이 짠 코드)에서도 깨지지 않게.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// `~/Library/Application Support/madi/madi.sqlite`
    public static func openDefault() throws -> AppDatabase {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try open(path: dir.appending(path: "madi.sqlite").path)
    }

    /// 파일 DB. 앱과 MCP 서버(`madi-mcp`, 다른 프로세스)가 같은 파일을 같은 설정으로 연다 — WAL 이라 동시에 열어도 된다.
    public static func open(path: String) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabasePool(path: path, configuration: config))
    }

    /// 테스트 · 스파이크용.
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1") { db in
            // 촬영본. 사진 앱(PhotoKit) 또는 폴더에서 들어온다 (§2 촬영본이 들어오는 길).
            try db.create(table: "video") { t in
                t.primaryKey("id", .text)
                t.column("source", .text).notNull().check(sql: "source IN ('photos','folder')")
                // PhotoKit localIdentifier 또는 파일 경로. 같은 영상을 두 번 들이지 않는다.
                t.column("sourceRef", .text).notNull().unique()
                // 앱이 가진 원본 사본. iCloud 원본을 다 받기 전에는 비어 있다.
                t.column("localPath", .text)
                t.column("durationSec", .double)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("capturedAt", .datetime)
                t.column("importedAt", .datetime).notNull()
                t.column("status", .text).notNull()
                    .check(sql: "status IN ('importing','ready','failed')")
                t.column("error", .text)
            }

            // §6 다이제스트. 원본이 바뀌지 않으면 다시 만들지 않는다 — sourceFingerprint 가 캐시 키.
            try db.create(table: "digest") { t in
                t.primaryKey("videoId", .text).references("video", onDelete: .cascade)
                t.column("version", .integer).notNull()
                t.column("sourceFingerprint", .text).notNull()
                t.column("text", .text).notNull()
                t.column("sheetPaths", .jsonText).notNull()
                // 뒤 단계가 다시 쓰는 원자료 — 자막 분절 · G6 는 낱말, 화면 잡기 · G1 은 피사체 트랙.
                t.column("transcript", .jsonText).notNull()
                t.column("subject", .jsonText).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // 편집안. Composition JSON 그대로 — 저장 전에 parseComposition 검증을 거친다.
            try db.create(table: "composition") { t in
                t.primaryKey("id", .text)
                t.column("videoId", .text).notNull().references("video", onDelete: .restrict)
                t.column("json", .jsonText).notNull()
                t.column("revisionOf", .text).references("composition", onDelete: .restrict)
                t.column("createdAt", .datetime).notNull()
            }

            // 결과물. 항상 편집안에서 재현 가능해야 한다 (§1-8) — 편집안 없이 존재할 수 없다.
            try db.create(table: "output") { t in
                t.primaryKey("id", .text)
                t.column("compositionId", .text).notNull().references("composition", onDelete: .restrict)
                t.column("path", .text).notNull()
                t.column("reviewReport", .jsonText)
                t.column("arch", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // ★ 결과물이 있는 편집안은 제자리에서 고치지 않는다 (§5 revisionOf).
            //   새 편집안을 만들고 revisionOf 에 이전 id 를 적는다.
            try db.execute(sql: """
                CREATE TRIGGER composition_frozen_after_output
                BEFORE UPDATE ON composition
                WHEN EXISTS (SELECT 1 FROM output WHERE compositionId = OLD.id)
                BEGIN
                    SELECT RAISE(ABORT, '결과물이 있는 편집안은 고칠 수 없다 — 새 편집안을 만들고 revisionOf 에 적는다');
                END
                """)

            // 작업 큐 (§2 Queue). 분석 1 · 렌더 1 동시.
            try db.create(table: "job") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull().check(sql: "kind IN ('analyze','render')")
                // analyze → video.id, render → composition.id
                t.column("targetId", .text).notNull()
                t.column("state", .text).notNull()
                    .check(sql: "state IN ('queued','running','done','failed')")
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            // 같은 대상에 같은 종류의 작업이 **살아 있는 채로** 둘 있으면 안 된다.
            try db.execute(sql: """
                CREATE UNIQUE INDEX job_one_live_per_target ON job(kind, targetId)
                WHERE state IN ('queued','running')
                """)

            // 사용 이벤트 (§14). 외부 전송 없음. 성능 판정은 arch 로 가른다 (§17).
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("subjectId", .text)
                t.column("payload", .jsonText)
                t.column("arch", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        return m
    }
}

/// 이 프로세스의 아키텍처. `events` · `output` 에 같이 남긴다 (§14 · §17).
///
/// 런타임에 읽는다 — `#if arch` 분기는 두 provider 에만 둔다 (§14).
/// Rosetta 로 돌면 x86_64 로 나온다. 그건 맞다 — 그 실행의 성능은 Tier 2 특성이다.
public enum MachineArch {
    public static let current: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()
}
