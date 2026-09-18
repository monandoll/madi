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

## 편집안 (기획안 §4 · §13)

촬영본을 넣으면 편집안이 나온다. AI 가 골라져 있으면 상세를 처음 열 때(인사와 함께) `plan` 잡이 걸리고, "편집안 만들기" 버튼으로 다시 읽을 수 있다.

```
plan 잡 (workers/plan.ts, AI 한 턴 · 도구 없음)
  자막 (없고 소리 있으면 먼저 만든다) + 무음을 가만히/동작 중으로 나눔(motion) + 장면 전환 + "# 기억"(recall)
  → plan/prompt.ts planPrompt → provider.analyze → parsePlan → plans 테이블 (EditPlan)
  → 채팅에 plan 카드: 취지 · 시작 · 구성(시간 · 내용 · 편집 초안) · 남길 곳 · 잘라낼 후보 · 숏폼 후보(채널 · 이유) · 용어
```

- 편집안은 **파일을 만들지 않는다**. 사용자가 후보를 눌러야 렌더가 걸린다 (§6 초안 → 확인 → 확정 → 내보내기):
  숏폼 후보 "숏폼으로" → `short` 액션, "잘라낼 후보 N곳을 빼고 롱폼 만들기" → `apply_plan` (`planCuts`: 남길 구간과 겹치는 부분은 컷에서 뺀다).
- 다음 채팅 요청의 프롬프트에 `planBlock` 이 "# 이 영상의 편집안" 으로 들어간다 — 에이전트가 숏폼 · 컷을 고를 때 여기서 시작한다.
- AI 가 없으면 `plan` 은 409 `ai_off`. 편집안 없이 `apply_plan` 은 409 `plan_missing`. 읽기 실패는 채팅에 `plan_failed` (큐 재시도 없음 — 토큰).
- 단위 `test/plan.test.ts`, 엔진 e2e `test/e2e.agent.test.ts` (편집안 → 프롬프트 → 롱폼 만들기), 브라우저 `e2e/3-ai.spec.ts` (처음 열면 카드).

## 도구 (`apps/engine/src/mcp/tools.ts`)

| 이름 | 하는 일 |
|---|---|
| `get_transcript` | 자막(문장·시각). 없으면 whisper 로 만들고 기다린다 |
| `find_silences` | 무음 구간. `moving=true` 는 말은 없지만 동작이 이어지는 침묵(시범) |
| `find_scenes` | 장면 전환 시각 + 구간 |
| `propose_cuts` | 무음 → 잘라낼 구간 제안. 동작이 이어지는 침묵은 `kept` 로 따로 (자르지 않는다) |
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

`MADI_CLAUDE_BIN` / `MADI_CODEX_BIN` → **사용자가 직접 골라 준 파일**(`settings.ai.paths`) → PATH →
흔한 설치 위치(`~/.claude/local`, `~/.local/bin`, npm 전역, nvm, homebrew …).
트레이 앱은 로그인 셸 PATH 를 못 받으므로 후보 폴더가 중요하다. `--version` 이 8초 안에 답해야 설치된 것으로 본다.
60초 캐시이고, 캐시는 `이름 + 직접 고른 경로` 별로 따로 센다.

Windows 의 `claude.cmd` 는 `cmd.exe /d /s /c` 로 띄운다 (`provider.ts spawnCli`).

### 아예 안 깔렸을 때: 마디가 대신 깐다

두 회사 다 **공식 설치기**가 있다. node 도, npm 도, 관리자 권한도 필요 없고 사용자 폴더(`~/.local/bin`)에 깔린다.
그래서 설정의 "이 컴퓨터에 깔기" 한 번이면 끝난다 — 1차 사용자는 터미널을 열 사람이 아니다.

| OS | Claude Code | Codex |
|---|---|---|
| macOS · Linux | `curl -fsSL https://claude.ai/install.sh \| bash` | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` |
| Windows | `irm https://claude.ai/install.ps1 \| iex` (powershell) | `irm https://chatgpt.com/codex/install.ps1 \| iex` |

`agent/install.ts` 가 이 한 줄들을 만든다 (`installLine` = 사람이 직접 칠 줄, `installPlan` = 우리가 띄울 명령).
`MADI_INSTALL_CLAUDE` / `MADI_INSTALL_CODEX` 로 갈아 끼울 수 있다 (테스트가 이걸 쓴다).

