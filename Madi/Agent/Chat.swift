import Foundation
import GRDB

/// 채팅 수정 (AGENTS.md §10, docs/stage-6.spec.md 5번).
///
/// ```
/// 크리에이터 말 → chat 줄 + [chat 작업] → AI 수정 턴 (대화 이력 · 보고 있는 편집안)
///   → 새 편집안 (origin chat · revisionOf) → [렌더] → 검사 → (되먹임) → 보여 준다
///   → AI 가 한 말 · "앞으로도 이렇게 할까요?" 선택지
/// 예 → 크리에이터가 한 말을 사용자 규칙으로 (프롬프트 4번 칸)
/// ```
/// - 수정은 **항상 새 편집안**이다 (§10). 결과물이 있는 편집안은 DB 가 고치지 못하게 막는다 (§5)
/// - 앱이 붙이는 줄(선택지 · 알림)은 문구 키만 저장한다. 문장은 `Copy.swift`(디자인 소유) 한 곳이다
public enum Chat {

    /// 선택지 · 알림 문구 키. `docs/design/copy-keys.md` 에 넘긴 것과 같아야 한다.
    public enum Key {
        /// "앞으로도 이렇게 할까요?" (§10)
        public static let askRemember = "askRemember"
        public static let rememberYes = "rememberYes"
        public static let rememberNo = "rememberNo"
        /// 수정 턴이 실패했다 (한도 · 로그인 만료 · 시간 초과)
        public static let aiDraftFailed = "aiDraftFailed"
    }

    /// 크리에이터가 말을 보낸다. 줄을 남기고 수정 작업을 건다. 걸지 못하면 `creatorNotSent` 로 남긴다 — 쓴 말을 지우지 않는다.
    @discardableResult
    public static func send(
        db: AppDatabase, videoID: String, text: String, viewing compositionID: String?,
        enqueue: @Sendable (String) async throws -> Void
    ) async throws -> ChatRecord {
        var row = ChatRecord(videoId: videoID, kind: .creator, text: text,
                             payload: compositionID.map { ["viewing": .string($0)] })
        try await db.writer.write { [row] in try row.insert($0) }
        do {
            try await enqueue(row.id)
        } catch {
            row.kind = .creatorNotSent
            try await db.writer.write { [row] in try row.update($0) }
            throw error
        }
        try? db.log("chat.sent", subject: videoID)
        return row
    }

    /// "앞으로도 이렇게 할까요?" 에 답한다. 예일 때만 사용자 규칙에 적는다 (§10).
    public static func answerRemember(db: AppDatabase, choicesID: String, yes: Bool) async throws {
        guard let row = try await db.writer.read({ try ChatRecord.fetchOne($0, key: choicesID) }),
              case .string(let ruleText)? = row.payloadValues["rule"] else { return }
        try await db.writer.write { db in
            var values = row.payloadValues
            values["answered"] = .bool(yes)
            var answered = row
            answered.payload = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
            try answered.update(db)
            if yes {
                var rule = RuleRecord(text: ruleText, sourceChatId: row.id)
                try rule.insert(db)
            }
        }
        try? db.log(yes ? "rule.added" : "rule.declined", subject: row.videoId)
    }

    /// AI 에게 줄 대화 이력 (크리에이터 · AI 말만. 선택지 · 알림 · 보내지 못한 말은 빼고).
    static func history(_ rows: [ChatRecord], before id: String) -> [PromptAssembler.Turn] {
        var out: [PromptAssembler.Turn] = []
        for r in rows {
            if r.id == id { break }
            switch r.kind {
            case .creator: if let t = r.text { out.append(.init(.creator, t)) }
            case .assistant: if let t = r.text { out.append(.init(.assistant, t)) }
            default: break
            }
        }
        return out
    }

    /// 수정 턴의 요청 칸 (§10 6번). 크리에이터 말 + 보고 있는 편집안.
    static func request(text: String, current: Composition) -> String {
        [
            "크리에이터: \(text)",
            "",
            "(앱이 붙임) 크리에이터가 지금 보고 있는 편집안이다. 위 요청대로 고친 편집안을 `write_composition` 으로 **새로** 보낸다.",
            "요청과 상관없는 장면은 그대로 둔다. 영문(`secondary`)도 쓴 문장마다 다시 보낸다.",
            "저장되면 크리에이터에게 무엇을 바꿨는지 한두 문장으로 말한다 — 편집 용어 없이.",
            "",
            "```json",
            SelfEvalRequest.previousJSON(current),
            "```",
        ].joined(separator: "\n")
    }
}

extension AgentJob {

    /// 채팅 수정 턴. `targetId` 는 크리에이터 말(`chat.id`).
    func chat(messageID: String) async throws {
        guard let message = try await db.writer.read({ try ChatRecord.fetchOne($0, key: messageID) }),
              let text = message.text else { throw Failure(description: "채팅 줄이 없다: \(messageID)") }
        let videoID = message.videoId
        // 보고 있던 편집안. 없으면 이 영상의 가장 최근 사람이 본 판(초안 · 채팅).
        let viewing: String? = { if case .string(let s)? = message.payloadValues["viewing"] { s } else { nil } }()
        let (current, rows) = try await db.writer.read { db -> (CompositionRecord?, [ChatRecord]) in
            let cur = try viewing.flatMap { try CompositionRecord.fetchOne(db, key: $0) }
                ?? CompositionRecord.filter(Column("videoId") == videoID && Column("origin") != "selfEval")
                    .order(Column("createdAt").desc).fetchOne(db)
            let rows = try ChatRecord.filter(Column("videoId") == videoID).order(Column("createdAt")).fetchAll(db)
            return (cur, rows)
        }
        guard let current else { throw Failure(description: "고칠 편집안이 없다: \(videoID)") }
        guard let choice = await choose() else {
            try? db.log("agent.notConnected", subject: videoID)
            return
        }
        let compositionID = makeCompositionID(videoID)
        let request = AgentRequest(
            prompt: try PromptAssembler.assemble(
                videoID: videoID, userRules: userRules(),
                history: Chat.history(rows, before: messageID),
                request: Chat.request(text: text, current: try current.composition())
            ),
            mcp: .madi(executable: mcpExecutable, videoID: videoID, compositionID: compositionID,
                       revisionOf: current.id, origin: .chat, dbPath: db.filePath),
            workDir: workRoot.appending(path: compositionID, directoryHint: .isDirectory)
        )
        do {
            let said = try await turnAndCheck(choice, request, videoID: videoID, compositionID: compositionID, kind: "chat")
            try await db.writer.write { db in
                try ChatRecord(videoId: videoID, kind: .assistant, text: said, compositionId: compositionID).insert(db)
                // §10 — 고친 뒤 한 번 묻는다. 예일 때만 규칙에 적는다.
                try ChatRecord(videoId: videoID, kind: .choices,
                               payload: ["ask": .string(Chat.Key.askRemember), "rule": .string(text)]).insert(db)
            }
        } catch {
            try? await db.writer.write { db in
                try ChatRecord(videoId: videoID, kind: .notice,
                               payload: ["key": .string(Chat.Key.aiDraftFailed), "detail": .string("\(error)")]).insert(db)
            }
            throw error
        }
    }

    public var chatHandler: JobQueue.Handler {
        { job in try await self.chat(messageID: job.targetId) }
    }
}
