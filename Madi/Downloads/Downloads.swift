import Foundation
import CryptoKit
import os

/// 앱이 대신 받아 주는 파일 — 전사 모델 · 무료 글꼴 (AGENTS.md §2 · §3).
///
/// - **공식 배포처에서, 커밋을 고정해서** 받는다. 배포처가 파일을 바꿔도 결과가 바뀌지 않아야 한다 (§1-8)
/// - 받은 파일은 **SHA-256** 으로 확인한다. 틀리면 버린다 — 제자리에는 확인된 파일만 있다
/// - 목록은 데이터다 (`Resources/downloads.json`). 코드는 목록만 보고 받는다
public struct DownloadCatalog: Codable, Sendable {
    public struct File: Codable, Sendable, Hashable {
        public var url: URL
        /// 저장 위치. `Downloads.root` 기준 상대 경로.
        public var path: String
        public var size: Int64
        public var sha256: String
    }
    public struct Pack: Codable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable { case model, font }
        public var id: String
        public var kind: Kind
        public var family: String?
        public var license: String
        public var files: [File]
        public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    }
    public var packs: [Pack]

    public static func bundled() throws -> DownloadCatalog {
        guard let url = Bundle(for: DownloadsBundleToken.self).url(forResource: "downloads", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(DownloadCatalog.self, from: Data(contentsOf: url))
    }

    public func pack(_ id: String) -> Pack? { packs.first { $0.id == id } }
}

public enum DownloadError: Error, CustomStringConvertible {
    case checksumMismatch(String)
    case badStatus(String, Int)
    public var description: String {
        switch self {
        case .checksumMismatch(let p): "받은 파일이 목록의 해시와 다르다: \(p)"
        case .badStatus(let p, let code): "받지 못했다 (\(code)): \(p)"
        }
    }
}

/// 받기. 팩 단위로 받고, 다 받고 확인되면 팩 폴더에 확인 표시(`.verified`)를 남긴다.
public enum Downloads {
    private static let log = Logger(subsystem: "app.madi", category: "downloads")

    /// `~/Library/Application Support/madi/downloads/` — 다시 받을 수 있는 파일이라 백업에서 뺀다.
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/downloads", directoryHint: .isDirectory)
    }

    /// 팩이 이미 다 받아져 확인됐는가. 파일을 다시 해시하지 않는다 — 확인 표시와 크기만 본다.
    public static func isReady(_ pack: DownloadCatalog.Pack, root: URL = defaultRoot) -> Bool {
        guard FileManager.default.fileExists(atPath: marker(pack, root: root).path) else { return false }
        return pack.files.allSatisfy { f in
            let size = (try? FileManager.default.attributesOfItem(atPath: root.appending(path: f.path).path)[.size] as? NSNumber)?.int64Value
            return size == f.size
        }
    }

    /// 팩을 받는다. 이미 확인된 파일은 건너뛴다. 진행률은 바이트 기준 0~1.
    public static func fetch(
        _ pack: DownloadCatalog.Pack, root: URL = defaultRoot, session: URLSession = .shared,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var r = root
        try? r.setResourceValues(values)

        let total = Double(max(pack.totalSize, 1))
        var done: Int64 = 0
        for file in pack.files {
            let dest = root.appending(path: file.path)
            if try existingMatches(dest, file) {
                done += file.size
                progress?(Double(done) / total)
                continue
            }
            let (tmp, response) = try await session.download(from: file.url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: tmp)
                throw DownloadError.badStatus(file.path, http.statusCode)
            }
            guard try sha256(of: tmp) == file.sha256 else {
                try? FileManager.default.removeItem(at: tmp)
                throw DownloadError.checksumMismatch(file.path)
            }
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            done += file.size
            progress?(Double(done) / total)
        }
        try Data(pack.files.map(\.sha256).joined(separator: "\n").utf8).write(to: marker(pack, root: root))
        log.info("받음 \(pack.id, privacy: .public) \(pack.totalSize) 바이트")
    }

    private static func marker(_ pack: DownloadCatalog.Pack, root: URL) -> URL {
        root.appending(path: ".verified-\(pack.id)")
    }

    private static func existingMatches(_ url: URL, _ file: DownloadCatalog.File) throws -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.size] as? NSNumber)?.int64Value == file.size else { return false }
        return try sha256(of: url) == file.sha256
    }

    /// 큰 파일도 메모리에 다 올리지 않고 해시한다 (모델 가중치 300MB).
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadsBundleToken {}
