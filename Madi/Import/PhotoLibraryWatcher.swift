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

    /// 감시를 시작한다. 권한이 없으면 false — 폴더 감시만 쓴다.
    /// - Parameter ask: 아직 안 물었으면 권한 창을 띄울지. **앱을 켤 때는 묻지 않는다** — 첫 실행 창이 무엇을 읽는지
    ///   먼저 말한 뒤 "사진 접근 허용" 에서 묻는다 (디자인 `onboarding-photos`). 켤 때 물으면 답을 기다리느라 시작이 막힌다
    public func start(ask: Bool = false) async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status = current == .notDetermined && ask ? await PHPhotoLibrary.requestAuthorization(for: .readWrite) : current
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

    /// 한 번 더 훑는다 — 받기에 실패한 영상은 다시 받는다 ("다시 가져오기"). 준비된 영상은 건너뛴다.
    public func rescan() { scan() }

    /// 이 앨범에서만 가져온다 (설정 "사진 폴더"). nil 이면 전체 보관함. 값은 설정(`madi.album.id`).
    public static let albumKey = "madi.album.id"
    public static let albumNameKey = "madi.album.name"

    /// 앨범 목록 — 설정에서 고른다 (사용자가 만든 앨범 + 공유 앨범).
    public static func albums() -> [(id: String, name: String)] {
        var out: [(String, String)] = []
        for type in [PHAssetCollectionType.album] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { c, _, _ in
                out.append((c.localIdentifier, c.localizedTitle ?? ""))
            }
        }
        return out.filter { !$0.1.isEmpty }
    }

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
        let assets: PHFetchResult<PHAsset>
        if let albumID = UserDefaults.standard.string(forKey: Self.albumKey),
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND mediaType == %d", since as NSDate, PHAssetMediaType.video.rawValue)
            assets = PHAsset.fetchAssets(in: album, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: .video, options: options)
        }
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