| 길 | 하는 일 |
|---|---|
| `GET /api/ai/install` | 지금 깔고 있는지 + 찾은 결과 (화면이 2초마다 본다) |
| `POST /api/ai/install` | 시작. 이미 하고 있으면 409 `ai_install_busy`, 못 깔아 주는 OS 면 501 `ai_install_unsupported` |
| `DELETE /api/ai/install` | 실패 표시 닫기 (다시 누를 수 있게) |
| `POST /api/ai/login` | 로그인 창(터미널) 열기. 못 여는 OS 면 501 `ai_login_unsupported` |

- 한 번에 하나만. 5분 넘으면 멈춘다.
- 설치기가 0 을 돌려줘도 **직접 실행해 봐야**(`--version`) 다 됐다고 본다. 반대로 exit 코드가 이상해도 실행되면 성공.
- 실패 이유는 `network` / `permission` / `timeout` / `unsupported` / `failed` 다섯 가지로만 줄여서 화면에 사람 말로 보인다.
- 끝나면 찾아 둔 기억을 지우고 다시 찾는다. 같은 응답에 찾은 결과가 실려 있어 화면이 바로 "연결하기"로 넘어간다.

### 로그인: 화면 안 터미널

로그인은 자동으로 못 한다 — 브라우저가 떠야 하고 진짜 터미널(PTY)이 필요하다.
그래서 **마디 안에 터미널을 띄운다**. 검은 창을 따로 찾을 필요가 없고, 폰으로 들어와 있어도 똑같이 된다.

```
브라우저 (xterm)  ──WebSocket /api/term──▶  엔진  ──PTY──▶  claude setup-token / codex login
```

- `@lydell/node-pty` (프리빌트만, node-gyp 안 씀 → Electron 에서 재빌드 불필요). `asarUnpack` 에 넣는다.
- `/api/term` 은 `/api/*` 라서 **짝짓기 가드가 그대로 걸린다** (밖에서 온 기기는 6자리 숫자를 맞혀야 붙는다).
- 화면 쪽 xterm 은 열 때만 받아 온다 (`lazy`) — 첫 화면이 무거워지지 않게.
- 한 번에 창 하나. 15분이 지나면 저절로 닫는다.

**열 수 있는 것은 네 개뿐이다** (`TermKind`): `login-claude`, `login-codex`, `install-claude`, `install-codex`.
셸도, 사용자가 친 명령도 열리지 않는다. 목록 밖이면 바로 `bad_kind` 로 거절한다.

> 왜 `claude` 를 그냥 띄우지 않나: 대화형 claude 안에서는 `!` 로 아무 셸 명령이나 돌릴 수 있다.
> 짝지은 폰이 그걸 열 수 있으면 그 폰이 곧 이 PC 의 조종간이 된다. 그래서 로그인만 하고 끝나는
> `claude setup-token` 을 쓴다. codex 는 `codex login`.

창을 못 띄우는 PC 를 위해 `POST /api/ai/login` (트레이 앱이 macOS Terminal.app / Windows 명령 창을 여는 옛 길)을
"이 컴퓨터 창으로 열기" 폴백으로 남겨 뒀다. 그것도 안 되면 화면에 한 줄(`claude setup-token`)을 그대로 보여 준다.

API 키 방식은 아직 안 쓴다 (사용자 본인 구독으로 돈다는 원칙).

### 못 찾을 때: 다시 찾기 · 직접 찾기

설치 자리는 PC 마다 다르다(npm 전역, nvm, winget, 직접 받은 파일…). 그래서 화면에 두 가지를 둔다.

| 화면 | 하는 일 | API |
|---|---|---|
| 다시 찾기 | 캐시를 버리고 처음부터 다시 찾는다 (방금 깔았거나 껐다 켠 경우) | `GET /api/ai/providers?fresh=1` |
| 직접 찾기 | 트레이 앱의 파일 선택창으로 실행 파일을 고른다 | `POST /api/ai/pick {provider}` |
| 직접 고른 것 지우기 | 그 값을 비우고 다시 알아서 찾게 한다 | `POST /api/ai/path {provider, path: null}` |

