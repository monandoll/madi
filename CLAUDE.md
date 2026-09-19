# 마디 (madi)

운동·재활 크리에이터를 위한 AI 영상 편집 도구.
1차 사용자는 물리치료사 겸 크리에이터 1명. 화면에 보이는 스튜디오 이름은 `workspaceName` 설정값이고 사용자가 앱에서 직접 정한다(헤더 제목 탭 → 입력). 이후 같은 도메인의 크리에이터에게 판매 가능성을 열어둔다.
사용자 PC에 설치된 **엔진**이 편집을 수행하고, **브라우저**는 그 PC를 바라보는 리모컨이다.
사용자는 편집 지식이 없다. 자연어로 요청하면 결과가 돌아온다.

## 제품 원칙 (코드 판단 기준)

1. 첫 화면은 영상 갤러리. 타임라인은 결과물 상세에서만, 그것도 자막 목록으로 대체.
2. 편집 요청은 채팅으로. 추천 칩으로 타이핑 없이도 가능해야 한다.
3. UI에 전문 용어 금지. "인코딩" → "만드는 중", "프록시" → 노출 안 함, "트랜스크립트" → "자막".
4. AI 연결은 선택. 설치 직후 AI 없이도 자막·무음 제거·규격 변환·수동 숏폼 자르기가 동작해야 한다.
5. 오류는 토스트가 아니라 채팅 안에 AI 말투로. ("이 영상은 소리가 없어서 자막을 못 만들었어요")
6. 상태는 조용하게. AI 미연결은 오류가 아니다 — 붉은색 쓰지 않는다.
7. 개인화는 전부 설정값. 사용자 이름·워크스페이스명을 코드에 박지 않는다.
8. 디자인 시안이 정답이다. `design/v2/` 의 HTML 내보내기(Mobile · Desktop · Install)를 픽셀 단위로 따른다. 임의로 컴포넌트를 "개선"하지 않는다. `design/` 바로 아래는 1차 시안(참고용).

## 아키텍처

```
[브라우저] ──HTTPS──▶ Cloudflare Tunnel ──▶ 사용자 PC
                                             └─ apps/engine (Electron, 트레이 전용)
                                                 ├─ Hono 웹 서버 (UI 정적 서빙 + REST + WebSocket)
                                                 ├─ SQLite (Drizzle) — 메타/자막/작업/스타일
                                                 ├─ 작업 큐 (SQLite 기반, 인프로세스)
                                                 ├─ 워커: ffmpeg / whisper.cpp 바이너리 스폰
                                                 ├─ 에이전트 러너: claude -p / codex exec 스폰
                                                 ├─ MCP 서버 (stdio) — 편집 도구를 에이전트에 노출
                                                 ├─ 폴더 감시 (chokidar)
                                                 └─ 사이드카: ffmpeg, whisper.cpp, cloudflared
```

- 엔진이 UI까지 직접 서빙한다. 별도 프론트 배포 없음. CORS 없음.
- AI 호출은 현재 **로컬 CLI 스폰**(사용자 본인 구독). 판매 시 "AI 포함 요금제"(API 키, 운영자 부담)를 `AgentProvider` 구현 하나로 추가한다. 두 갈래를 처음부터 인정하고 설계한다.
- 구독 CLI 연동을 유료 제품에 붙이기 전에 Anthropic·OpenAI 약관을 그 시점에 재확인한다.
- Python 없음. 미디어 처리는 전부 바이너리 스폰. TypeScript 단일 언어.
- Redis 없음. 큐는 SQLite 테이블.
- 외부 노출은 cloudflared + Cloudflare Access(이메일 OTP). 앱 자체 로그인 UI 없음.

## 스택

