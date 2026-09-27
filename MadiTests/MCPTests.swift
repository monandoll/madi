import Testing
import Foundation
import GRDB
@testable import MadiKit

/// MCP 서버 — 도구 2개 (AGENTS.md §10 · docs/stage-4.spec.md 2번).
/// 프로세스 없이 줄 하나를 넣고 줄 하나를 받는다.
struct MCPTests {

    private struct Fixture {
        let db: AppDatabase
        let server: MCPServer
        let sheet: URL
    }

    private func fixture(videoID: String = "v1", duration: Double = 20) throws -> Fixture {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try VideoRecord(id: videoID, source: .folder, sourceRef: "/tmp/\(videoID).mov",
                            durationSec: duration, status: .ready).insert(db)
        }
        let sheet = FileManager.default.temporaryDirectory.appending(path: "mcp-sheet-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sheet)
        let digest = DigestRecord(
            videoId: videoID, version: 1, sourceFingerprint: "fp", text: "# VIDEO \(videoID)\n## TRANSCRIPT",
            sheetPaths: [sheet.path], transcript: Transcript(videoID: videoID, words: Self.words),
            subject: SubjectTrack(source: SourceInfo(videoID: videoID, width: 1920, height: 1080, durationSec: duration, fps: 30),
                                  stepSec: 0.5, samples: []),
            createdAt: Date()
        )
        try db.writer.write { try digest.insert($0) }
        let tools = MadiTools(db: db, videoID: videoID, compositionID: "c_ai",
                              style: { var s = try StyleStore.load(); s.version = 3; return s })
        return Fixture(db: db, server: MCPServer(tools: tools), sheet: sheet)
    }

