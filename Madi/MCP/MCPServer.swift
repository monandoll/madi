import Foundation

/// MCP stdio 서버의 프로토콜 부분 (AGENTS.md §10). JSON-RPC 2.0, 한 줄에 메시지 하나.
///
/// 도구가 무엇인지는 모른다 — `MadiTools` 가 정한다. 여기는 봉투만 연다.
/// 줄 하나를 받아 답할 줄 하나(없으면 nil)를 돌려주는 순수 함수라 테스트에서 프로세스 없이 부른다.
public struct MCPServer {
    public static let serverName = "madi"
    /// 아는 판. 클라이언트가 이 중 하나를 말하면 그대로 돌려주고, 아니면 가장 새것을 말한다 (MCP 판 협상).
    static let knownVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]

    let tools: MadiTools

    public init(tools: MadiTools) { self.tools = tools }

    /// 표준 입력이 닫힐 때까지 돈다. 로그는 표준 오류로만 — 표준 출력은 프로토콜 전용이다.
    public func run(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        var buffer = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let reply = handle(line: line) { output.write(Data((reply + "\n").utf8)) }
            }
        }
    }

    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let msg = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "JSON 이 아니다"]])
        }
        let id = msg["id"]
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]
        // id 가 없으면 알림 — 답하지 않는다 (notifications/initialized 등).
        guard let id else { return nil }

        func result(_ r: [String: Any]) -> String? { Self.encode(["jsonrpc": "2.0", "id": id, "result": r]) }
        func error(_ code: Int, _ message: String) -> String? {
            Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return result([
                "protocolVersion": Self.knownVersions.contains(asked) ? asked : Self.knownVersions.last!,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.serverName, "version": "1"],
            ])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": MadiTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else { return error(-32602, "name 이 없다") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let out = tools.call(name, arguments: arguments)
            return result(["content": out.content, "isError": out.isError])
        default:
            return error(-32601, "모르는 메서드: \(method)")
        }
    }

    static func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
