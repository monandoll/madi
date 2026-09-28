import Foundation
import GRDB
import os

/// 분석이 끝난 영상에 AI 한 턴을 걸어 **편집안 초안**을 만든다 (AGENTS.md §10 첫 진입, docs/stage-4.spec.md 5번).
///
/// ```
/// 다이제스트 → [agent 작업] → AI 고르기 → 한 턴 (madi-mcp 로 read_digest · write_composition) → 초안
/// ```
/// - 초안이 저장되면 `onDraft` 로 렌더를 건다 — 검사한 결과만 보여 준다 (5단계 결정 ①, §10)
/// - AI 가 연결돼 있지 않으면 **스폰하지 않는다** (§10). 이벤트만 남기고 끝낸다 — 실패가 아니다
/// - 턴이 끝났는데 초안이 저장되지 않았으면 실패다. 조용히 넘어가지 않는다 (§2-4)
/// - 요청 종류 · 걸린 시간 · CLI · 판 · 모델을 `events` 에 남긴다 (§14, 결정 ②)
public struct AgentJob: Sendable {
    static let log = Logger(subsystem: "app.madi", category: "agent")

    /// 고른 AI. `executable` 은 CLI 실행 파일.
    public struct Choice: Sendable, Equatable {
        public var kind: AgentKind
        public var executable: URL
        public var version: String?
        public init(kind: AgentKind, executable: URL, version: String?) {
            self.kind = kind; self.executable = executable; self.version = version
        }
    }

    public typealias Turn = @Sendable (Choice, AgentRequest) -> AsyncThrowingStream<AgentEvent, Error>

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    let db: AppDatabase
    let mcpExecutable: URL
    let choose: @Sendable () async -> Choice?
    let userRules: @Sendable () -> [String]
    let workRoot: URL
    let turn: Turn
    let makeCompositionID: @Sendable (String) -> String
    let onDraft: @Sendable (String) async throws -> Void

    public init(
        db: AppDatabase,
        mcpExecutable: URL,
        choose: @escaping @Sendable () async -> Choice? = { await AgentJob.defaultChoice() },
        userRules: @escaping @Sendable () -> [String] = { [] },
        workRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/agent", directoryHint: .isDirectory),
        turn: @escaping Turn = { choice, request in
            AgentRunner(executable: choice.executable, provider: AgentProviders.provider(choice.kind)).run(request)
        },
        makeCompositionID: @escaping @Sendable (String) -> String = { "draft_\($0)_\(UUID().uuidString.prefix(8))" },
        onDraft: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.db = db; self.mcpExecutable = mcpExecutable; self.choose = choose; self.userRules = userRules
        self.workRoot = workRoot; self.turn = turn; self.makeCompositionID = makeCompositionID
        self.onDraft = onDraft
    }

    public var handler: JobQueue.Handler {
        { job in try await self.run(videoID: job.targetId) }
    }

    /// 사용자 설정(`madi.agent` = claude | codex)이 있으면 그것. 없으면 연결된 쪽 — 둘 다면 Claude
    /// (2026-09-27 결정. Claude 가 더 빨랐고 도구 목록을 코드로 검사할 수 있다). 설정한 쪽이 연결 안 됐으면 다른 쪽을 보지 않는다 —
    /// 사람이 고른 것을 몰래 바꾸지 않는다.
    /// 설정 `madi.agent` 가 `none` 이면 AI 를 쓰지 않는다 — 설정의 "연결 끊기" (CLI 로그아웃은 하지 않는다).
    public static let disabledValue = "none"

    public static func defaultChoice(
        preferred: AgentKind? = UserDefaults.standard.string(forKey: "madi.agent").flatMap(AgentKind.init(rawValue:)),
        disabled: Bool = UserDefaults.standard.string(forKey: "madi.agent") == AgentJob.disabledValue,
        connection: @Sendable (AgentKind) async -> AgentConnection = { await CLILocator.connection($0) }
    ) async -> Choice? {
        if disabled { return nil }
        for kind in preferred.map({ [$0] }) ?? [.claude, .codex] {
            if case .ready(let exe, let version) = await connection(kind) {
                return Choice(kind: kind, executable: exe, version: version)
            }
        }
        return nil
    }

    func run(videoID: String) async throws {
        guard let choice = await choose() else {
            try? db.log("agent.notConnected", subject: videoID)
            Self.log.notice("AI 가 연결돼 있지 않아 초안을 만들지 않는다: \(videoID, privacy: .public)")
            return
        }
        let compositionID = makeCompositionID(videoID)
        let workDir = workRoot.appending(path: compositionID, directoryHint: .isDirectory)
        let request = AgentRequest(
            prompt: try PromptAssembler.assemble(videoID: videoID, userRules: userRules()),
            mcp: .madi(executable: mcpExecutable, videoID: videoID, compositionID: compositionID,
                       dbPath: db.filePath),
            workDir: workDir
        )
        try await turnAndCheck(choice, request, videoID: videoID, compositionID: compositionID, kind: "firstDraft")
    }

