import Foundation
import os

/// 폴더 감시 — **보조 경로** (AGENTS.md §2). 사진 앱 권한을 안 주거나 쓰기 싫어할 때.
///
/// 폴더에 영상 파일(`mov` · `mp4` · `m4v`)이 생기면 가져온다. 원본은 앱 폴더로 **복사**한다 —
/// 폴더의 파일을 옮기거나 지워도 편집안을 다시 그릴 수 있어야 한다 (§1-8).
///
/// ★ 쓰는 중인 파일을 집지 않는다 — 크기가 두 번 연속 같을 때만 들인다 (AirDrop · 복사 도중).
public final class FolderWatcher: @unchecked Sendable {

    private static let log = Logger(subsystem: "app.madi", category: "import")
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    private let importer: Importer
    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private let lock = NSLock()
    private var lastSizes: [String: Int64] = [:]
    /// 이미 `Importer` 에 넘긴 파일. 변경 알림이 겹쳐도 같은 파일을 두 번 복사하지 않는다.
    private var handedOver: Set<String> = []

    public init(importer: Importer, folder: URL) {
        self.importer = importer
        self.folder = folder
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .global())
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        scan()
    }

    public func stop() { source?.cancel(); source = nil }

    /// 크기가 안정된 영상 파일을 들인다. 아직 쓰는 중이면 1초 뒤 다시 본다.
    func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])) ?? []
        var ready: [URL] = []
        var pending = false
        lock.withLock {
            for f in files where Self.videoExtensions.contains(f.pathExtension.lowercased()) {
                let size = Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
                guard !handedOver.contains(f.path) else { continue }
                if let last = lastSizes[f.path], last == size, size > 0 {
                    ready.append(f)
                    handedOver.insert(f.path)
                } else {
                    pending = true
                }
                lastSizes[f.path] = size
            }
        }
        for f in ready {
            let created = try? f.resourceValues(forKeys: [.creationDateKey]).creationDate
            let item = IncomingVideo(
                source: .folder, sourceRef: f.path, fileExtension: f.pathExtension, capturedAt: created,
                fetch: { destination, progress in
                    try FileManager.default.copyItem(at: f, to: destination)
                    progress(1)
                }
            )
            Task {
                do { try await importer.receive(item) } catch {
                    Self.log.error("폴더 가져오기 실패 \(f.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
        if pending {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in self?.scan() }
        }
    }
}
