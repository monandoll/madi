import Foundation
import MadiKit

/// AI CLI(claude · codex)가 자식 프로세스로 띄우는 MCP 서버 (AGENTS.md §10, docs/stage-4.spec.md 결정 ① — 번들 안 별도 도구).
///
/// 앱이 AI 한 턴을 걸 때 설정에 이 실행 파일과 인자를 적어 넘긴다. 사람이 직접 부르지 않는다.
///
///   madi-mcp --video <id> --composition <id> [--revision-of <id>] [--db <sqlite 경로>]
///
/// 앱 초기화(사진 감시 · 큐 · 모델 받기)는 여기서 하지 않는다 — DB 를 열고 도구 2개만 연다.
/// 표준 출력은 프로토콜 전용이다. 사람이 읽을 말은 표준 오류로.
let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--" + name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("madi-mcp: " + message + "\n").utf8))
    exit(2)
}

guard let video = option("video"), let composition = option("composition") else {
    fail("--video 와 --composition 이 필요하다")
}

let db: AppDatabase
do {
    db = try option("db").map { try AppDatabase.open(path: $0) } ?? AppDatabase.openDefault()
} catch {
    fail("DB 를 열지 못했다: \(error)")
}

MCPServer(tools: MadiTools(db: db, videoID: video, compositionID: composition, revisionOf: option("revision-of"))).run()
