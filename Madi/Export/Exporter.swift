import Foundation
import GRDB
import Photos

/// 결과물을 쓰는 일 — 내보내기 · 봤다 · 휴지통 (docs/stage-6.spec.md 7번, ViewData `ExportTarget` · `ResultRef`).
///
/// - 아이폰에서 확인하려면 사진 앱으로 보낸다 (§2 — iOS 앱이 없다)
/// - "Mac에 저장" 은 **사람이 고른 폴더**에 복사한다 (고르는 창은 앱이 띄운다)
/// - 휴지통은 macOS 휴지통이다 — 되살릴 수 있다. 행은 지우지 않고 표시만 한다 (§5 결과물이 있는 편집안은 고치지 못한다)
/// - 내보낸 것은 이력으로 남긴다 — 목록 줄에 "사진 앱에 저장함 · 오후 2:40" (올렸는지 헷갈리지 않게)
public enum Exporter {

    public enum Failure: Error, CustomStringConvertible {
        case noOutput(String)
        case photos(String)
        public var description: String {
            switch self {
            case .noOutput(let id): "결과물이 없다: \(id)"
            case .photos(let m): "사진 앱에 넣지 못했다: \(m)"
            }
        }
    }

    static func output(_ db: AppDatabase, _ id: String) async throws -> OutputRecord {
        guard let o = try await db.writer.read({ try OutputRecord.fetchOne($0, key: id) }) else { throw Failure.noOutput(id) }
        return o
    }

    static func record(_ db: AppDatabase, _ outputID: String, _ target: ExportRecord.Target, _ location: String?) async throws {
        try await db.writer.write { db in
            var row = ExportRecord(outputId: outputID, target: target, location: location)
            try row.insert(db)
        }
        try? db.log("export.done", subject: outputID, payload: ["target": .string(target.rawValue)])
    }

    /// 사진 앱으로. 돌려주는 값은 사진 앱의 식별자.
    @discardableResult
    public static func toPhotos(_ db: AppDatabase, outputID: String) async throws -> String {
        let o = try await output(db, outputID)
        let url = URL(fileURLWithPath: o.path)
        nonisolated(unsafe) var identifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            try? db.log("export.failed", subject: outputID, payload: ["target": .string("photos"), "error": .string("\(error)")])
            throw Failure.photos(error.localizedDescription)
        }
        try await record(db, outputID, .photos, identifier)
        return identifier ?? ""
    }

    /// 사람이 고른 폴더에 복사한다. 이름이 겹치면 ` 2` · ` 3` 을 붙인다.
    @discardableResult
    public static func toFolder(_ db: AppDatabase, outputID: String, folder: URL, name: String) async throws -> URL {
        let o = try await output(db, outputID)
        let fm = FileManager.default
        let base = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        var dest = folder.appending(path: "\(base.isEmpty ? "마디" : base).mp4")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appending(path: "\(base) \(n).mp4")
            n += 1
        }
        try fm.copyItem(at: URL(fileURLWithPath: o.path), to: dest)
        try await record(db, outputID, .folder, dest.path)
        return dest
    }

    public static func markSeen(_ db: AppDatabase, outputID: String, at: Date = Date()) async throws {
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE output SET seenAt = ? WHERE id = ? AND seenAt IS NULL", arguments: [at, outputID])
        }
    }

    /// macOS 휴지통으로. 파일이 이미 없으면 표시만 한다.
    public static func trash(_ db: AppDatabase, outputID: String, at: Date = Date()) async throws {
        let o = try await output(db, outputID)
        let url = URL(fileURLWithPath: o.path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE output SET trashedAt = ? WHERE id = ?", arguments: [at, outputID])
        }
        try? db.log("output.trashed", subject: outputID)
    }
}
