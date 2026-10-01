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

    /// 아직 AI 가 답하지 않은 크리에이터 말 — 마지막 AI 말 · 알림 **뒤에** 온 것 (한 영상의 줄, 시간 순).
    /// 보내지 못한 말(`creatorNotSent`)은 세지 않는다 — 다시 보내기를 눌러야 요청이다.
    public static func pendingRequest(_ rows: [ChatRecord]) -> [ChatRecord] {
        var pending: [ChatRecord] = []
        for r in rows {
            switch r.kind {
            case .creator: pending.append(r)
            case .assistant, .notice: pending.removeAll()
            default: break
            }
        }
        return pending
    }

    /// **첫 요청** — 편집안이 아직 없을 때 크리에이터가 한 말. 줄을 남기고 초안을 건다: 분석이 끝났으면 AI 초안,
    /// 아니면 분석부터 (끝나면 파이프라인이 이 줄을 보고 초안을 건다). AI 는 이 말이 있어야 시작한다 (2026-10-01 결정).
    @discardableResult
    public static func sendFirstRequest(
        db: AppDatabase, videoID: String, text: String,
        enqueue: @Sendable (JobRecord.Kind, String) async throws -> Void
    ) async throws -> ChatRecord {
        var row = ChatRecord(videoId: videoID, kind: .creator, text: text)
        try await db.writer.write { [row] in try row.insert($0) }
        do {
            let (ready, hasDigest) = try await db.writer.read { db in
                (try VideoRecord.fetchOne(db, key: videoID)?.status == .ready, try DigestRecord.fetchOne(db, key: videoID) != nil)
            }
            // 원본을 아직 받는 중이면(사진 보관함에 있던 영상) 여기서 걸지 않는다 — 다 받으면 가져오기가 분석을 걸고,
            // 분석이 끝나면 파이프라인이 이 말을 보고 초안을 건다
            if ready { try await enqueue(hasDigest ? .agent : .analyze, videoID) }
        } catch {
            row.kind = .creatorNotSent
            try await db.writer.write { [row] in try row.update($0) }
            throw error
        }
        try? db.log("chat.sent", subject: videoID, payload: ["first": .bool(true)])
        return row
    }

    /// 첫 초안 턴의 요청 칸 (§10 6번) — 크리에이터가 한 말 그대로 + 앱이 붙이는 말.
    static func firstRequest(text: String) -> String {
        [
            text,
            "",
            "(앱이 붙임) 아직 편집안이 없다. 이 영상으로 **편집안 초안**을 `write_composition` 으로 보낸다.",
            "크리에이터가 말한 것(어느 부분 · 길이 · 무엇을 보여 줄지)을 따르고, 말하지 않은 것은 제작 지침대로 한다. \"알아서\" 라고 하면 전부 제작 지침대로.",
            "저장되면 무엇을 만들었는지 한두 문장으로 말한다 — 편집 용어 없이.",
            "**질문이면**(무슨 영상인지 등) 편집안을 보내지 않고 답만 한다. 새 영상이 만들어지지 않는다.",
            "답은 **세 문장 이내의 평범한 말**로 쓴다. 마크다운(`**` · `-` 목록 · `#` 제목)을 쓰지 않는다 — 채팅 말풍선에 기호가 그대로 보인다.",
        ].joined(separator: "\n")
    }

    /// "앞으로도 이렇게 할까요?" 에 답한다. 예일 때만 사용자 규칙에 적는다 (§10).
    /// 규칙 문장은 크리에이터 말 그대로가 아니라 **AI 가 다듬은 일반 문장**이다 (6단계 결정 ③).
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
            text,   // "크리에이터: " 는 프롬프트 조립이 붙인다 (전에는 두 번 들어갔다)
            "",
            "(앱이 붙임) 크리에이터가 지금 보고 있는 편집안이다.",
            "**고쳐 달라는 요청이면** 고친 편집안을 `write_composition` 으로 **새로** 보낸다. 요청과 상관없는 장면은 그대로 둔다. 영문(`secondary`)도 쓴 문장마다 다시 보낸다.",
            "저장되면 크리에이터에게 무엇을 바꿨는지 한두 문장으로 말한다 — 편집 용어 없이. 첫 문장에 바꾼 것을 쓴다 (결과물 화면에 그대로 뜬다).",
            "**질문이면**(무슨 영상인지 · 왜 그렇게 했는지 등) 편집안을 보내지 않고 답만 한다. 새 영상이 만들어지지 않는다.",
            "답은 **세 문장 이내의 평범한 말**로 쓴다. 마크다운(`**` · `-` 목록 · `#` 제목)을 쓰지 않는다 — 채팅 말풍선에 기호가 그대로 보인다.",
            "이 요청이 다음 영상에도 통할 **일반 규칙**이면 `rule` 에 한 문장으로 적는다 (예: \"영상은 15초 안팎으로\"). 이 영상에만 해당하면 비운다 — 그러면 크리에이터에게 묻지 않는다.",
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
            // 질문에는 편집안 없이 답만 한다 — 새 판 · 새 영상을 만들지 않는다.
            let said = try await turnAndCheck(choice, request, videoID: videoID, compositionID: compositionID,
                                              kind: "chat", answerOnly: true)
            let wrote = try await db.writer.read { try CompositionRecord.fetchOne($0, key: compositionID) } != nil
            try await db.writer.write { db in
                try ChatRecord(videoId: videoID, kind: .assistant, text: said,
                               compositionId: wrote ? compositionID : nil).insert(db)
                guard wrote else { return }
                // §10 — 고친 뒤 한 번 묻는다. 묻는 문장은 AI 가 다듬은 일반 규칙이고, 일반화할 게 없으면 묻지 않는다 (결정 ③).
                let proposed = try EventRecord
                    .filter(Column("kind") == "agent.rule.proposed" && Column("subjectId") == compositionID)
                    .order(Column("id").desc).fetchOne(db)
                    .flatMap { $0.payload }
                    .flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
                if case .string(let rule)? = proposed?["rule"], !rule.isEmpty {
                    try ChatRecord(videoId: videoID, kind: .choices,
                                   payload: ["ask": .string(Chat.Key.askRemember), "rule": .string(rule),
                                             "request": .string(text)]).insert(db)
                }
            }
        } catch {
            chatFailed(message, error: error)
            throw error
        }
    }

    /// 수정 턴이 막혔다 — 알림 줄을 남기고, 크리에이터 말은 "보내지 못함" 으로 바꾼다. 말풍선 밑에 "다시 보내기" 가 붙는다.
    /// 알림은 "쓰신 말은 그대로 있으니 다시 보내 주세요" 라고 하는데, 전에는 누를 곳이 없어 같은 말을 다시 써야 했다 (2026-09-30).
    /// 보내지 못한 말은 AI 대화 이력에서도 빠진다 (`history`).
    ///
    /// **동기 쓰기** (async 가 아닌 함수라 동기 쓰기가 골라진다) — 멈추기(■)로 끊긴 작업 안에서 비동기 쓰기는 GRDB 가
    /// CancellationError 로 거절해, 알림도 못 남기고 말풍선이 그대로였다 (눌러서 찾음).
    func chatFailed(_ message: ChatRecord, error: Error) {
        try? db.writer.write { db in
            try ChatRecord(videoId: message.videoId, kind: .notice,
                           payload: ["key": .string(Chat.Key.aiDraftFailed), "detail": .string("\(error)")]).insert(db)
            var sent = message
            sent.kind = .creatorNotSent
            try sent.update(db)
        }
    }

    public var chatHandler: JobQueue.Handler {
        { job in try await self.chat(messageID: job.targetId) }
    }
}
