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

    /// 파일 DB 의 경로. 메모리 DB 면 nil. `madi-mcp`(다른 프로세스)에게 같은 파일을 열게 할 때 쓴다.
    public var filePath: String? {
        let p = writer.path
        return p.isEmpty || p == ":memory:" || p.hasPrefix("file::memory:") ? nil : p
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
        // 4단계 — AI 한 턴도 큐 작업이다 (docs/stage-4.spec.md 5번). SQLite 는 CHECK 를 고칠 수 없어 표를 다시 만든다.
        m.registerMigration("v2-agent-job") { db in
            try db.create(table: "job_new") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull().check(sql: "kind IN ('analyze','render','agent')")
                // analyze · agent → video.id, render → composition.id
                t.column("targetId", .text).notNull()
                t.column("state", .text).notNull()
                    .check(sql: "state IN ('queued','running','done','failed')")
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            try db.execute(sql: "INSERT INTO job_new SELECT id, kind, targetId, state, attempts, error, createdAt, startedAt, finishedAt FROM job")
            try db.drop(table: "job")
            try db.rename(table: "job_new", to: "job")
            try db.execute(sql: """
                CREATE UNIQUE INDEX job_one_live_per_target ON job(kind, targetId)
                WHERE state IN ('queued','running')
                """)
        }
        // 5단계 — self-eval 루프 (docs/stage-5.spec.md 3번).
        // - composition.origin: 누가 만들었나. self-eval 횟수(최대 2, §7)는 연속된 selfEval 조상으로 센다 —
        //   6단계 채팅 수정(chat)과 섞이지 않게
        // - output.verdict: 보여 줄 수 있나 (§8 · §10 "검사한 결과만 보여 준다"). 기존 결과물은 보여 준 것으로 본다
        // - job.kind: selfEval (targetId → composition.id). CHECK 를 못 고쳐 표를 다시 만든다
        m.registerMigration("v3-self-eval") { db in
            try db.alter(table: "composition") { t in
                t.add(column: "origin", .text).notNull().defaults(to: "draft")
                    .check(sql: "origin IN ('draft','selfEval','chat')")
            }
            try db.alter(table: "output") { t in
                t.add(column: "verdict", .text).notNull().defaults(to: "shown")
                    .check(sql: "verdict IN ('shown','hidden','failed')")
            }
            try db.create(table: "job_new") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull().check(sql: "kind IN ('analyze','render','agent','selfEval')")
                // analyze · agent → video.id, render · selfEval → composition.id
                t.column("targetId", .text).notNull()
                t.column("state", .text).notNull()
                    .check(sql: "state IN ('queued','running','done','failed')")
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            try db.execute(sql: "INSERT INTO job_new SELECT id, kind, targetId, state, attempts, error, createdAt, startedAt, finishedAt FROM job")
            try db.drop(table: "job")
            try db.rename(table: "job_new", to: "job")
            try db.execute(sql: """
                CREATE UNIQUE INDEX job_one_live_per_target ON job(kind, targetId)
                WHERE state IN ('queued','running')
                """)
        }
        // 6단계 — 채팅 수정 (docs/stage-6.spec.md 5번, AGENTS.md §10).
        // - chat: 영상별 대화. 사람이 읽는 문장은 AI 가 한 말과 크리에이터가 쓴 말뿐이다.
        //   앱이 붙이는 줄(선택지 · 알림)은 **문구 키**만 저장한다 — 문장은 Copy.swift(디자인 소유) 한 곳에 있다
        // - rule: 사용자 규칙 (§10 컨텍스트 4번). "앞으로도 이렇게 할까요?" 에 예일 때만 적는다
        // - job.kind: chat (targetId → chat.id)
        m.registerMigration("v4-chat") { db in
            try db.create(table: "chat") { t in
                t.primaryKey("id", .text)
                t.column("videoId", .text).notNull().references("video", onDelete: .cascade)
                t.column("kind", .text).notNull()
                    .check(sql: "kind IN ('creator','creatorNotSent','assistant','choices','notice')")
                t.column("text", .text)
                // choices · notice 의 문구 키와 값. creator 줄은 보고 있던 편집안.
                t.column("payload", .jsonText)
                // 이 줄로 생긴 편집안 (assistant 줄)
                t.column("compositionId", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "chat_by_video", on: "chat", columns: ["videoId", "createdAt"])
            try db.create(table: "rule") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("sourceChatId", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "job_new") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull().check(sql: "kind IN ('analyze','render','agent','selfEval','chat')")
                // analyze · agent → video.id, render · selfEval → composition.id, chat → chat.id
                t.column("targetId", .text).notNull()
                t.column("state", .text).notNull()
                    .check(sql: "state IN ('queued','running','done','failed')")
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            try db.execute(sql: "INSERT INTO job_new SELECT id, kind, targetId, state, attempts, error, createdAt, startedAt, finishedAt FROM job")
            try db.drop(table: "job")
            try db.rename(table: "job_new", to: "job")
            try db.execute(sql: """
                CREATE UNIQUE INDEX job_one_live_per_target ON job(kind, targetId)
                WHERE state IN ('queued','running')
                """)
        }
        // 6단계 7번 — 결과물을 쓰는 일 (docs/stage-6.spec.md).
        // - output.seenAt: 사람이 봤나 (ViewData ResultRef.isNew)
        // - output.trashedAt: 휴지통으로 옮겼나. 행은 지우지 않는다 — 편집안이 결과물이 있는 채로 남아야 제자리 수정이 막힌다 (§5)
        // - export: 내보낸 이력 (목록 줄 "사진 앱에 저장함 · 오후 2:40" — 올렸는지 헷갈리지 않게)
        m.registerMigration("v5-export") { db in
            try db.alter(table: "output") { t in
                t.add(column: "seenAt", .datetime)
                t.add(column: "trashedAt", .datetime)
            }
            try db.create(table: "export") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("outputId", .text).notNull().references("output", onDelete: .cascade)
                t.column("target", .text).notNull().check(sql: "target IN ('photos','folder')")
                // 사진 앱 localIdentifier 또는 저장한 파일 경로
                t.column("location", .text)
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