    private func call(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:], id: Int = 1) throws -> [String: Any] {
        let line = String(decoding: try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]), as: UTF8.self)
        let reply = try #require(server.handle(line: line))
        return try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func tool(_ server: MCPServer, _ name: String, _ arguments: [String: Any]) throws -> (text: String, isError: Bool, content: [[String: Any]]) {
        let r = try #require(try call(server, "tools/call", ["name": name, "arguments": arguments])["result"] as? [String: Any])
        let content = try #require(r["content"] as? [[String: Any]])
        return (content.first?["text"] as? String ?? "", r["isError"] as? Bool ?? false, content)
    }

    /// 문장 둘: [0.10-2.30] · [3.00-5.20] (DigestBuilder.sentences — 끝 문장부호에서 끊는다)
    static let words: [Word] = [
        Word(text: "오늘은", start: 0.1, end: 0.5), Word(text: "골반", start: 0.5, end: 0.9),
        Word(text: "스트레칭을", start: 0.9, end: 1.5), Word(text: "알려드릴게요.", start: 1.5, end: 2.3),
        Word(text: "양쪽", start: 3.0, end: 3.3), Word(text: "다리를", start: 3.3, end: 3.7),
        Word(text: "펴고", start: 3.7, end: 4.0), Word(text: "천천히", start: 4.0, end: 4.5),
        Word(text: "숙여주세요.", start: 4.5, end: 5.2),
    ]

    private let draft: [String: Any] = [
        "meta": ["title": "골반", "targetDurationSec": 8],
        "captionSlot": "fullBody",
        "scenes": [[
            "id": "s1", "role": "hook", "source": ["videoId": "v1", "in": 0.1, "out": 8],
        ]],
    ]

    @Test("initialize 는 클라이언트 판을 돌려주고, 알림에는 답하지 않는다")
    func handshake() throws {
        let f = try fixture()
        let r = try #require(try call(f.server, "initialize", ["protocolVersion": "2025-06-18"])["result"] as? [String: Any])
        #expect(r["protocolVersion"] as? String == "2025-06-18")
        #expect((r["serverInfo"] as? [String: Any])?["name"] as? String == "madi")
        #expect(f.server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test("도구는 read_digest · write_composition 두 개뿐이다")
    func listsTwoTools() throws {
        let f = try fixture()
        let tools = try #require((try call(f.server, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String }.sorted() == ["read_digest", "write_composition"])
    }

    @Test("read_digest 는 텍스트와 시트 이미지를 준다")
    func readsDigest() throws {
        let f = try fixture()
        let out = try tool(f.server, "read_digest", ["videoId": "v1"])
        #expect(!out.isError)
        #expect(out.text.hasPrefix("# VIDEO v1"))
        let image = try #require(out.content.first { $0["type"] as? String == "image" })
        #expect(image["mimeType"] as? String == "image/png")
        #expect(image["data"] as? String == Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
    }

    @Test("다른 영상은 읽을 수 없다")
    func refusesOtherVideo() throws {
        let f = try fixture()
        #expect(try tool(f.server, "read_digest", ["videoId": "v2"]).isError)
    }

    @Test("write_composition 은 앱이 스타일 · id 를 찍어 저장한다")
    func writesComposition() throws {
        let f = try fixture()
        let out = try tool(f.server, "write_composition", ["composition": draft])
        #expect(!out.isError, "\(out.text)")
        let rec = try #require(try f.db.writer.read { try CompositionRecord.fetchOne($0, key: "c_ai") })
        let comp = try rec.composition()
        #expect(comp.style == StyleRef(id: "short.v1", version: 3))
        #expect(!comp.scenes[0].captions.isEmpty)
        #expect(comp.videoID == "v1")
        #expect(comp.templateID == "short")
        #expect(comp.captionSlot == .fullBody)
    }

    @Test("자막은 앱이 전사에서 채운다 — 장면 로컬 시각, 첫 자막은 0초")
    func fillsCaptions() throws {
        let f = try fixture()
        #expect(!(try tool(f.server, "write_composition", ["composition": draft]).isError))
        let comp = try #require(try f.db.writer.read { try CompositionRecord.fetchOne($0, key: "c_ai") }).composition()
        let caps = comp.scenes[0].captions
        #expect(!caps.isEmpty)
        #expect(abs(caps[0].start) < 0.001)
        #expect(caps.map(\.text).joined(separator: " ") == Self.words.map(\.text).joined(separator: " "))
        #expect(caps.allSatisfy { $0.secondary == nil })
    }

    @Test("AI 가 자막을 적으면 거절한다")
    func rejectsCaptions() throws {
        let f = try fixture()
        var bad = draft
        var scene = (bad["scenes"] as! [[String: Any]])[0]
        scene["captions"] = [["id": "c1", "start": 0, "end": 1.2, "text": "골반이 아프면", "slot": "main"]]
        bad["scenes"] = [scene]
        let out = try tool(f.server, "write_composition", ["composition": bad])
        #expect(out.isError)
        #expect(out.text.contains("scenes[0].captions"))
    }

    @Test("영문은 문장마다 받아 그 문장의 덩어리들에 나눠 붙인다")
    func distributesSecondary() throws {
        let f = try fixture()
        let secondary: [[String: Any]] = [
            ["sentenceStart": 0.10, "text": "Today I'll show you a hip stretch."],
            ["sentenceStart": 3.00, "text": "Straighten both legs and slowly bend forward."],
        ]
        let out = try tool(f.server, "write_composition", ["composition": draft, "secondary": secondary])
        #expect(!out.isError, "\(out.text)")
        let caps = try #require(try f.db.writer.read { try CompositionRecord.fetchOne($0, key: "c_ai") }).composition().scenes[0].captions
        let english = caps.compactMap(\.secondary).joined(separator: " ")
        #expect(english == "Today I'll show you a hip stretch. Straighten both legs and slowly bend forward.")
    }

    @Test("다이제스트에 없는 문장 시작을 짚으면 거절한다")
    func rejectsUnknownSentence() throws {
        let f = try fixture()
        let out = try tool(f.server, "write_composition", ["composition": draft, "secondary": [["sentenceStart": 1.0, "text": "x"]]])
        #expect(out.isError)
        #expect(out.text.contains("1.00"))
    }

    @Test("JSON 문자열로 보내도 받는다")
    func acceptsJSONString() throws {
        let f = try fixture()
        let s = String(decoding: try JSONSerialization.data(withJSONObject: draft), as: UTF8.self)
        #expect(!(try tool(f.server, "write_composition", ["composition": s]).isError))
    }

    @Test("AI 가 style 이나 id 를 적으면 거절한다 — 앱이 채우는 칸")
    func rejectsAppFilledKeys() throws {
        let f = try fixture()
        var bad = draft
        bad["style"] = ["id": "short.v1", "version": 1]
        bad["id"] = "mine"
        let out = try tool(f.server, "write_composition", ["composition": bad])
        #expect(out.isError)
        #expect(out.text.contains("style") && out.text.contains("id"))
        #expect(try f.db.writer.read { try CompositionRecord.fetchCount($0) } == 0)
    }

    @Test("스타일 값은 payload 안에 숨겨도 거절한다")
    func rejectsStyleValues() throws {
        let f = try fixture()
        var bad = draft
        var scene = (bad["scenes"] as! [[String: Any]])[0]
        scene["overlays"] = [["id": "o1", "kind": "mark", "start": 0, "end": 1, "anchor": ["x": 0.5, "y": 0.5],
                              "payload": ["symbol": "o", "color": "red"]]]
        bad["scenes"] = [scene]
        let out = try tool(f.server, "write_composition", ["composition": bad])
        #expect(out.isError)
        #expect(out.text.contains("color"))
    }

    @Test("검증 실패는 무엇이 틀렸는지 그대로 돌려준다")
    func returnsProblems() throws {
        let f = try fixture()
        var bad = draft
        bad.removeValue(forKey: "captionSlot")
        let missing = try tool(f.server, "write_composition", ["composition": bad])
        #expect(missing.isError)
        #expect(missing.text.contains("captionSlot"))

        var backwards = draft
        var scene = (backwards["scenes"] as! [[String: Any]])[0]
        scene["source"] = ["videoId": "v1", "in": 5, "out": 2]
        backwards["scenes"] = [scene]
        #expect(try tool(f.server, "write_composition", ["composition": backwards]).text.contains("scenes[0].source"))
    }

    @Test("원본 구간이 영상 길이를 넘으면 거절한다")
    func rejectsBeyondDuration() throws {
        let f = try fixture(duration: 6)
        let out = try tool(f.server, "write_composition", ["composition": draft])
        #expect(out.isError)
        #expect(out.text.contains("영상 길이"))
    }

    @Test("여러 번 써도 같은 편집안 id 를 덮어쓴다")
    func overwritesSameID() throws {
        let f = try fixture()
        _ = try tool(f.server, "write_composition", ["composition": draft])
        var second = draft
        second["captionSlot"] = "upperBody"
        #expect(!(try tool(f.server, "write_composition", ["composition": second]).isError))
        #expect(try f.db.writer.read { try CompositionRecord.fetchCount($0) } == 1)
        #expect(try f.db.writer.read { try CompositionRecord.fetchOne($0, key: "c_ai") }?.composition().captionSlot == .upperBody)
    }

    @Test("모르는 메서드 · 모르는 도구")
    func unknowns() throws {
        let f = try fixture()
        #expect((try call(f.server, "resources/list")["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(try tool(f.server, "render", [:]).isError)
    }
}
