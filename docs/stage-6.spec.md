# Stage 6 — 채팅 수정 · 장면 카드 UI · 배포

## 상태 — 진행 중 (2026-09-27 시작)

`AGENTS.md §12-6`. 5단계 통과(`stage-5`, 2026-09-27, CI 녹색) 뒤에 시작한다.

```
- SwiftUI 편집안 · 장면 카드 · 채팅
- 엔타이틀먼트, .dmg, Sparkle
통과: 크리에이터가 혼자 3편을 만들고 각 편 10분 이내.
      깨끗한 Mac 에서 .dmg 드래그 → 아이콘 클릭 → 사용까지 터미널 0회
```

## 경계 — 화면은 디자인, 개발은 그 밖 (2026-09-27 사용자 지시)

- **`Madi/UI/ViewData.swift` 가 약속이다.** 개발은 `Madi/UI/**` 를 건드리지 않는다
- 개발은 UI 밖에 **엔진 → ViewData 로 바꾸는 층**을 만든다. ViewData 를 바꿔야 하면 고치지 않고 목록에 적는다
- 대응표 · 화면이 없는 엔진 상태 · 변경 요청: `docs/design/viewdata-map.md` — **디자인에 넘기는 목록**
- 화면과 상관없는 것(채팅 수정 · `.dmg` · Sparkle · 서명)은 같이 진행한다

## 작업 단위

| # | 단위 | 들어가는 곳 | 끝났다는 증거 |
|---|---|---|---|
| 1 | **design 합치기** ✅ | — | `0b8fbfc` 빌드 · 테스트 185개 |
| 2 | **대응표** ✅ | `docs/design/viewdata-map.md` | 칸마다 출처 · 화면 없는 상태 11 · 변경 요청 7 |
| 3 | **서명 · 공증 · `.dmg`** — Developer ID · Hardened Runtime · 엔타이틀먼트 · notarytool · stapler ✅ 공증 앞까지 (자격 증명 대기) | `scripts/` · `project.yml` | 공증된 `.dmg` 를 다른 계정(또는 격리 속성 붙인 채)에서 열어 Gatekeeper 통과 |
| 4 | **Sparkle** — 업데이트 확인 · EdDSA 서명 · appcast (GitHub Releases) ✅ 첫 릴리스 전까지 | `Madi/App/` · `scripts/` | 옛 판이 새 판을 찾아 설치 |
| 5 | **채팅 수정 (엔진)** — `chat` 저장소 · 수정 턴(`origin chat` · `revisionOf`) → 렌더 → 검사 · "앞으로도 이렇게 할까요?" → 사용자 규칙 ✅ (실제 Claude 수정 1회 확인) | `Madi/Agent/` · `Madi/Store/` | 가짜 CLI 테스트 · 실제 CLI 수정 1회 |
| 6 | **바꾸는 층** — DB → ViewData (값을 내는 쪽). 행동 받기는 요청 ⑦ 결정 뒤 ✅ 값을 내는 쪽 | `Madi/App/Bridge/` · `Madi/Store/LibrarySnapshot.swift` | 테스트: DB 상태마다 ViewData (`MadiBridgeTests` 7개) |
| 7 | **UI 밖 부품** — 썸네일 한 장 · 렌더 진행률 · "봤다" · 스튜디오 이름 · 내보내기(사진 앱 · Mac) · 보관 기간 · CLI 설치 · 로그인 대행 | 여러 곳 | 각자 테스트 |
| 8 | **판정** — 크리에이터 3편 · 깨끗한 Mac | — | 사람이 한다 |

## 결정

- **서명 · 공증 — 있는 Developer ID 로 (2026-09-27).** 이 Mac 에 `Developer ID Application: eunjoong kim (64YK8W88M5)`
  (2031년까지)이 이미 있다. `§2` 는 "계정은 판매 시점에, 그전엔 우클릭 → 열기" 였는데
  **macOS 15 부터 우클릭 → 열기가 막혀** 시스템 설정 > 개인정보 보호에서 따로 허용해야 한다 — `§12-6` "터미널 0회" 와
  크리에이터 부담을 생각해 지금 서명 · 공증한다. 공증 자격 증명은 사용자가 한 번 저장한다 (`notarytool store-credentials`).
  멤버십이 유효해야 공증이 된다. `§2` 문장을 고친다
