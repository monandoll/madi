import Foundation
import Photos
import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

/// 사진 앱(iCloud 사진)에 새 영상이 생기면 가져온다 (AGENTS.md §2 · §1-11 — 파일을 옮기게 하지 않는다).
///
/// ```
/// 아이폰 촬영 → iCloud 사진 동기화 → 이 Mac 사진 보관함 → 변경 알림 → Importer
/// ```
/// - 보관함의 영상은 **전부 보인다** (2026-10-01 사용자: "기존 영상도 다 불러와야지"). 다만 둘로 나눠 다룬다:
///   - `since`(앱을 처음 켠 시각) **이후**에 찍은 영상 — 바로 원본을 받고 분석해 둔다 (찍으면 앱에 이미 있어야 한다, §1-11)
///   - 그 **전부터 있던** 영상 — 목록에만 올린다 (`Importer.list`, 미리보기 그림은 사진 앱 것). 몇 년 치를 전부 복사 · 분석하지 않고,
///     `숏폼 만들기` 를 누르면 그때 받는다 (`fetch(localIdentifier:)`)
/// - "저장 공간 최적화" 면 Mac 에 저화질만 있다 — **원본을 iCloud 에서 받는다**
///   (`isNetworkAccessAllowed`, §2 주의할 것)
/// - 한 번에 하나씩 처리한다. 변경 알림이 겹쳐 와도 같은 영상을 두 번 받지 않는다
public final class PhotoLibraryWatcher: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    private static let log = Logger(subsystem: "app.madi", category: "import")

    private let importer: Importer
    private let since: Date
    private let thumbnails: Thumbnails
    /// 목록 · 미리보기 그림이 늘었다 — 화면을 다시 그리라고 알린다 (그림 파일은 DB 가 아니라 관측에 안 잡힌다).
    private let onChange: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var scanning = false
    private var rescanRequested = false

    public init(importer: Importer, since: Date, thumbnails: Thumbnails = Thumbnails(), onChange: (@Sendable () -> Void)? = nil) {
        self.importer = importer
        self.since = since
        self.thumbnails = thumbnails
        self.onChange = onChange
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

    /// 보관함을 훑는다 — 전부터 있던 영상은 목록에, `since` 이후 영상은 받아서 들인다 (받다 만 것도 이어 받는다).
    private func scan() {
        lock.lock()
        if scanning { rescanRequested = true; lock.unlock(); return }
        scanning = true
        lock.unlock()

        Task {
            repeat {
                lock.withLock { rescanRequested = false }
                let (older, newer) = assets()
                // 1. 전부터 있던 영상 — 목록에만 (빠르다). 미리보기 그림은 뒤에서 채운다
                do {
                    let listed = try await importer.list(older.map(Self.listed))
                    if !listed.isEmpty {
                        onChange?()
                        let thumbnails = self.thumbnails, onChange = self.onChange
                        Task.detached(priority: .utility) { Self.makeThumbnails(for: listed, into: thumbnails, onChange: onChange) }
                    }
                } catch {
                    Self.log.error("보관함 목록 실패: \(String(describing: error), privacy: .public)")
                }
                // 2. 새로 찍은 영상 — 원본을 받아 분석까지
                for item in newer.compactMap(Self.incoming) {
                    do { try await importer.receive(item) } catch {
                        Self.log.error("가져오기 실패 \(item.sourceRef, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            } while lock.withLock({ rescanRequested })
            lock.withLock { scanning = false }
        }
    }

    /// 목록에만 있던 영상 하나를 **지금 받는다** (`숏폼 만들기` 를 눌렀을 때). 받으면 분석이 걸린다.
    public func fetch(localIdentifier: String) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject,
              let item = Self.incoming(asset) else {
            Self.log.error("사진 보관함에서 못 찾았다: \(localIdentifier, privacy: .public)")
            return
        }
        do { try await importer.receive(item) } catch {
            Self.log.error("가져오기 실패 \(localIdentifier, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// 보관함(또는 고른 앨범)의 영상 전부 — `since` 전 것과 뒤 것으로 나눈다. 찍은 순.
    private func assets() -> (older: [PHAsset], newer: [PHAsset]) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result: PHFetchResult<PHAsset>
        if let albumID = UserDefaults.standard.string(forKey: Self.albumKey),
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            result = PHAsset.fetchAssets(in: album, options: options)
        } else {
            result = PHAsset.fetchAssets(with: .video, options: options)
        }
        var older: [PHAsset] = [], newer: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if (asset.creationDate ?? .distantPast) >= self.since { newer.append(asset) } else { older.append(asset) }
        }
        return (older, newer)
    }

    /// 목록에 올릴 만큼만 — 원본 자원은 받을 때 찾는다 (자산마다 자원을 물으면 몇 천 개에서 느리다).
    static func listed(_ asset: PHAsset) -> Importer.Listed {
        Importer.Listed(sourceRef: asset.localIdentifier, capturedAt: asset.creationDate,
                        durationSec: asset.duration, width: asset.pixelWidth, height: asset.pixelHeight)
    }

    static func incoming(_ asset: PHAsset) -> IncomingVideo? {
        let resources = PHAssetResource.assetResources(for: asset)
        // 편집본이 아니라 **찍은 그대로의 원본**.
        guard let found = resources.first(where: { $0.type == .video }) ?? resources.first else { return nil }
        // PHAssetResource 는 Sendable 표시가 없지만 받기 요청에 넘기기만 한다 (읽기 전용)
        nonisolated(unsafe) let original = found
        let ext = (original.originalFilename as NSString).pathExtension
        return IncomingVideo(
            source: .photos, sourceRef: asset.localIdentifier,
            fileExtension: ext.isEmpty ? "mov" : ext, capturedAt: asset.creationDate,
            fetch: { destination, progress in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                options.progressHandler = { progress($0) }
                try await PHAssetResourceManager.default().writeData(for: original, toFile: destination, options: options)
            }
        )
    }

    /// 목록에만 있는 영상의 미리보기 그림 — 사진 앱이 가진 것을 받아 앱의 그림 자리에 둔다 (원본을 받지 않고도 갤러리에 보인다).
    /// 최근 것부터. 몇 천 개면 1분쯤 걸려서 뒤에서 돌고, 묶음마다 화면을 다시 그리게 알린다.
    static func makeThumbnails(for rows: [VideoRecord], into thumbnails: Thumbnails, onChange: (@Sendable () -> Void)?) {
        try? FileManager.default.createDirectory(at: thumbnails.root, withIntermediateDirectories: true)
        let options = PHImageRequestOptions()
        options.isSynchronous = true               // 뒤 스레드에서 하나씩 — 돌아오기 전에 그림이 온다
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let newestFirst = rows.sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        let size = 40
        for start in stride(from: 0, to: newestFirst.count, by: size) {
            let chunk = Array(newestFirst[start..<min(start + size, newestFirst.count)])
            let ids = Dictionary(uniqueKeysWithValues: chunk.map { ($0.sourceRef, $0.id) })
            PHAsset.fetchAssets(withLocalIdentifiers: chunk.map(\.sourceRef), options: nil).enumerateObjects { asset, _, _ in
                guard let id = ids[asset.localIdentifier] else { return }
                let out = thumbnails.video(id)
                if FileManager.default.fileExists(atPath: out.path) { return }
                autoreleasepool {
                    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 480, height: 480),
                                                          contentMode: .aspectFit, options: options) { image, _ in
                        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
                        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                        CGImageDestinationFinalize(dest)
                    }
                }
            }
            onChange?()
        }
    }
}
