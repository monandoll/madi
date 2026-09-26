import Foundation
import os

/// 스타일 값을 **파일에서** 읽는다. AGENTS.md §9.
///
/// 값이 코드가 아니라 데이터인 이유: "자막이 좀 큰 것 같은데" 에 새 빌드를 배포하지 않고
/// 답할 수 있어야 한다. 여기가 그 경계다 — 위로는 JSON, 아래로는 검증된 `StyleValues`.
///
/// ⚠ DB 는 아직 없다 (0단계 범위 밖). 지금은 파일 한 장을 읽는 것까지다.
///   나중에 `Style` 레코드로 옮길 때 이 타입의 바깥 모양은 그대로 둘 수 있게 짰다.
public struct Style: Codable, Hashable, Sendable {
    public let id: String
    /// 표시용 이름. **코드에 사람 이름을 박지 않는다** (AGENTS.md §1-7).
    /// 여기는 설정값이라 괜찮다.
    public var name: String
    public var version: Int

    /// `docs/style-authoring.md §1` 의 5편 절차를 통과했는가.
    /// false 면 렌더할 때마다 경고가 남는다. 조용히 지나가지 않는다.
    public var measured: Bool
    public var measuredNote: String?
    /// 어떤 프레임에서 재서 나온 값인지. 나중에 "왜 이 값인가" 를 되짚는 유일한 근거다.
    public var measuredFrom: [String]

    public var values: StyleValues
}

public enum StyleStore {
    private static let log = Logger(subsystem: "app.madi", category: "style")

    public enum Failure: Error, CustomStringConvertible {
        case notFound(String, [String])
        case versionNotFound(StyleRef, URL)

        public var description: String {
            switch self {
            case .notFound(let id, let searched):
                "스타일 \(id) 를 찾지 못했습니다. 찾아본 곳:\n"
                    + searched.map { "  - \($0)" }.joined(separator: "\n")
            case .versionNotFound(let ref, let dir):
                "스타일 \(ref.id) v\(ref.version) 를 찾지 못했습니다 (\(dir.path)). "
                    + "옛 버전은 지우면 안 됩니다 — 그 버전으로 만든 편집안을 다시 그릴 수 없습니다"
            }
        }
    }

    /// 기본 스타일. 0단계에는 이것 하나뿐이다.
    public static let defaultID = "short.v1"

    /// **번들 기본 스타일** `styles/<id>.json` 을 읽어 검증한다. 사용자 폴더는 보지 않는다
    /// (테스트가 개발 Mac 에 저장된 사용자 모양에 흔들리지 않게).
    ///
    /// 찾는 순서:
    ///   1. `MADI_STYLES_DIR` 환경변수 — 측정 루프용. 레포의 JSON 을 고치고 바로 다시 그린다
    ///   2. MadiKit 번들의 `styles/`
    public static func load(_ id: String = defaultID) throws -> Style {
        var searched: [String] = []
        for url in candidateURLs(for: id) {
            searched.append(url.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let decoder = JSONDecoder()
            let style = try decoder.decode(Style.self, from: Data(contentsOf: url))
            try validate(style.values)
            if !style.measured {
                log.warning("""
                스타일 \(style.id, privacy: .public) 은 아직 확정값이 아닙니다. \
                공개본 5편으로 다시 재고 measured 를 true 로 바꾸세요 (docs/style-authoring.md §1).
                """)
            }
            return style
        }
        throw Failure.notFound(id, searched)
    }

    // MARK: - 버전

    /// 사용자가 고른 자막 모양이 저장되는 곳. `<id>@<version>.json`.
    ///
    /// ⚠ DB(`styles` 테이블)는 3단계다. 그때 옮겨도 바깥 모양(`load(_:in:)` · `saveLook`)은 그대로 둔다.
    public static var defaultUserDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "madi/styles", directoryHint: .isDirectory)
    }

    /// 정확히 그 버전. 편집안을 그릴 때는 **항상 이걸 쓴다** (`Composition.style`).
    ///
    /// 번들 파일의 `version` 과 같으면 번들을, 아니면 사용자 폴더의 `<id>@<version>.json` 을 읽는다.
    /// ★ 번들 파일의 `version` 은 올리지 않는다. 템플릿 값이 바뀌면 새 id(`short.v2`)로 만든다 —
    ///   안 그러면 사용자가 저장한 버전 번호와 부딪힌다.
    public static func load(_ ref: StyleRef, in userDirectory: URL = defaultUserDirectory) throws -> Style {
        let base = try load(ref.id)
        if base.version == ref.version { return base }
        let url = userDirectory.appending(path: fileName(ref))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.versionNotFound(ref, userDirectory)
        }
        let style = try JSONDecoder().decode(Style.self, from: Data(contentsOf: url))
        try validate(style.values)
        return style
    }

    /// 가장 최근 버전. **새 편집안**에 찍을 스타일이다.
    public static func latest(_ id: String = defaultID, in userDirectory: URL = defaultUserDirectory) throws -> StyleRef {
        let base = try load(id)
        return StyleRef(id: id, version: max(base.version, savedVersions(id, in: userDirectory).max() ?? 0))
    }

    /// 사용자가 고른 모양으로 **새 버전**을 만든다. 템플릿 값은 `base` 그대로, `look` 만 바뀐다.
    ///
    /// - 옛 버전을 덮어쓰지 않는다. 그 버전으로 만든 편집안이 있다 (§1-8)
    /// - 설치 안 된 글꼴이면 저장하지 않는다 (`validate`)
    @discardableResult
    public static func saveLook(
        _ look: StyleValues.LookValues, basedOn base: Style,
        in userDirectory: URL = defaultUserDirectory
    ) throws -> Style {
        var style = base
        style.values.look = look
        try validate(style.values)
        style.version = try latest(base.id, in: userDirectory).version + 1

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let url = userDirectory.appending(path: fileName(StyleRef(id: style.id, version: style.version)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `.withoutOverwriting` — 같은 번호가 이미 있으면 실패한다. 덮어쓰는 길이 없다.
        try encoder.encode(style).write(to: url, options: .withoutOverwriting)
        return style
    }

    private static func fileName(_ ref: StyleRef) -> String { "\(ref.id)@\(ref.version).json" }

    private static func savedVersions(_ id: String, in dir: URL) -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let prefix = "\(id)@"
        return names.compactMap { name in
            guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
            return Int(name.dropFirst(prefix.count).dropLast(".json".count))
        }
    }

    private static func candidateURLs(for id: String) -> [URL] {
        var urls: [URL] = []
        if let dir = ProcessInfo.processInfo.environment["MADI_STYLES_DIR"], !dir.isEmpty {
            urls.append(URL(fileURLWithPath: dir).appending(path: "\(id).json"))
        }
        let bundle = Bundle(for: StyleBundleToken.self)
        if let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "styles") {
            urls.append(url)
        }
        return urls
    }
}

/// `Bundle(for:)` 로 MadiKit 프레임워크 번들을 잡기 위한 앵커.
private final class StyleBundleToken {}