- **Sparkle 업데이트 — 업데이트 전용 공개 레포 `monandoll/madi-releases` (2026-09-27).** 처음엔 소스 레포 `monandoll/madi`
  릴리스에 올리려 했는데, 거기에는 **전작 v0.2 릴리스가 `Latest`(v0.2.22)로 걸려 있어** `releases/latest` 가 전작을 가리킨다.
  업데이트용 레포를 따로 두면 전작과 섞이지 않고 소스 레포 공개 여부와도 상관없다. 릴리스에는 `.dmg` 와 `appcast.xml` 만
  (⚠ 만들다가 로그인 계정 `ejinhvn-0112` 아래에 `ejinhvn-0112/madi-releases` 가 잘못 생겼다 — monandoll 은 개인 계정이라
  협업자가 그 아래에 레포를 만들 수 없고 `gh` 가 오류 없이 로그인 계정에 만들었다. 계정을 monandoll 로 바꾸기로 했다)

### 4번 — Sparkle (2026-09-27)

- Sparkle **2.10.0** (SwiftPM, 판 고정). 하루 한 번 자동 확인 (`SUEnableAutomaticChecks` · 86400초)
- appcast: `https://github.com/monandoll/madi-releases/releases/latest/download/appcast.xml`
- **업데이트 서명 키(EdDSA)** — 공개 키는 Info.plist (`project.yml`), **비밀 키는 이 Mac 로그인 키체인(계정 `madi`)에만 있다.**
  이 키를 잃으면 이미 설치된 앱에 업데이트를 보낼 수 없다 — 백업이 필요하다 (`generate_keys --account madi -x <파일>`)
- `scripts/release.sh`: Sparkle 안쪽(XPC · `Updater.app` · `Autoupdate`)을 깊은 것부터 서명 → 공증 뒤
  `generate_appcast`(도구 위치 `MADI_SPARKLE_BIN`, Sparkle 배포본 `bin/`)로 appcast → `--publish` 일 때만 GitHub 릴리스
- 메뉴 "업데이트 확인…" 은 문구 키 `checkForUpdates` 를 디자인이 채운 뒤 붙인다 (`copy-keys.md`)
- 확인: 서명한 앱(Sparkle 포함)이 Hardened Runtime 에서 켜진다. **옛 판 → 새 판 설치 확인은 첫 릴리스 뒤**

### 5번 — 채팅 수정 실제 CLI (2026-09-27)

`madi-spike chat --kind claude --video uw1aUHnMfo8 --viewing j_claude_uw1aUHnMfo8 --text "마지막 장면은 빼고 15초 정도로 줄여 줘"`
(4 · 5단계 판정 DB 사본, 앱과 같은 큐 chat → 렌더 → 검사 → 되먹임)

| | 보고 있던 판 | 고친 판 |
|---|---|---|
| 길이/목표 · 장면 | 19.4/20초 · 6 | **15.3/15초** · 5 |
| 검사 | — | 되먹임 항목 없음 → 보여 줌 |

AI 말: "말씀하신 대로 끝의 마무리 부분을 빼서 영상이 약 15초가 됐어요. 앞부분의 옆구리 늘리기 설명과 팔 올리는 동작 시범은 그대로 두었습니다."
턴 · 렌더 · 검사 합쳐 18.2초.

~~열린 문제 — 규칙 문장~~ → 결정 ③ 으로 풀었다. "앞으로도?" 에 예면 지금은 크리에이터 말이 **그대로** 규칙이 된다
("마지막 장면은 빼고 15초 정도로 줄여 줘"). 이 영상에만 맞는 말이라 다음 영상 규칙으로는 어색하다.
AI 가 일반화한 규칙 문장을 같이 내게 할지(예: "영상은 15초 안팎으로") — 결정 ③

### 결정 ② · ③ (2026-09-28)

- **② CLI 설치 — 앱이 공식 설치 방법을 대신 돌린다. Homebrew · Node 가 필요한 방법은 뺀다** (쌤 Mac 에 없고 `§1-9` 위반)
  - Claude Code: 공식 네이티브 설치 스크립트 `https://claude.ai/install.sh` (Node 없음, 스크립트가 체크섬을 확인, `~/.local/bin`)
  - Codex: 공식 GitHub 릴리스 `openai/codex` 의 `codex-package-<aarch64|x86_64>-apple-darwin.tar.gz`
    (npm · Homebrew 는 뺐다). `codex` 와 **`codex-code-mode-host`** 가 같이 들어 있다 — MCP 도구가 코드 모드 안에서 불리므로 필요하다
  - 받은 뒤 확인: Codex 는 GitHub 가 기록한 SHA-256(`digest`)과 대조, 두 CLI 모두 **서명 팀**을 확인한다
    (Anthropic `Q6L2SF6YDW` · OpenAI `2DC432GLL2`). 판을 고정하지 않는다 — 공식 최신판을 받고 서명으로 믿는다
