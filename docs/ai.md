# AI 연결 (4단계)

사용자 PC 에 설치된 **Claude Code** 또는 **Codex** CLI 를 엔진이 자식 프로세스로 띄워 채팅 편집을 한다.
API 키 없음, 서버 없음 — 사용자 본인 구독으로 돈다. 판매 시 "AI 포함 요금제"는 `AgentProvider` 구현 하나를 더하면 된다.

## 흐름

```
브라우저  POST /api/videos/:id/chat {text}
   │
엔진      AgentRunner.ask → 메시지 2개(user.text, ai.text streaming) → provider.run
   │        프롬프트 = 영상 정보 + 최근 대화 + 사용자 말,  시스템 = 규칙 + style.md
   ▼
claude -p --output-format stream-json --mcp-config mcp.json --strict-mcp-config --allowedTools mcp__madi__* ...
   │  (codex exec --json -c mcp_servers.madi...)
   ├─ stdout(JSONL) → ClaudeStream/CodexStream → library.updateMessage(ai.text) 150ms 단위
   └─ 자식: MCP 서버 (dist/mcp.mjs | src/mcp/index.ts)
              stdio JSON-RPC ← tools/list, tools/call
              → POST /api/agent/tools/:name (x-madi-agent: 토큰)
                 → AgentTools: 잡 걸고 기다림, 진행 카드/결과 카드는 워커가 붙임
```

- 에이전트는 파일·셸을 못 만진다: claude 는 `--disallowedTools Bash,Edit,Write,Read,…`, codex 는 `-s read-only`. 작업 폴더는 빈 임시 폴더.
- MCP 서버는 DB 를 열지 않는다. 엔진 HTTP 만 부른다. 토큰은 엔진이 뜰 때마다 새로.
- 영상당 동시 1. 돌아가는 동안 또 보내면 409 `ai_busy`. `POST /chat/cancel` 로 멈춤.
- AI 미연결(`settings.ai.provider === 'none'`)이면 러너를 아예 스폰하지 않는다 (409 `ai_off`). 버튼 4개는 그대로 워커 직접 호출.

## 도구 (`apps/engine/src/mcp/tools.ts`)

| 이름 | 하는 일 |
|---|---|
| `get_transcript` | 자막(문장·시각). 없으면 whisper 로 만들고 기다린다 |
| `find_silences` | 무음 구간 |
| `find_scenes` | 장면 전환 시각 + 구간 |
| `propose_cuts` | 무음 → 잘라낼 구간 제안 |
| `apply_edit` | Edit 생성/수정 (keep, cuts, crop, subtitles) |
| `render` | Edit → 결과 파일. 끝날 때까지 기다림 |
| `extract_shorts` | 구간 여러 개 → 9:16 숏폼 파일들 |
| `set_subtitle_style` | 자막 모양. `remember` 면 기본값도 |
| `set_subtitle_text` | 자막 문장 고치기. `lines[{start,end,text}]` 가 겹치는 문장을 바꾼다(`replaceAll` 이면 전체). 자막이 없으면 `model=manual` 로 새로 만든다. "이 문장 고쳐줘", "○○라고 자막 넣어줘" 용 |
| `update_style_rule` | style.md 에 규칙 한 줄 (사용자가 예라고 한 뒤에만) |

렌더는 항상 Edit 로부터 — 에이전트도 예외 없다.

## StyleProfile (`~/.madi/style/`)

- `style.md` 자연어 규칙. 시스템 프롬프트에 항상 들어간다. 기본 내용은 `agent/style.ts`.
- `params.json` 숫자 기본값(자막 스타일).
- `examples/` 5단계.

수정 요청을 받으면 고친 뒤 "앞으로도 이렇게 할까요?" 를 한 번 묻고, 예일 때만 `update_style_rule`. 프롬프트 규칙으로 강제한다.

## CLI 찾기 (`agent/detect.ts`)

`MADI_CLAUDE_BIN` / `MADI_CODEX_BIN` → PATH → 흔한 설치 위치(`~/.claude/local`, `~/.local/bin`, npm 전역, nvm, homebrew …).
트레이 앱은 로그인 셸 PATH 를 못 받으므로 후보 폴더가 중요하다. `--version` 이 8초 안에 답해야 설치된 것으로 본다. 60초 캐시.

Windows 의 `claude.cmd` 는 `cmd.exe /d /s /c` 로 띄운다 (`provider.ts spawnCli`).

## 테스트

- 단위: 스트림 파서 두 개, 인자 조립, StyleProfile, MCP 서버(가짜 call).
- 엔진 e2e `test/e2e.agent.test.ts`: `fixtures/fake-claude.mjs` 가 진짜 claude 처럼 `--mcp-config` 의 서버를 띄우고 stdio 로 도구를 부른 뒤 stream-json 을 낸다. 그래서 MCP 서버 프로세스·도구 API·렌더까지 실제로 돈다.
- 브라우저 e2e `e2e/3-ai.spec.ts`: 설정에서 고르기 → 칩·입력 → 스트리밍 답 → 결과물 카드 → 멈추기 → 연결 끊기.

진짜 CLI 로 손 테스트: `claude` 가 PATH 에 있으면 설정 → AI → Claude Code "쓰기". 로그는 `~/.madi/logs/engine.log` (`agent` 항목, debug).

## CLI 가 죽을 때

러너는 CLI 의 stderr/JSON 오류를 코드로 나눠 채팅에 보인다 (`classifyAgentError`): `ai_login`(로그인 안 됨 — `codex login` / `claude`), `ai_node_missing`(npm 설치본이 `node` 를 못 찾음), 나머지 `ai_failed`. 원문 300자는 말풍선 아래 "이유: …" 로 보인다.

트레이 앱은 로그인 셸 PATH 를 물려받지 못한다. npm 으로 깐 `codex`/`claude` 는 `#!/usr/bin/env node` 라 `node` 가 PATH 에 없으면 exit 127 로 죽는다 → 자식 CLI 를 띄울 때 `withKnownDirs` 가 `/opt/homebrew/bin`, `/usr/local/bin`, `~/.nvm/versions/node/*/bin`, `%APPDATA%\npm`, `Program Files\nodejs` 등을 PATH 뒤에 붙인다.
