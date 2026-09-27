import Foundation
import CoreText
import os

/// 자막 글꼴 목록 = **이 Mac 에 설치된 한글 글꼴 ∪ 무료 글꼴 목록** (docs/findings/2026-09-27-font-catalog.md).
///
/// 목록 글꼴은 받기 전에도 보이고, 고르면 받는다. 받은 글꼴은 시스템에 설치하지 않고
/// **앱 프로세스에만** 등록한다 — 사용자의 글꼴 메뉴를 어지럽히지 않는다.
/// 편집안이 쓰던 목록 글꼴이 지워졌으면 다시 받아 복구할 수 있다.
public enum FontLibrary {
    private static let log = Logger(subsystem: "app.madi", category: "fonts")

    public struct Choice: Sendable, Hashable {
        public enum Source: Sendable, Hashable {
            case bundled            // Pretendard (fontFamily = nil)
            case installed          // 사용자가 이 Mac 에 설치한 글꼴
            case catalog(ready: Bool, packID: String, bytes: Int64)
        }
        public var family: String?
        public var source: Source
    }

    /// 설정 화면의 글꼴 목록. 맨 앞은 기본(Pretendard).
    public static func choices(catalog: DownloadCatalog, root: URL = Downloads.defaultRoot) -> [Choice] {
        let packs = catalog.packs.filter { $0.kind == .font }
        let catalogFamilies = Set(packs.compactMap(\.family))
        var out = [Choice(family: nil, source: .bundled)]
        out += packs.compactMap { p in
            p.family.map { Choice(family: $0, source: .catalog(ready: Downloads.isReady(p, root: root), packID: p.id, bytes: p.totalSize)) }
        }
        out += MadiFont.hangulFamilies().filter { !catalogFamilies.contains($0) }.map { Choice(family: $0, source: .installed) }
        return out
    }

    /// 받아 둔 목록 글꼴을 이 프로세스에 등록한다. 앱 시작 때 · 새로 받은 뒤 한 번.
    public static func registerDownloaded(catalog: DownloadCatalog, root: URL = Downloads.defaultRoot) {
        for pack in catalog.packs where pack.kind == .font && Downloads.isReady(pack, root: root) {
            for file in pack.files where file.path.hasSuffix(".ttf") || file.path.hasSuffix(".otf") {
                var error: Unmanaged<CFError>?
                let url = root.appending(path: file.path) as CFURL
                if !CTFontManagerRegisterFontsForURL(url, .process, &error) {
                    let code = (error?.takeRetainedValue() as Error?).map { ($0 as NSError).code } ?? -1
                    if code != Int(CTFontManagerError.alreadyRegistered.rawValue) {
                        log.error("글꼴 등록 실패 \(file.path, privacy: .public) (\(code))")
                    }
                }
            }
        }
    }

    /// 목록 글꼴 하나를 받고 등록한다.
    public static func fetch(
        family: String, catalog: DownloadCatalog, root: URL = Downloads.defaultRoot,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let pack = catalog.packs.first(where: { $0.kind == .font && $0.family == family }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await Downloads.fetch(pack, root: root, progress: progress)
        registerDownloaded(catalog: catalog, root: root)
    }
}
