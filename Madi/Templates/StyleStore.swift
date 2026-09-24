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

        public var description: String {
            switch self {
            case .notFound(let id, let searched):
                "스타일 \(id) 를 찾지 못했습니다. 찾아본 곳:\n"
                    + searched.map { "  - \($0)" }.joined(separator: "\n")
            }
        }
    }

    /// 기본 스타일. 0단계에는 이것 하나뿐이다.
    public static let defaultID = "short.v1"

    /// `styles/<id>.json` 을 읽어 검증한다.
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