| 영역 | 선택 | 비고 |
|---|---|---|
| 엔진 셸 | Electron (창 없음, 트레이만) | 프로세스명 `madi-engine`, electron-builder, electron-updater, 자동 시작 |
| 웹 서버 | Hono + `ws` | 포트 `41520` 고정 |
| DB | SQLite + Drizzle ORM | `better-sqlite3` |
| 큐 | 자체 구현 (SQLite `jobs` 테이블) | 렌더 동시 1, 자막 동시 1 |
| 미디어 | ffmpeg (NVENC/VideoToolbox), whisper.cpp (CUDA/CoreML) | `packages/ffmpeg-presets` |
| 에이전트 | `claude -p --output-format stream-json`, `codex exec` | `AgentProvider` 인터페이스 뒤에 숨김 |
| UI | Vite + React + TS, Tailwind, shadcn/ui(재테마) | TanStack Query + Zustand |
| 업로드 | tus (재개 가능) | `@tus/server` |
| 공유 | zod 스키마 | `packages/shared` |
| 패키지 관리 | pnpm workspace | Node 22 |

## 레포 구조

```
apps/engine/          Electron + Hono + 큐 + 워커 + 러너 + MCP
  src/main/           Electron 진입, 트레이, 자동 업데이트, 사이드카 경로
  src/server/         Hono 라우트, WebSocket
  src/db/             Drizzle 스키마, 마이그레이션
  src/queue/          작업 큐
  src/workers/        ffmpeg, whisper, scene, subtitle
  src/agent/          AgentProvider, ClaudeProvider, CodexProvider, 러너
  src/mcp/            편집 도구 MCP 서버
  src/watch/          폴더 감시
apps/web/             Vite React (빌드 결과 → engine에 포함)
apps/site/            설치 안내 정적 페이지 (Cloudflare Pages)
packages/shared/      zod 스키마, 타입, API 계약
packages/ffmpeg-presets/  컷/크롭/자막/프록시 명령 템플릿
design/               Claude Design HTML 내보내기 (참조용, 수정 금지). v2/ 가 현재 시안
resources/bin/        플랫폼별 ffmpeg, whisper.cpp, cloudflared 바이너리 (git-lfs)
```

## 핵심 도메인 모델

- `Video` — 원본. `path`, `duration`, `kind: 'long' | 'short'`, `status`
- `Proxy` — 720p 프리뷰용. 원본 등록 시 자동 생성.
- `Transcript` — whisper 결과. 문장 단위 `Segment[]` (start, end, text, words[])
- `Edit` — 편집 결정. 원본이 아니라 **결정 목록**이다. `keep`/`parts[]`(조각을 이 순서로 — 시범 먼저, 설명 뒤), `cuts[]`, `crop`+`cropFocus`(세로일 때 어디를 잡을지, null 이면 렌더가 움직임으로 고르고 다시 적는다), `subtitleStyle`+`subtitleAuto`(아래 동작을 가리면 위로), `emphasis[]`(강조할 단어 · 구간), `revisionOf`(결과물이 있는 Edit 를 고치면 새 Edit — 이전 결과물은 계속 재현된다), `speed[]`
- `Output` — `Edit`를 렌더한 결과 파일. `Video`에 여러 개 매달림.
- `Job` — 큐 항목. `type`, `status`, `progress`, `payload`, `error`
- `StyleProfile` — `style.md`(자연어 규칙) + `params.json`(숫자) + `examples/`(few-shot)
- `Reference` — 완성본(배우는 대상). `stats`(숫자 + 장면 전환 시각) + `segments`(자막) + `insight`(AI 가 읽은 뜻: 취지·구성·보존 구간·숏폼 후보·용어·제목과 내용의 관계·태그)
- `TermCorrection` — 자막에서 고친 말 한 쌍(틀린 말 → 바른 말 · 횟수). 바른 말은 whisper 에 알려 주고, 2번 이상이면 결과에서 바로 바꾼다. 사용자가 뺄 수 있다.
- `Memory` — 제작자 기억 한 줄. `kind`(style·keep·avoid·term) · `scope`(all·topic·video) · `source`(reference·feedback·user) · `status`(proposed·approved). 완성본에서 추린 것은 **제안**으로 들어오고 사용자가 확인한 것만 편집에 쓴다. 사용자가 보고 고치고 지운다. 완성본은 `excluded` 로 학습에서 뺄 수 있다.
- `EditPlan` — 촬영본 편집안 초안. AI 가 자막·무음·움직임·장면을 읽고 남긴 취지·구성(구간별 편집 초안)·남길 구간·잘라낼 후보·숏폼 후보(채널·이유). 파일은 만들지 않는다 — 사용자가 후보를 골라야 렌더. `feedback[]` 에 사용자가 뺀·만든 후보가 남고, 뺀 것은 다시 제안하지 않는다.
- `Chat` — `Video`별 대화. 메시지에 `Output` 카드가 붙는다.

