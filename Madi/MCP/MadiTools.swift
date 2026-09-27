import Foundation
import GRDB

/// AI 에게 주는 도구 **2개** (AGENTS.md §10). 더 늘리고 싶으면 "이게 없으면 AI 가 뭘 못 하나" 부터 적는다.
///
/// 서버 하나는 **영상 하나 · 편집안 id 하나**에 묶인다 (앱이 스폰할 때 정한다).
/// - AI 는 다른 영상을 읽거나 쓸 수 없다
/// - 앱은 턴이 끝난 뒤 어느 편집안을 볼지 미리 안다. AI 가 여러 번 써도 같은 id 를 덮어쓴다
///   (결과물이 생기기 전이라 DB 가 허락한다 — 생긴 뒤에는 새 id · `revisionOf`, §5)
public struct MadiTools: Sendable {
    public let db: AppDatabase
    public let videoID: String
    public let compositionID: String
    public let revisionOf: String?
    /// 저장할 편집안의 출처 — 첫 초안이면 draft, 되먹임 턴이면 selfEval (§7 횟수를 센다).
    public let origin: CompositionRecord.Origin
    /// 되먹임 턴이면 지난 결과물(**내보낸 파일**, §7)의 프레임 시트. `read_digest` 가 원본 시트 뒤에 붙여 준다.
    /// 도구를 늘리지 않고 AI 가 자기 결과를 보게 한다 (§1-4 · §10 도구 2개).
    public let feedbackSheet: URL?
    /// 새 편집안에 찍을 스타일(가장 최근 버전). AI 가 아니라 앱이 찍는다 (§5). 자막 분절 값도 여기서 온다.
    /// 테스트에서 바꿔 끼운다.
    public let style: @Sendable () throws -> Style

    public static let templateID = "short"
    public static let templateVersion = 1

    /// AI 가 쓰면 거절하는 칸 — 앱이 채운다. Spec.json `_앱이 채우는 것` 과 같아야 한다.
    public static let appFilledKeys = ["id", "videoId", "templateId", "templateVersion", "style", "revisionOf", "createdAt"]

    public init(
        db: AppDatabase, videoID: String, compositionID: String, revisionOf: String? = nil,
        origin: CompositionRecord.Origin = .draft, feedbackSheet: URL? = nil,
        style: @escaping @Sendable () throws -> Style = { try StyleStore.load(try StyleStore.latest()) }
    ) {
        self.db = db; self.videoID = videoID; self.compositionID = compositionID
        self.revisionOf = revisionOf; self.origin = origin; self.feedbackSheet = feedbackSheet; self.style = style
    }

    public struct Output {
        public var content: [[String: Any]]
        public var isError: Bool

        static func text(_ s: String, error: Bool = false) -> Output {
            Output(content: [["type": "text", "text": s]], isError: error)
        }
    }

