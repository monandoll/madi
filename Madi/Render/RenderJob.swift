import Foundation
import GRDB

/// 큐의 **렌더** 작업 — 편집안 하나를 내보내고 게이트 리포트를 붙인다 (AGENTS.md §7 · §8).
///
/// ```
/// 편집안 → (auto 장면) 다이제스트 피사체 트랙으로 키프레임 채워 편집안에 되쓰기(§7-1)
///        → 원본 사본 · 기록된 스타일 버전 → 내보내기 → G1~G6 리포트 → 결과물 행
/// ```
/// - 키프레임은 **렌더 전에** 되쓴다. 결과물이 생긴 편집안은 고칠 수 없다(DB 트리거)
/// - 같은 편집안의 결과물이 이미 있으면 다시 그리지 않는다
/// - self-eval(하드 게이트 실패 → 되돌리기)은 5단계다. 여기서는 기록만 한다
public struct RenderJob: Sendable {
    public let db: AppDatabase
    public let outputs: URL

    public init(db: AppDatabase, outputs: URL = RenderJob.defaultOutputs) {
        self.db = db; self.outputs = outputs
    }

    public static var defaultOutputs: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/outputs", directoryHint: .isDirectory)
    }

    public enum Failure: Error, CustomStringConvertible {
        case noComposition(String), sourceNotReady(String), noDigest(String)
        public var description: String {
            switch self {
            case .noComposition(let id): "편집안 \(id) 이 저장소에 없다"
            case .sourceNotReady(let id): "영상 \(id) 의 원본 사본이 없다"
            case .noDigest(let id): "영상 \(id) 의 다이제스트가 없다 — 화면 잡기에 피사체 트랙이 필요하다"
            }
        }
    }

    public var handler: JobQueue.Handler {
        { job in _ = try await run(compositionId: job.targetId) }
    }

    @discardableResult
    public func run(compositionId: String) async throws -> OutputRecord {
        if let existing = try await db.writer.read({
            try OutputRecord.filter(Column("compositionId") == compositionId).fetchOne($0)
        }) { return existing }
        guard let record = try await db.writer.read({ try CompositionRecord.fetchOne($0, key: compositionId) }) else {
            throw Failure.noComposition(compositionId)
        }
        var comp = try record.composition()
        let style = try StyleStore.load(comp.style).values

        // 원본 사본 · 다이제스트 (장면이 여러 영상을 쓸 수 있다)
        var sources: [String: URL] = [:]
        var digests: [String: DigestRecord] = [:]
        for id in Set(comp.scenes.map(\.source.videoID)) {
            let (video, digest) = try await db.writer.read { db in
                (try VideoRecord.fetchOne(db, key: id), try DigestRecord.fetchOne(db, key: id))
            }
            guard let path = video?.localPath, video?.status == .ready else { throw Failure.sourceNotReady(id) }
            sources[id] = URL(fileURLWithPath: path)
            if let digest { digests[id] = digest }
        }

        // 화면 잡기 — auto 장면의 키프레임을 채워 편집안에 되쓴다 (§7-1 재현 가능성).
        var report: [String: JSONValue] = [:]
        var reframed = false
        if comp.scenes.contains(where: { $0.reframe.mode == .auto }) {
            let tracks = try Dictionary(uniqueKeysWithValues: Set(comp.scenes.map(\.source.videoID)).map { id in
                guard let d = digests[id] else { throw Failure.noDigest(id) }
                return (id, d.subject)
            })
            let plan = ReframePlanner.apply(to: comp, tracks: tracks, style: style)
            comp = plan.composition
            reframed = true
            report["G1"] = .string(Self.label(plan.g1))
            report["G2"] = .string(Self.label(plan.g2))
            report["G3"] = .string(Self.label(plan.g3))
            report["heightPassRatio"] = .number(plan.heightPassRatio)
            report["maxCenterShiftPerFrame"] = .number(plan.maxCenterShiftPerFrame)
        }

        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        let out = outputs.appending(path: "\(comp.id).mp4")
        let started = Date()
        try await Renderer().render(comp, sources: sources, style: style, to: out)
        let seconds = Date().timeIntervalSince(started)

        let size = comp.size.cgSize
        for slot in Set(comp.scenes.map { comp.captionSlot(for: $0) }) {
            report["G4.\(slot.rawValue)"] = .string(Self.label(Gate.g4(frameSize: size, style: style, slot: slot).0))
        }
        report["G5"] = .string(Self.label(Gate.g5(comp, frameSize: size, style: style).0))
        if let transcript = digests[comp.videoID]?.transcript {
            let (g6, m) = Gate.g6(comp, transcript: transcript)
            report["G6"] = .string(Self.label(g6))
            report["G6.worstError"] = .number(m.worstError)
        }
        report["renderSeconds"] = .number(seconds)

        // 채운 키프레임은 **렌더가 성공한 뒤에** 편집안에 되쓴다 (§7-1 재현 가능성).
        // 먼저 쓰면 렌더가 실패했을 때 편집안이 이미 keyframes 모드라, 다시 렌더할 때 화면 잡기와 G1~G3 를 건너뛴다.
        if reframed { try db.saveComposition(comp, createdAt: record.createdAt) }
        let reportJSON = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        let output = OutputRecord(id: UUID().uuidString, compositionId: comp.id, path: out.path,
                                  reviewReport: reportJSON, arch: MachineArch.current, createdAt: Date())
        try await db.writer.write { try output.insert($0) }
        try db.log("render.done", subject: comp.id, payload: report)
        return output
    }

    static func label(_ r: GateResult) -> String {
        switch r {
        case .pass: "pass"
        case .fail: "fail"
        case .cannotJudge(let n): "cannotJudge:\(n.rawValue)"
        case .sourceLimited(let n): "sourceLimited:\(n.rawValue)"
        }
    }
}