    /// 되먹임 턴 (§7-6 · docs/stage-5.spec.md 4번). **사용자에게 보이지 않는다** (§10).
    ///
    /// 렌더된 편집안의 리포트에서 되먹임 항목을 읽어, 수치와 지난 편집안을 요청 칸(§10 6번)에 넣고,
    /// 지난 결과물(내보낸 파일)의 프레임 시트를 `read_digest` 로 보여 준다. AI 는 새 편집안을 쓴다 —
    /// 결과물이 있는 편집안은 고칠 수 없다 (`revisionOf`, §5).
    func selfEval(compositionID previous: String) async throws {
        let (record, output) = try await db.writer.read { db in
            (try CompositionRecord.fetchOne(db, key: previous),
             try OutputRecord.filter(Column("compositionId") == previous).fetchOne(db))
        }
        guard let record, let output else { throw Failure(description: "되먹임할 편집안 · 결과물이 없다: \(previous)") }
        guard let choice = await choose() else {
            try? db.log("agent.notConnected", subject: record.videoId)
            return
        }
        let report = (try? JSONDecoder().decode([String: JSONValue].self, from: Data((output.reviewReport ?? "{}").utf8))) ?? [:]
        let compositionID = makeCompositionID(record.videoId)
        let workDir = workRoot.appending(path: compositionID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        // self-eval 프레임은 반드시 내보낸 파일에서 (§7). 원본에서 뽑으면 자막이 없다.
        let sheet = workDir.appending(path: "last-output.png")
        _ = try await FrameSheet.grid(from: URL(fileURLWithPath: output.path), at: [], columns: 5, to: sheet)

        let request = AgentRequest(
            prompt: try PromptAssembler.assemble(
                videoID: record.videoId, userRules: userRules(),
                request: SelfEvalRequest.text(report: report, previous: try record.composition())
            ),
            mcp: .madi(executable: mcpExecutable, videoID: record.videoId, compositionID: compositionID,
                       revisionOf: previous, origin: .selfEval, feedbackSheet: sheet, dbPath: db.filePath),
            workDir: workDir
        )
        try await turnAndCheck(choice, request, videoID: record.videoId, compositionID: compositionID, kind: "selfEval")
    }

    public var selfEvalHandler: JobQueue.Handler {
        { job in try await self.selfEval(compositionID: job.targetId) }
    }

    /// 한 턴을 돌리고 편집안이 실제로 저장됐는지 확인한다. 첫 초안 · 되먹임 · 채팅 수정이 같이 쓴다.
    /// AI 가 크리에이터에게 한 마지막 말을 돌려준다.
    @discardableResult
    func turnAndCheck(
        _ choice: Choice, _ request: AgentRequest, videoID: String, compositionID: String, kind: String,
        answerOnly: Bool = false
    ) async throws -> String {
        let workDir = request.workDir
        let base: [String: JSONValue] = [
            "request": .string(kind), "cli": .string(choice.kind.rawValue),
            "version": .string(choice.version ?? ""), "composition": .string(compositionID),
        ]
        try? db.log("agent.turn.started", subject: videoID, payload: base)

        let started = Date()
        var outcome: AgentOutcome?
        var said: [String] = []
        for try await event in turn(choice, request) {
            switch event {
            case .text(let t): said.append(t)
            case .warning(let w): try? db.log("agent.warning", subject: videoID, payload: base.merging(["message": .string(w)]) { $1 })
            case .finished(let o): outcome = o
            case .started, .toolCall: break
            }
        }

        let saved = (try? await db.writer.read { try CompositionRecord.fetchOne($0, key: compositionID) }) != nil
        var payload = base
        payload["seconds"] = .number(Date().timeIntervalSince(started))
        payload["model"] = .string(outcome?.model ?? "")
        payload["ok"] = .bool(saved && outcome?.isError == false)
        // AI 가 크리에이터에게 한 말. 채팅 저장소는 6단계다 — 그전까지는 이벤트에 남긴다.
        // 되먹임 턴의 말은 크리에이터에게 보이지 않는다 (§10).
        payload["said"] = .string(said.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if let message = outcome?.message, outcome?.isError == true { payload["error"] = .string(message) }
        try? db.log("agent.turn.finished", subject: videoID, payload: payload)

        // 채팅 질문: 편집안 없이 답만 했으면 그 답을 돌려준다 (answerOnly).
        let answered = answerOnly && !saved && outcome?.isError == false
            && !(said.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if answered {
            try? FileManager.default.removeItem(at: workDir)
            return said.last!.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard saved, outcome?.isError == false else {
            // 실패 원인을 보려고 작업 폴더는 남긴다 (§7 중간 산출물 규칙과 같다).
            throw Failure(description: outcome?.isError == true
                ? "AI 턴 실패: \(outcome?.message ?? "이유 없음")"
                : saved ? "AI 턴이 끝을 알리지 않았다" : "AI 턴이 끝났지만 편집안이 저장되지 않았다")
        }
        try? db.log("agent.draft.ready", subject: compositionID, payload: ["video": .string(videoID), "request": .string(kind)])
        try? FileManager.default.removeItem(at: workDir)
        // 검사한 결과만 보여 준다 — 초안이든 되먹임이든 저장되면 바로 렌더에 건다 (5단계 결정 ①).
        try await onDraft(compositionID)
        return said.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