- **③ "앞으로도?" 규칙 문장 — AI 가 다듬은 일반 문장을 보여 주고 예/아니오. 일반화할 게 없으면 묻지 않는다**
  - `write_composition` 의 선택 칸 `rule` (채팅 수정 턴만). 도구는 2개 그대로. `madi-mcp` 가 이벤트(`agent.rule.proposed`)로 남기고 앱이 턴 뒤 읽는다
  - 실제 Claude: "앞으로는 마지막에 꼭 따라 해 보라는 말로 끝내 줘" → 규칙 "영상은 마지막에 따라 해 보라는 말로 끝낸다." 로 물음 /
    "3번 장면은 빼 줘" → 묻지 않음. 앞 요청에서 AI 는 "이번 영상에는 그런 말이 없다, 촬영할 때 넣어 달라" 고 답했다 — 자막은 전사에서만 온다

### 7번 — CLI 설치 · 로그인 대행 (2026-09-28)

`CLIInstaller` (MadiKit). 실제 설치 확인 — `madi-spike cli-install <claude|codex> --home <임시 폴더>` (이 Mac 의 기존 설치를 안 건드린다):

| | 판 | 서명 팀 | 걸린 시간 | 자리 |
|---|---|---|---|---|
| Codex | 0.157.1 | OpenAI `2DC432GLL2` ✅ | 5.8초 (약 130MB) | `codex/bin/codex` + `codex-code-mode-host` |
| Claude Code | 2.1.283 | Anthropic `Q6L2SF6YDW` ✅ | 15.4초 | `.local/bin/claude` |

- Codex 는 받은 파일의 SHA-256 을 GitHub `digest` 와 대조한 뒤, 새 폴더에 풀고 서명을 확인하고 나서 바꿔 끼운다 (반쯤 깔린 상태가 안 남는다)
- 설치 스크립트는 임시 HOME 안에만 썼다 — 진짜 홈의 셸 설정 파일은 바뀌지 않았다
- 로그인: `claude auth login --claudeai` · `codex login` 을 띄우고 브라우저 승인을 기다린다 (15분). **실제 로그인은 확인 못 했다** —
  이 Mac 은 이미 로그인돼 있고, 크리에이터 계정으로 해 봐야 한다
- 화면(첫 실행 · 설정의 연결 버튼)에 붙이는 것은 요청 ⑦(행동 입구) 뒤

### 7번 — 그림 · 진행률 (2026-09-28)

- **그림** (`Thumbnails`, 캐시 `~/Library/Caches/madi/thumbs`): 촬영본(0.5초) · 결과물(가운데, **내보낸 파일**에서) · 장면 카드(장면 원본 첫 0.2초 뒤).
  분석 뒤 · 렌더 뒤에 만든다 — 못 만들어도 진행한다. 바꾸는 층은 **있는 그림만** 넘긴다 (없으면 디자인 규칙대로 회색 자리표시)
- **진행률**: 렌더러가 0.5초마다 `AVAssetExportSession.progress` 를 읽어 메모리 게시판(`RenderProgressBoard`)에 올린다.
  만드는 중 화면 · 편집안 만드는 중(`MakingProgress.fraction`)이 읽는다. DB 에 적지 않는다
- 렌더 **출력 픽셀은 바꾸지 않았다** (알림만 더했다) — 프레임 시트는 붙이지 않았다

## 미뤄 둔 결정

| # | 결정 | 닿는 단위 |
|---|---|---|
| ① | `RootView` 행동 입구 (요청 ⑦) — 디자인 쪽 | 6 |
| ② | ~~CLI 설치~~ → 공식 설치 방법을 앱이 대신 (위) | 7 |
| ③ | ~~"앞으로도?" 규칙 문장~~ → AI 가 다듬은 일반 문장, 없으면 묻지 않음 (위) | 5 |