- 고른 파일은 저장 전에 `--version` 으로 한 번 돌려 본다. 안 돌면 400 `ai_path_bad` → "그 파일로는 안 되네요."
- 파일 선택창은 트레이 앱에만 있다 (`engine.setFilePicker`). 브라우저만 있는 개발 환경에서는 501 `no_picker`.
- 저장된 경로는 `settings.ai.paths.{claude,codex}` 이고 이 PC 의 DB 에만 남는다. 파일이 옮겨지거나 지워지면 자동으로 평소 자리들을 다시 뒤진다.
- 프로바이더만 바꿔도 이 경로는 날아가지 않는다 (설정 저장이 `ai` 를 한 겹 더 깊게 합친다).
- 채팅 도중 `not_installed` 로 죽으면 캐시를 비워서 다음 확인 때 처음부터 다시 찾는다.

아이콘은 각 회사 마크를 그대로 쓴다 (`apps/web/src/components/AiMark.tsx`). 경로 데이터는 `@lobehub/icons-static-svg`(MIT) 에서 가져와 인라인으로 박았다 — 아이콘 두 개 때문에 의존성을 더하지 않는다.

## 테스트

- 단위: 스트림 파서 두 개, 인자 조립, StyleProfile, MCP 서버(가짜 call).
- 엔진 e2e `test/e2e.agent.test.ts`: `fixtures/fake-claude.mjs` 가 진짜 claude 처럼 `--mcp-config` 의 서버를 띄우고 stdio 로 도구를 부른 뒤 stream-json 을 낸다. 그래서 MCP 서버 프로세스·도구 API·렌더까지 실제로 돈다.
- 브라우저 e2e `e2e/3-ai.spec.ts`: 설정에서 고르기 → 칩·입력 → 스트리밍 답 → 결과물 카드 → 멈추기 → 연결 끊기 → 아이콘·다시 찾기·직접 찾기.
- 단위 `test/detect.test.ts`: 직접 고른 파일 우선·사라졌을 때 되돌아가기·경로별 캐시·fresh.
- 단위 `test/install.test.ts`: 플랫폼별 설치·로그인 명령(npm·node 안 씀), 설치 뒤 실행 확인, 실패 이유 줄이기.
- 엔진 e2e `test/e2e.aiinstall.test.ts`: 가짜 설치기로 깔기 → 설치됨 → 연결까지, 동시 실행 409, 로그인 창 501/200.
- 단위 `test/term.test.ts`: 열 수 있는 목록, 로그인이 도구를 통째로 띄우지 않음, 창 크기 이상값, 진짜 PTY 로 글이 나옴.
- 엔진 e2e `test/e2e.term.test.ts`: 소켓으로 터미널 열기, 목록 밖 거절, 짝짓기 전 차단, 창 하나 제한.
- 엔진 e2e `test/e2e.aipath.test.ts`: 엉뚱한 파일 거절, 고른 자리로 연결, 프로바이더를 바꿔도 남음, 파일 선택창 없음(501)·있음.

진짜 CLI 로 손 테스트: `claude` 가 PATH 에 있으면 설정 → AI → Claude Code "쓰기". 로그는 `~/.madi/logs/engine.log` (`agent` 항목, debug).

## CLI 가 죽을 때

러너는 CLI 의 stderr/JSON 오류를 코드로 나눠 채팅에 보인다 (`classifyAgentError`): `ai_login`(로그인 안 됨 — `codex login` / `claude`), `ai_node_missing`(npm 설치본이 `node` 를 못 찾음), 나머지 `ai_failed`. 원문 300자는 말풍선 아래 "이유: …" 로 보인다.

트레이 앱은 로그인 셸 PATH 를 물려받지 못한다. npm 으로 깐 `codex`/`claude` 는 `#!/usr/bin/env node` 라 `node` 가 PATH 에 없으면 exit 127 로 죽는다 → 자식 CLI 를 띄울 때 `withKnownDirs` 가 `/opt/homebrew/bin`, `/usr/local/bin`, `~/.nvm/versions/node/*/bin`, `%APPDATA%\npm`, `Program Files\nodejs` 등을 PATH 뒤에 붙인다.

## 소리 없는 영상의 자막