원칙: **렌더는 항상 `Edit`로부터 재현 가능**해야 한다. 결과 파일만 있고 결정이 없는 상태를 만들지 않는다.

## AI 에이전트 규칙

- 에이전트는 파일을 직접 만지지 않는다. MCP 도구만 호출한다.
- 도구 목록 (`apps/engine/src/mcp/tools.ts`): `get_transcript`, `find_silences`, `find_scenes`, `propose_cuts`, `apply_edit`, `render`, `extract_shorts`, `get_chapters`, `set_subtitle_style`, `set_subtitle_text`, `update_style_rule`
- 에이전트 컨텍스트에 `StyleProfile.style.md`를 항상 주입한다.
- 그 위에 **제작 지침**(`src/agent/playbook.ts`)과 **기억**(`styleService.recall(video)` — 이 영상과 관련 있는 것만)을 같이 넣는다. 세기 순서는 사용자가 쓴 규칙 > 기억 > 제작 지침.
- 완성본은 AI 가 연결돼 있으면 자막을 읽어 `insight` 를 남기고(insight 잡, 도구 없는 한 턴), 여러 편에 반복되는 것만 `Memory` 로 **제안**한다. 사용자가 승인하지 않은 것을 영구 성향으로 확정하지 않는다 — 프롬프트에는 `approved` 만 들어간다. 영상을 매번 다시 읽지 않는다 — 저장한 메모만 꺼낸다.
- 쉬는 구간 자르기(버튼 · `propose_cuts`)는 동작이 이어지는 침묵(시범)을 남긴다. 말하던 때보다 화면이 확실히 더 움직인 침묵은 자르지 않는다 (`ffmpeg-presets/motion.ts`).
- 세로 크롭 초점과 자막 위치는 렌더가 화면의 어느 쪽이 움직이는지 한 번 재서 정하고(`regionsFor` · `chooseCropFocus` · `chooseSubtitleSide`) 그 결정을 `Edit` 에 적는다. 에이전트는 `apply_edit.focus` / `set_subtitle_style.bottom` 으로 덮어쓸 수 있다.
- AI 가 골라져 있으면 상세를 처음 열 때 `plan` 잡으로 편집안을 읽어 카드로 붙인다 (`src/plan/`). 다음 채팅 요청에는 그 편집안이 같이 간다.
- 편집안 · 완성본 메모에는 대표 프레임 시트(장면 전환 직후 화면을 4칸 격자로, 최대 2장)도 같이 보여 준다 (`ffmpeg-presets/frames.ts`, `workers/frames.ts`). Claude 는 `Read(./sheets/**)` 만 열어 주고, Codex 는 `-i` 로 붙인다. 설정 `ai.frames` 로 끈다. 자세를 판정하지 않는다.
- 수정 요청이 오면 고친 뒤 **"앞으로도 이렇게 할까요?"** 를 한 번 묻고, 예일 때만 `update_style_rule`.
- 에이전트 응답은 채팅에 스트리밍. 도구 호출 내부는 사용자에게 보이지 않는다.
- AI 미연결 상태에서는 러너를 아예 스폰하지 않는다. 버튼 4개는 워커를 직접 호출한다.

## 디자인 토큰 (Tailwind 설정에 그대로 · `design/v2` 기준)