    static var definitions: [[String: Any]] { [
        [
            "name": "read_digest",
            "description": "영상 다이제스트를 읽는다 — 전사(낱말 시각) · 사람 위치 · 소리 · 컷 지점 · 프레임 시트 이미지. 영상을 보는 유일한 창구다. 동작은 자막으로 추측하지 말고 SUBJECT 와 이미지로 확인한다.",
            "inputSchema": [
                "type": "object",
                "properties": ["videoId": ["type": "string", "description": "영상 id"]],
                "required": ["videoId"],
            ],
        ],
        [
            "name": "write_composition",
            "description": "편집안(Composition)을 검증하고 저장한다. 틀리면 무엇이 틀렸는지 돌려주니 고쳐서 다시 부른다. 렌더는 앱이 한다. 스타일 값(글꼴 · 색 · 크기 · 좌표)은 쓸 수 없다. id · videoId · templateId · templateVersion · style · revisionOf · createdAt 은 앱이 채우니 적지 않는다. 자막(scenes[].captions)도 앱이 전사에서 채우니 적지 않는다 — 장면의 원본 구간만 고른다. 영문 보조 문구는 secondary 에 문장마다 한 줄씩 쓴다.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "composition": ["type": "object", "description": "meta · captionSlot · scenes · audio"],
                    "secondary": [
                        "type": "array",
                        "description": "영문 보조 문구. 다이제스트 TRANSCRIPT 의 문장마다 한 줄. 앱이 그 문장의 자막 덩어리들에 나눠 붙인다. 없으면 영문 없이 만든다.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "sentenceStart": ["type": "number", "description": "TRANSCRIPT [시작-끝] 의 시작 초 그대로"],
                                "text": ["type": "string", "description": "그 문장의 영어 번역 한 줄"],
                            ],
                            "required": ["sentenceStart", "text"],
                        ],
                    ],
                ],
                "required": ["composition"],
            ],
        ],
    ] }

    func call(_ name: String, arguments: [String: Any]) -> Output {
        switch name {
        case "read_digest": return readDigest(arguments)
        case "write_composition": return writeComposition(arguments)
        default: return .text("모르는 도구: \(name). 도구는 read_digest · write_composition 뿐이다.", error: true)
        }
    }

    // MARK: - read_digest

    func readDigest(_ args: [String: Any]) -> Output {
        guard let asked = args["videoId"] as? String else { return .text("videoId 가 없다.", error: true) }
        guard asked == videoID else { return .text("이 대화에서는 영상 \(videoID) 만 읽을 수 있다.", error: true) }
        let digest: DigestRecord?
        do { digest = try db.writer.read { try DigestRecord.fetchOne($0, key: videoID) } } catch {
            return .text("다이제스트를 읽지 못했다: \(error)", error: true)
        }
        guard let digest else { return .text("영상 \(videoID) 의 다이제스트가 아직 없다.", error: true) }

        var content: [[String: Any]] = [["type": "text", "text": digest.text]]
        for path in digest.sheetPaths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else {
                content.append(["type": "text", "text": "(시트 \(url.lastPathComponent) 를 읽지 못했다)"])
                continue
            }
            content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": Self.mimeType(url)])
        }
        if let feedbackSheet {
            if let data = try? Data(contentsOf: feedbackSheet) {
                content.append(["type": "text", "text": "## 지난 결과물 — 내보낸 영상에서 뽑은 프레임 (자막이 그려진 그대로)"])
                content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": Self.mimeType(feedbackSheet)])
            } else {
                content.append(["type": "text", "text": "(지난 결과물 시트를 읽지 못했다)"])
            }
        }
        return Output(content: content, isError: false)
    }

    static func mimeType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        default: return "image/png"
        }
    }

    // MARK: - write_composition

    func writeComposition(_ args: [String: Any]) -> Output {
        // 객체로 오는 게 맞지만 JSON 문자열로 보내는 클라이언트도 받아 준다.
        var body: [String: Any]
        if let obj = args["composition"] as? [String: Any] {
            body = obj
        } else if let s = args["composition"] as? String,
                  let obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] {
            body = obj
        } else {
            return reject(["composition 이 JSON 객체가 아니다"])
        }

        let filled = Self.appFilledKeys.filter { body[$0] != nil }
        if !filled.isEmpty {
            return reject(["앱이 채우는 칸이다 — 빼고 다시 보낸다: " + filled.joined(separator: ", ")])
        }

        // 자막은 앱이 채운다 — AI 가 적어 보내면 거절한다 (분절은 템플릿 값, §9).
        let scenesWithCaptions = (body["scenes"] as? [[String: Any]] ?? []).enumerated()
            .filter { ($0.element["captions"] as? [Any])?.isEmpty == false }.map { "scenes[\($0.offset)].captions" }
        if !scenesWithCaptions.isEmpty {
            return reject(["자막은 앱이 전사에서 채운다 — 빼고 다시 보낸다: " + scenesWithCaptions.joined(separator: ", ")])
        }
        var translations: [CaptionFiller.Translation] = []
        for (i, item) in (args["secondary"] as? [Any] ?? []).enumerated() {
            guard let d = item as? [String: Any], let at = (d["sentenceStart"] as? NSNumber)?.doubleValue,
                  let text = d["text"] as? String else {
                return reject(["secondary[\(i)] 는 {sentenceStart: 숫자, text: 문자열} 이어야 한다"])
            }
            translations.append(.init(sentenceStart: at, text: text))
        }

        // 영상 하나에 묶인 서버라 원본 id 는 하나뿐이다 — 안 적으면 채운다. 장면 id 도 안 적으면 순서대로 붙인다.
        if var scenes = body["scenes"] as? [[String: Any]] {
            for i in scenes.indices {
                if scenes[i]["id"] == nil { scenes[i]["id"] = "s\(i + 1)" }
                if var source = scenes[i]["source"] as? [String: Any], source["videoId"] == nil {
                    source["videoId"] = videoID
                    scenes[i]["source"] = source
                }
            }
            body["scenes"] = scenes
        }

        let styleValue: Style
        do { styleValue = try style() } catch { return .text("스타일을 읽지 못했다 (앱 문제): \(error)", error: true) }
        let styleRef = StyleRef(id: styleValue.id, version: styleValue.version)
        body["id"] = compositionID
        body["videoId"] = videoID
        body["templateId"] = Self.templateID
        body["templateVersion"] = Self.templateVersion
        body["style"] = ["id": styleRef.id, "version": styleRef.version]
        if let revisionOf { body["revisionOf"] = revisionOf }

        var comp: Composition
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            comp = try parseComposition(data)
        } catch let e as CompositionError {
            return reject(e.problems)
        } catch let e as DecodingError {
            return reject([Self.describe(e)])
        } catch {
            return reject(["\(error)"])
        }

        var problems = Renderer.unsupported(comp)
        let duration = try? db.writer.read { try VideoRecord.fetchOne($0, key: videoID)?.durationSec }
        for (i, scene) in comp.scenes.enumerated() {
            if scene.source.videoID != videoID {
                problems.append("scenes[\(i)].source.videoId 는 \(videoID) 여야 한다")
            }
            if let d = duration ?? nil, scene.source.end > d + 0.05 {
                problems.append("scenes[\(i)].source.out(\(scene.source.end)) 이 영상 길이(\(String(format: "%.2f", d))) 를 넘는다")
            }
        }
        if !problems.isEmpty { return reject(problems) }

        let words: [Word]
        do {
            guard let digest = try db.writer.read({ try DigestRecord.fetchOne($0, key: videoID) }) else {
                return .text("영상 \(videoID) 의 다이제스트가 없어 자막을 채우지 못했다.", error: true)
            }
            words = digest.transcript.words
        } catch {
            return .text("전사를 읽지 못했다 (앱 문제): \(error)", error: true)
        }
        let snapped = CaptionFiller.snapToWords(&comp, words: words)
        problems = CaptionFiller.fill(&comp, words: words, style: styleValue.values.caption, translations: translations)
        if !problems.isEmpty { return reject(problems) }

        do {
            try db.saveComposition(comp, origin: origin)
            try? db.log("agent.composition.saved", subject: comp.id,
                        payload: ["scenes": .number(Double(comp.scenes.count)), "duration": .number(comp.duration)])
        } catch {
            return reject(["저장하지 못했다: \(error)"])
        }
        let captions = comp.scenes.flatMap(\.captions)
        let withSecondary = captions.filter { $0.secondary != nil }.count
        return .text("저장했다 — 장면 \(comp.scenes.count)개 · 길이 \(String(format: "%.1f", comp.duration))초 · "
                     + "자막 \(captions.count)덩어리(영문 \(withSecondary))"
                     + (snapped > 0 ? " · 낱말 중간에 걸린 장면 경계 \(snapped)곳을 낱말 경계로 옮겼다" : "")
                     + ". 렌더는 앱이 한다.")
    }

    private func reject(_ problems: [String]) -> Output {
        try? db.log("agent.composition.rejected", subject: compositionID,
                    payload: ["problems": .array(problems.map { .string($0) })])
        return .text("저장하지 않았다. 고쳐서 다시 보낸다:\n" + problems.map { "- \($0)" }.joined(separator: "\n"), error: true)
    }

    /// Swift 의 DecodingError 문장은 AI 가 읽기 어렵다 — 경로와 무엇이 틀렸는지만 남긴다.
    static func describe(_ e: DecodingError) -> String {
        func path(_ keys: [CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: ["."])
        }
        switch e {
        case .keyNotFound(let key, let ctx):
            let at = path(ctx.codingPath)
            return "필수 칸이 없다: \(at.isEmpty ? "" : at + ".")\(key.stringValue)"
        case .typeMismatch(let type, let ctx):
            return "\(path(ctx.codingPath)): \(type) 이어야 한다"
        case .valueNotFound(let type, let ctx):
            return "\(path(ctx.codingPath)): \(type) 값이 비어 있다"
        case .dataCorrupted(let ctx):
            return "\(path(ctx.codingPath)): \(ctx.debugDescription)"
        @unknown default:
            return "\(e)"
        }
    }
}