자막은 말소리에서만 오지 않는다. 직접 쓴 자막(`model=manual`)이 있으면 소리가 없어도 자막 넣기·숏폼 자막·`apply_edit(subtitles)` 가 된다.
- 사용자: 영상 상세의 **자막 직접 쓰기** (줄마다 시작·끝·글) → `PUT /api/videos/:id/transcript {segments}` → 바로 자막 넣기. 결과물의 고른 줄 → **자막 고치기** 로 같은 편집기가 열린다 (AI 없이).
- 에이전트: `set_subtitle_text` 로 넣은 뒤 `apply_edit(subtitles=true)` → `render`. 시각을 안 주면 영상 전체에 한 줄.
- 소리도 없고 자막도 없을 때만 `no_audio`.

## 제작 지침 (어디를 자를지)

도구만 알려 주면 도구는 잘 부르는데 결과가 심심하다. 어디서 시작하고 어디서 끝내는지가 결과물의 거의 전부다.
그 판단 기준을 `src/agent/playbook.ts` 에 모아 시스템 프롬프트에 같이 넣는다.

세기 순서 (아래로 갈수록 세다):

1. **제작 지침** — 운동·재활 숏폼의 일반적인 기준 (이 파일)
2. **배운 값** — 완성본·링크에서 뽑은 길이·비율·무음 기준 (`style.md` 의 학습 블록)
3. **사용자가 쓴 규칙** — `style.md` 위쪽. 충돌하면 항상 이쪽이 이긴다

지침에 들어가는 것:

- **구간** — 첫 1.5초에 무엇에 대한 영상인지 보이게, 인사·채널 소개·촬영 세팅 멘트는 버리기, 한 클립 = 한 동작,
  문장 경계에 맞춰 자르기(앞뒤 0.2~0.3초), 시범은 1회 온전히, 끝은 마무리 문장에서,
  운동 이름·횟수·주의사항 문장은 자르지 않기.
- **롱폼** — 챕터는 주제 단위, 제목은 그 구간에서 실제로 한 말에서, 챕터마다 숏폼 후보 하나, 같은 동작 중복 금지.
- **자막** — 한 줄 12~16자·두 줄까지, 조사에서 끊지 않기, 운동 용어 오인식은 `set_subtitle_text` 로 고치기,
  횟수는 아라비아 숫자, 9:16 은 아래 UI 를 피해 `bottom` 0.18~0.22.
- **답하는 방식** — 되묻지 말고 하나 만들어서 보여 주기, 고른 이유 한 줄.

포맷은 길이로 고른다 (`formatOf`): 90초 이하면 릴스(9:16, 20~45초), 그보다 길면 롱폼(16:9).
롱폼일 때만 챕터 지침이 붙는다 — 읽을 게 적을수록 잘 따른다.

`DEFAULT_SUBTITLE_STYLE.bottom` 은 0.18 이다 (릴스·틱톡 화면 아래 UI 위로).

**용어 사전** (기획안 §5.2) — 자막을 만들 때 whisper 에 `--prompt "운동 · 재활 설명 영상. 용어: 견갑골, 외회전, …"` 를 넣는다 (`termsPrompt`).
용어는 사용자가 확인한 용어 기억(kind=term) + 완성본 메모의 용어 + 그 영상 편집안의 용어에서 모은다. 들린 말이 그래도 틀리면 에이전트가 `set_subtitle_text` 로 고치고, 사용자는 결과물 화면에서 "이 문장 고쳐줘".

**동작 시범 중의 침묵** (기획안 §5.1) — 무음이라는 이유만으로 시범을 잘라 내지 않는다. `ffmpeg-presets/motion.ts`: 화면을 160px 로 줄여 초당 4장의
앞 장과의 밝기 차이(`signalstats` YDIF)를 재고, **말하던 동안**의 중간값보다 1.4배 이상(바닥 2) 움직인 침묵은 남긴다. 절대값이 아니라 같은 영상 안에서 견주므로
카메라 · 조명이 달라도 된다. 처음부터 끝까지 똑같이 흔들리는 영상(손떨림)은 전처럼 다 자른다. 버튼(`silence` 잡) · `propose_cuts` · `find_silences` 가 같은 판단을 쓴다.

- 단위 `test/playbook.test.ts`: 포맷 고르기, 빠지면 안 되는 기준, 롱폼에만 붙는 챕터 지침, 소리 없는 영상.
- 엔진 e2e `test/e2e.agent.test.ts`: 가짜 CLI 가 시스템 프롬프트에서 style.md 와 제작 지침을 둘 다 받았는지.