```
bg/surface  #FFFFFF   side #F3F5F7 (사이드바·첫 실행 배경)   surface-2 #F7FAFC
line        #E0E6EB   line-2 #E7ECF0   line-soft #EAEFF3   line-faint #EDF2F6   input #D9E1E7
text        #1C2127   text-2 #5E6872   text-3 #8A939C   text-4 #4E5862 (칩)   muted #9AA3AC
accent      #3E6B8A   accent-hover #2F5470   accent-soft #E4EEF5   accent-faint #EEF5FA
select      #DFE7ED (사이드바 활성)   hover #EDF2F6   ok #7A9E7E   off #D2DAE1   busy #D9A441   error #B85C5C
thumb       #E6EAEE / #DBE1E6 / #CDD5DB   track #E7ECF0   overlay rgba(22,26,31,.72) (길이 배지·자막)
font        Pretendard Variable (self-host)   sizes 10/11/12/13/14/15/16/20/26
radius      6px(사이드바 줄) 8px(카드·버튼·썸네일) 10px(패널·칩 바·폰 버튼) 12px(첫 실행 카드) 999px(칩·알약)
shadow      없음. 구분은 1px 선.
레이아웃    900px 이상 = PC(왼쪽 252px 사이드바 + 화면 + 오른쪽 380px 결과물 패널), 미만 = 모바일(화면 + 아래 탭 3개)
```

## 개발 규칙

- 커밋 단위는 작게. 화면 하나 또는 워커 하나.
- 새 기능은 `packages/shared`의 zod 스키마부터. 엔진과 UI가 같은 타입을 쓴다.
- 워커는 순수 함수 + 스폰. 테스트는 짧은 샘플 영상(`fixtures/`, 5초)으로.
- ffmpeg 명령은 문자열 조립 금지. `packages/ffmpeg-presets`의 빌더 사용.
- UI 문구는 `apps/web/src/copy.ts` 한 파일에. 하드코딩 금지.
- 에러 문구도 `copy.ts`. AI 말투로.
- 로그는 `~/.madi/logs/`. 사용자에게 로그 경로를 노출하지 않는다.
- 사용 이벤트(요청 종류, 횟수, 소요 시간)를 로컬 SQLite `events` 테이블에 기록한다. 외부 전송 없음. 판매 판단 근거로 쓴다.
- `design/`은 읽기 전용. UI 구현 시 해당 HTML을 먼저 열어 구조·간격·문구를 확인한다.

## 명령

```
pnpm i
pnpm dev            # engine(개발 모드) + web(HMR) 동시
pnpm dev:web        # web만 (engine은 별도 실행)
pnpm build          # web 빌드 → engine 리소스 복사 → electron-builder
pnpm test
pnpm db:migrate
pnpm db:studio
```

## 개발 단계 (현재: 6 완료 — 이후는 사용 피드백으로 정한다)

1. **갤러리** — 폴더 감시 → 프록시·썸네일 → 갤러리 화면. "설치하면 영상이 뜬다".
2. **AI 없는 편집** — whisper 자막, 무음 제거, 9:16 크롭, 수동 숏폼 → 상세 패널 미연결 상태 완성.
3. **패키징** — electron-builder, cloudflared, 자동 업데이트. 2단계 직후에 한다. 미루지 않는다.
4. **AI 연결** — 러너 + MCP + 설정의 AI 연결 → 채팅 편집. 이때 `design/Setup.dc.html`(첫 실행 카드·설정 화면 초안)을 실제 설정 시안과 합치고 AI 연결 항목을 넣는다.
5. **스타일 학습** — 기존 영상 분석 → `StyleProfile`, 원본+완성본 쌍 diff, 피드백 루프.
6. **롱폼** — 챕터 나누기, 숏폼 자동 추출.

## 하지 않는 것 (지금은)

- SaaS 배포, 다중 사용자, 계정 시스템, 텔레메트리 전송 — 설계상 막지는 않되 구현하지 않는다
- API 키 방식 AI 호출 — `AgentProvider` 구현 추가로 대응 가능하게만 둔다
- 범용 편집 도구화. 타깃은 운동·재활 크리에이터로 고정한다
- 타임라인 편집기, 트랙, 키프레임
- 브라우저 내 영상 처리 (ffmpeg.wasm 등)
- 다크 모드

## 타깃 환경

- 1차 타깃은 **선생님 PC 한 대**. OS와 GPU는 `docs/target-machine.md`에 기록. 그 조합의 바이너리만 우선 빌드.
- 지원 브라우저: 최신 Chrome/Safari. 모바일은 375 기준 갤러리·상세·결과물 3화면만.
