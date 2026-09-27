import Foundation
import os

/// 전사 모델 준비 — **첫 실행이 끝나자마자 백그라운드로** 받고 데운다 (docs/stage-3.spec.md 결정 A).
///
/// 크리에이터의 첫 영상이 다운로드를 기다리지 않게 하려는 것이다. 영상이 먼저 들어오면
/// 분석 작업은 준비가 끝날 때까지 기다린다(`PreparedTranscriber`).
///
/// 상태는 `docs/design/copy-keys.md` 의 모델 준비 키와 1:1 이다. 준비가 끝나면 **아무 말도 하지 않는다.**
public actor ModelPreparer {

    public enum State: Sendable, Equatable {
        case notStarted
        case downloading(Double)   // modelDownloading
        case paused                // modelDownloadPaused — 인터넷이 돌아오면 이어서
        case warming               // modelWarming
        case ready
        case failed(String)        // modelDownloadFailed
        case diskFull              // modelDiskFull
    }

    private static let log = Logger(subsystem: "app.madi", category: "model")
    public static let packID = "model.whisper-small"

    public private(set) var state: State = .notStarted
    private let pack: DownloadCatalog.Pack
    private let root: URL
    private let provider: WhisperKitProvider
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var observers: [UUID: AsyncStream<State>.Continuation] = [:]
    private var running = false

    public init(catalog: DownloadCatalog, root: URL = Downloads.defaultRoot) throws {
        guard let pack = catalog.pack(Self.packID) else { throw CocoaError(.fileNoSuchFile) }
        self.pack = pack
        self.root = root
        self.provider = WhisperKitProvider(
            model: "small",
            modelFolder: root.appending(path: "whisperkit/openai_whisper-small"),
            tokenizerFolder: root.appending(path: "tokenizers")
        )
    }

    /// 상태가 바뀔 때마다. 화면(디자인 쪽)이 구독한다.
    public func states() -> AsyncStream<State> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(state)
            observers[id] = continuation
            continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        }
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func set(_ new: State) {
        state = new
        for c in observers.values { c.yield(new) }
    }

    /// 첫 실행 뒤 한 번 부른다. 이미 돌고 있으면 아무것도 안 한다.
    /// 인터넷이 끊기면 30초마다 다시 시도한다. 해시가 틀리면 세 번까지.
    public func prepare(retryDelaySec: Double = 30) async {
        guard !running, state != .ready else { return }
        running = true
        defer { running = false }

        var checksumFailures = 0
        while true {
            if Downloads.isReady(pack, root: root) { break }
            if freeBytes() < pack.totalSize + 200_000_000 {
                set(.diskFull)
                try? await Task.sleep(nanoseconds: UInt64(retryDelaySec * 1e9))
                continue
            }
            do {
                set(.downloading(0))
                try await Downloads.fetch(pack, root: root) { p in Task { await self.progress(p) } }
                break
            } catch let error as DownloadError {
                checksumFailures += 1
                Self.log.error("모델 받기 실패: \(error.description, privacy: .public)")
                if checksumFailures >= 3 { return fail(error.description) }
            } catch {
                // 인터넷 끊김 · 서버 문제 — 실패가 아니라 멈춤이다.
                set(.paused)
                try? await Task.sleep(nanoseconds: UInt64(retryDelaySec * 1e9))
            }
        }

        set(.warming)
        do {
            try await provider.warmUp()
        } catch {
            return fail("\(error)")
        }
        set(.ready)
        for w in readyWaiters { w.resume() }
        readyWaiters = []
    }

    private func progress(_ p: Double) {
        if case .downloading = state { set(.downloading(p)) }
    }

    private func fail(_ reason: String) {
        set(.failed(reason))
        for w in readyWaiters { w.resume(throwing: TranscriptionFailure.modelUnavailable(reason)) }
        readyWaiters = []
    }

    /// 준비된 전사기. 준비가 안 끝났으면 끝날 때까지 기다린다.
    public func readyProvider() async throws -> WhisperKitProvider {
        if state == .ready { return provider }
        if case .failed(let reason) = state { throw TranscriptionFailure.modelUnavailable(reason) }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        return provider
    }

    private func freeBytes() -> Int64 {
        let values = try? FileManager.default.homeDirectoryForCurrentUser
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}

/// 분석 작업에 넘기는 전사기. 모델 준비가 끝날 때까지 기다렸다가 전사한다.
/// 기다리는 동안 `model.waiting` 이벤트를 남긴다 — 채팅 `modelWaitingForVideo` 의 근거.
public struct PreparedTranscriber: TranscriptionProvider {
    public let preparer: ModelPreparer
    public let db: AppDatabase?

    public init(preparer: ModelPreparer, db: AppDatabase? = nil) {
        self.preparer = preparer; self.db = db
    }

    public func transcribe(_ url: URL, languageCode: String) async throws -> Transcript {
        if await preparer.state != .ready {
            try? db?.log("model.waiting", subject: url.deletingPathExtension().lastPathComponent)
        }
        return try await preparer.readyProvider().transcribe(url, languageCode: languageCode)
    }
}
