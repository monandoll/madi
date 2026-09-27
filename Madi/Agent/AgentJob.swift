import Foundation
import GRDB
import os

/// 분석이 끝난 영상에 AI 한 턴을 걸어 **편집안 초안**을 만든다 (AGENTS.md §10 첫 진입, docs/stage-4.spec.md 5번).
///
/// ```
/// 다이제스트 → [agent 작업] → AI 고르기 → 한 턴 (madi-mcp 로 read_digest · write_composition) → 초안
/// ```
/// - **자동 렌더하지 않는다** (§10 · 결정 ③). 초안까지다. 렌더는 사용자가 고른다 (화면은 6단계)
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
        makeCompositionID: @escaping @Sendable (String) -> String = { "draft_\($0)_\(UUID().uuidString.prefix(8))" }
    ) {
        self.db = db; self.mcpExecutable = mcpExecutable; self.choose = choose; self.userRules = userRules
        self.workRoot = workRoot; self.turn = turn; self.makeCompositionID = makeCompositionID
    }

    public var handler: JobQueue.Handler {
        { job in try await self.run(videoID: job.targetId) }
    }

    /// 사용자 설정(`madi.agent` = claude | codex)이 있으면 그것. 없으면 연결된 쪽 — 둘 다면 Claude
    /// (2026-09-27 결정. Claude 가 더 빨랐고 도구 목록을 코드로 검사할 수 있다). 설정한 쪽이 연결 안 됐으면 다른 쪽을 보지 않는다 —
    /// 사람이 고른 것을 몰래 바꾸지 않는다.
    public static func defaultChoice(
        preferred: AgentKind? = UserDefaults.standard.string(forKey: "madi.agent").flatMap(AgentKind.init(rawValue:)),
        connection: @Sendable (AgentKind) async -> AgentConnection = { await CLILocator.connection($0) }
    ) async -> Choice? {
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
        let base: [String: JSONValue] = [
            "request": .string("firstDraft"), "cli": .string(choice.kind.rawValue),
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
        payload["said"] = .string(said.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if let message = outcome?.message, outcome?.isError == true { payload["error"] = .string(message) }
        try? db.log("agent.turn.finished", subject: videoID, payload: payload)

        guard saved, outcome?.isError == false else {
            // 실패 원인을 보려고 작업 폴더는 남긴다 (§7 중간 산출물 규칙과 같다).
            throw Failure(description: outcome?.isError == true
                ? "AI 턴 실패: \(outcome?.message ?? "이유 없음")"
                : saved ? "AI 턴이 끝을 알리지 않았다" : "AI 턴이 끝났지만 편집안이 저장되지 않았다")
        }
        try? db.log("agent.draft.ready", subject: compositionID, payload: ["video": .string(videoID)])
        try? FileManager.default.removeItem(at: workDir)
    }
}
