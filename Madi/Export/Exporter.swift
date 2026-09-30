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

    /// 앱이 내보낸 것 — 사진 앱 식별자 · 파일 경로. **가져오기가 이걸 새 촬영본으로 다시 들이지 않게** 한다.
    ///
    /// 전에는 사진 앱으로 보낸 결과물이 사진 보관함 감시에 새 영상으로 잡혀 촬영본이 되고, 분석 → AI 초안 → 렌더까지
    /// 저절로 돌았다 — 구독을 쓰고, 그 결과물을 또 보내면 또 들어온다 (2026-09-30).
    /// 이력(`export` 행)은 보내기가 끝난 **뒤에** 적히는데 사진 앱 변경 알림은 그 전에 올 수 있어, 방금 보낸 것은 메모리에도 둔다.
    public static let sent = SentRefs()

    public final class SentRefs: @unchecked Sendable {
        private let lock = NSLock()
        private var refs: Set<String> = []
        public func insert(_ ref: String) { lock.withLock { _ = refs.insert(ref) } }
        public func remove(_ ref: String) { lock.withLock { _ = refs.remove(ref) } }
        public func contains(_ ref: String) -> Bool { lock.withLock { refs.contains(ref) } }
    }

    /// 이 영상(사진 앱 식별자 · 파일 경로)이 앱이 내보낸 결과물인가 — 방금 보낸 것 또는 이력.
    public static func isOwnExport(_ ref: String, _ db: Database) throws -> Bool {
        if sent.contains(ref) { return true }
        // SQL 로 비교하지 않는다 — 같은 한글 경로가 조합 방식(NFC · NFD)만 달라 바이트가 다르게 온다
        // (저장한 경로는 NFD, 폴더 감시가 읽은 경로는 NFC 였다). Swift 문자열은 글자로 비교한다.
        return try String.fetchAll(db, sql: "SELECT location FROM export WHERE location IS NOT NULL").contains(ref)
    }

    /// 내보내는 파일 이름(확장자 없이) — "스튜디오 · 제목". 첫 실행 · 설정이 결과물이 이 이름으로 저장된다고 말한다
    /// (전에는 제목만 썼다). 스튜디오가 비면 제목만, 둘 다 비면 "마디".
    public static func fileName(studio: String, title: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = [clean(studio), clean(title)].filter { !$0.isEmpty }
        return parts.isEmpty ? "마디" : parts.joined(separator: " · ")
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

    /// 사진 앱으로. 돌려주는 값은 사진 앱의 식별자. `name` 은 사진 앱 정보에 남는 파일 이름 (확장자 없이, `fileName`).
    @discardableResult
    public static func toPhotos(_ db: AppDatabase, outputID: String, name: String = "") async throws -> String {
        let o = try await output(db, outputID)
        let url = URL(fileURLWithPath: o.path)
        nonisolated(unsafe) var identifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                if !name.isEmpty { options.originalFilename = "\(name).mp4" }
                request.addResource(with: .video, fileURL: url, options: options)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
                // 변경이 보관함에 들어가기 **전에** 적는다 — 변경 알림을 받은 가져오기가 먼저 봐도 걸러지게
                if let identifier { sent.insert(identifier) }
            }
        } catch {
            if let identifier { sent.remove(identifier) }
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
        // 입구 폴더(폴더 감시)에 저장해도 촬영본으로 다시 들어오지 않게 — 복사 **전에** 적는다
        sent.insert(dest.path)
        do {
            try fm.copyItem(at: URL(fileURLWithPath: o.path), to: dest)
        } catch {
            sent.remove(dest.path)
            throw error
        }
        try await record(db, outputID, .folder, dest.path)
        return dest
    }

    /// 사람이 저장 창에서 고른 자리(이름 포함)에 복사한다. 같은 이름이 있으면 저장 창이 이미 "대치할까요?" 를 물었다.
    @discardableResult
    public static func toFile(_ db: AppDatabase, outputID: String, url dest: URL) async throws -> URL {
        let o = try await output(db, outputID)
        let fm = FileManager.default
        // 입구 폴더(폴더 감시)에 저장해도 촬영본으로 다시 들어오지 않게 — 복사 **전에** 적는다
        sent.insert(dest.path)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: URL(fileURLWithPath: o.path), to: dest)
        } catch {
            sent.remove(dest.path)
            throw error
        }
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
