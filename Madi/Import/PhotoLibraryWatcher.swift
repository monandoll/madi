import Foundation
import Photos
import os

/// 사진 앱(iCloud 사진)에 새 영상이 생기면 가져온다 (AGENTS.md §2 · §1-11 — 파일을 옮기게 하지 않는다).
///
/// ```
/// 아이폰 촬영 → iCloud 사진 동기화 → 이 Mac 사진 보관함 → 변경 알림 → Importer
/// ```
/// - **`since` 이후에 찍은 영상만** 들인다. 보관함 전체를 들이면 몇 년 치 영상이 다 들어온다.
///   `since` 는 앱을 처음 켠 시각이다 (`ImportSettings`)
/// - "저장 공간 최적화" 면 Mac 에 저화질만 있다 — **원본을 iCloud 에서 받는다**
///   (`isNetworkAccessAllowed`, §2 주의할 것)
/// - 한 번에 하나씩 처리한다. 변경 알림이 겹쳐 와도 같은 영상을 두 번 받지 않는다
public final class PhotoLibraryWatcher: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    private static let log = Logger(subsystem: "app.madi", category: "import")

    private let importer: Importer
    private let since: Date
    private let lock = NSLock()
    private var scanning = false
    private var rescanRequested = false

    public init(importer: Importer, since: Date) {
        self.importer = importer
        self.since = since
    }

    /// 권한을 묻고(첫 실행 한 번) 감시를 시작한다. 권한이 없으면 false — 폴더 감시만 쓴다.
    public func start() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            Self.log.notice("사진 보관함 권한 없음 (\(status.rawValue)) — 폴더 감시만 쓴다")
            return false
        }
        PHPhotoLibrary.shared().register(self)
        scan()
        return true
    }

    public func stop() { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    public func photoLibraryDidChange(_ changeInstance: PHChange) { scan() }

    /// `since` 이후 영상을 훑어 새 것 · 받다 만 것을 들인다.
    private func scan() {
        lock.lock()
        if scanning { rescanRequested = true; lock.unlock(); return }
        scanning = true
        lock.unlock()

        Task {
            repeat {
                lock.withLock { rescanRequested = false }
                for item in incoming() {
                    do { try await importer.receive(item) } catch {
                        Self.log.error("가져오기 실패 \(item.sourceRef, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            } while lock.withLock({ rescanRequested })
            lock.withLock { scanning = false }
        }
    }

    private func incoming() -> [IncomingVideo] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var out: [IncomingVideo] = []
        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            // 편집본이 아니라 **찍은 그대로의 원본**.
            guard let original = resources.first(where: { $0.type == .video }) ?? resources.first else { return }
            let ext = (original.originalFilename as NSString).pathExtension
            out.append(IncomingVideo(
                source: .photos, sourceRef: asset.localIdentifier,
                fileExtension: ext.isEmpty ? "mov" : ext, capturedAt: asset.creationDate,
                fetch: { destination, progress in
                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.progressHandler = { progress($0) }
                    try await PHAssetResourceManager.default().writeData(for: original, toFile: destination, options: options)
                }
            ))
        }
        return out
    }
}
