# 마디 (madi) — 운동·재활 크리에이터를 위한 AI 숏폼 편집 도구

전작(`monandoll/madi` v0.2.x)을 버리고 다시 만든다. 코드를 옮겨 오지 않는다.
전작이 실패한 이유는 인프라가 아니라 **편집을 표현하는 자료구조**였다. 그 결론을 이 문서 전체가 전제한다.

1차 사용자는 물리치료사 겸 숏폼 크리에이터 1명(팔로워 12만, 인스타 릴스 · 유튜브 숏츠 · 틱톡 동시 운영).
편집 지식이 없다. 타임라인을 못 읽는다. 자연어로 요청하면 **바로 업로드 가능한 영상**이 나와야 한다.
목표는 "AI가 도와준다"가 아니라 **편집 2~3시간 → 10분**이다. 이 수치가 유일한 성공 기준이다.

---

## 0. 전작에서 배운 것 (반복 금지 목록)

이 6개는 실측으로 확인된 실패 원인이다. 코드 리뷰 때 이 목록을 기준으로 거절한다.

| # | 전작이 한 것 | 왜 망했나 | 이번 규칙 |
|---|---|---|---|
| 1 | `Edit = {keep, parts, cuts, crop, subtitles}` | 표현 가능한 편집이 트림·크롭·자막뿐. 줌·BGM·효과음·오버레이·훅카드가 **구조적으로 불가능**. AI가 아무리 똑똑해도 출력 어휘가 없었다 | 코어 자료구조는 `Composition`(장면 · 레이어 · 키프레임). 편집 어휘를 먼저 넓히고 AI를 붙인다 |
| 2 | 9:16 크롭이 `cropFocus: number` 하나 (정적 x좌표) | 인물이 화면 구석에 작게 박힘. 숏폼에서 피사체가 작으면 그 시점에 끝난 영상 | 리프레이밍은 **사람 bbox 추적 기반 시간축 키프레임**. 1단계 기능이다 |
| 3 | 자막을 ASS(`buildAss`)로 번인. whisper 문장 통째로, `fontSize:56` on 1080 | 화면 폭의 5%짜리 자막. 딱 봐도 자동 생성 자막 | 자막은 **React 컴포넌트**. 분절·크기·모션·외곽선은 템플릿이 강제 |
| 4 | 스타일을 `style.md` 자연어 규칙으로 두고 AI가 매번 해석 | 같은 요청에 매번 다른 결과. 일관성이 없으면 "내 채널 영상"이 아니다 | **스타일은 코드 자산**. AI는 스타일 값을 쓸 수 없다. 슬롯만 채운다 |
| 5 | 완성본(Reference)에서 스타일을 "학습" | 완성본은 자막·효과가 번인되어 있어 파라미터 역추출 불가. 원본↔완성본 쌍이 없으면 델타를 못 배움 | 학습하지 않는다. 사람이 릴스 5편 보고 템플릿을 **손으로 쓴다**. 10배 정확하고 100배 싸다 |
| 6 | 렌더 결과를 아무도 다시 안 봄 | "처참하다"는 걸 코드가 모름. 품질 기준이 코드에 없었다 | `§8 품질 게이트` + `§7 self-eval`이 1단계부터 들어간다 |

추가로 버리는 것: MCP 도구 12개(→2개), `Memory` 승인 플로우, `Reference.insight`, `TermCorrection` 자동 치환, "AI 없이도 동작" 이중 경로(유지비만 컸다).

---

## 1. 제품 원칙 (코드 판단 기준)

1. **결과가 바로 올릴 수 있어야 한다.** "고치면 쓸 만함"은 실패다. 사용자는 CapCut을 다시 열지 않아야 한다.
2. **스타일은 자산, 콘텐츠는 AI.** 폰트·색·크기·모션·자막 위치를 AI가 정하면 버그다.
3. **장면 단위로 보여준다.** 풀 타임라인 편집기는 만들지 않지만, 장면 카드(썸네일 + 자막 + 길이)는 반드시 보여준다. 전작은 "자막 목록"으로 대체했다가 사용자가 틀린 곳을 짚을 방법이 없었다.
4. **AI는 자기 결과를 본다.** 렌더 → 프레임 추출 → 재검사 → 수정. 사람에게 보여주기 전에 최소 1회.
5. UI에 전문 용어 금지. "인코딩"→"만드는 중", "컴포지션"→"편집안", "리프레임"→"화면 잡기".
6. 오류는 토스트가 아니라 채팅 안에 AI 말투로. 상태는 조용하게, 붉은색은 진짜 실패에만.
7. 개인화는 전부 설정값. 사용자 이름·워크스페이스명을 코드에 박지 않는다.
8. **렌더는 항상 `Composition`으로부터 재현 가능**해야 한다. 결과 파일만 있고 결정이 없는 상태를 만들지 않는다.

---

## 2. 아키텍처

```
[브라우저 = 리모컨] ──HTTPS──▶ Cloudflare Tunnel ──▶ 사용자 PC
                                                     └─ apps/engine (Electron, 트레이 전용)
                                                         ├─ Hono 웹 서버 (UI 정적 서빙 + REST + WS)
                                                         ├─ SQLite (Drizzle) — 미디어/다이제스트/컴포지션/작업
                                                         ├─ 작업 큐 (SQLite 기반, 인프로세스)
                                                         ├─ 분석 워커  → Digest
                                                         │    whisper.cpp / 사람감지(onnx) / silence / scene / frames
                                                         ├─ 렌더 워커  → Composition → mp4
                                                         │    ffmpeg(클립) → Remotion(합성) → ffmpeg(먹싱)
                                                         ├─ 검수 워커  → 품질 게이트 + self-eval
                                                         ├─ 에이전트 러너 — claude -p / codex exec 스폰
                                                         ├─ MCP 서버 (stdio) — 도구 2개
                                                         └─ 사이드카: ffmpeg, whisper.cpp, onnxruntime, cloudflared
```

- 엔진이 UI까지 직접 서빙. 별도 프론트 배포 없음. CORS 없음.
- AI 호출은 **로컬 CLI 스폰**(사용자 본인 Claude/Codex 구독). 판매 시 API 키 방식은 `AgentProvider` 구현 하나 추가로 대응한다. 두 갈래를 처음부터 인정하고 설계한다.
- 구독 CLI를 유료 제품에 붙이기 전에 Anthropic·OpenAI 약관을 그 시점에 재확인한다.
- Python 없음. 미디어·추론 전부 바이너리/onnxruntime-node 스폰. TypeScript 단일 언어.
- Redis 없음. 큐는 SQLite 테이블.
- 외부 노출은 cloudflared + Cloudflare Access(이메일 OTP). 앱 자체 로그인 UI 없음.

---

## 3. 스택

| 영역 | 선택 | 비고 |
|---|---|---|
| 엔진 셸 | Electron (창 없음, 트레이만) | 프로세스명 `madi-engine`, electron-builder, electron-updater, 자동 시작 |
| 웹 서버 | Hono + `ws` | 포트 `41520` 고정 |
| DB | SQLite + Drizzle ORM | `better-sqlite3` |
| 큐 | 자체 구현 (SQLite `jobs`) | 렌더 동시 1, 분석 동시 1 |
| 트림·인코딩 | ffmpeg (NVENC / VideoToolbox) | `packages/media` |
| 합성 | **Remotion** (React) | 자막·오버레이·모션. 라이선스는 `§13` 확인 |
| 전사 | whisper.cpp (CUDA / CoreML), word timestamps 필수 | |
| 사람 감지 | onnxruntime-node + YOLOv8n-pose (또는 `@vladmandic/human`) | bbox + 17 keypoint, 0.5s 간격 |
| 에이전트 | `claude -p --output-format stream-json`, `codex exec` | `AgentProvider` 뒤에 숨김 |
| UI | Vite + React + TS, Tailwind, shadcn/ui(재테마) | TanStack Query + Zustand |
| 업로드 | tus (재개 가능) | `@tus/server` |
| 공유 | zod 스키마 | `packages/shared` |
| 패키지 관리 | pnpm workspace | Node 22 |

---

## 4. 레포 구조

```
apps/engine/            Electron + Hono + 큐 + 워커 + 러너 + MCP
  src/main/             Electron 진입, 트레이, 자동 업데이트, 사이드카 경로
  src/server/           Hono 라우트, WebSocket, 업로드, 미디어 서빙
  src/db/               Drizzle 스키마, 마이그레이션
  src/queue/            작업 큐
  src/analyze/          Digest 생성 (transcript · subject · audio · scene · frames)
  src/render/           Composition → 클립 트림 → Remotion 렌더 → 먹싱
  src/review/           품질 게이트(코드 측정) + self-eval(AI 재검사)
  src/agent/            AgentProvider, Claude/Codex, 러너, 프롬프트 조립
  src/mcp/              MCP 서버 (도구 2개)
  src/watch/            폴더 감시 (chokidar)
apps/web/               Vite React — 갤러리 · 편집안 · 장면 카드 · 채팅
apps/site/              설치 안내 정적 페이지 (Cloudflare Pages)
packages/shared/        zod 스키마 (Composition · Digest · Job · API 계약)
packages/media/         ffmpeg 명령 빌더, probe, 인코더 선택, 프레임 시트
packages/templates/     ★ 스타일 자산. Remotion 컴포지션 + 토큰 + spec
  suhyun.short.v1/
    index.tsx           Remotion 루트
    tokens.ts           폰트 · 색 · 크기 · 모션 상수 (AI 접근 불가)
    layout.ts           role/slot 별 좌표 규칙, 리프레임 목표치
    spec.json           AI에게 보여줄 "이 템플릿이 지원하는 것" 목록
    reference/          참고한 실제 릴스 캡처 (사람이 보고 맞춘 근거)
resources/bin/          플랫폼별 ffmpeg, whisper.cpp, onnx 모델, cloudflared (git-lfs)
fixtures/               5초 샘플 영상, fake-claude/codex/cloudflared
docs/                   shooting.md(촬영 규칙), quality.md, style-authoring.md, packaging.md
```

---

## 5. 코어 도메인 모델

`packages/shared/src/composition.ts`. 모든 필드는 zod. 엔진과 UI와 AI가 같은 스키마를 쓴다.

```ts
Composition {
  id, videoId, templateId: string, templateVersion: number
  size: { w: 1080, h: 1920 }, fps: 30
  meta: { title, platform: 'reels'|'shorts'|'tiktok', targetDurationSec: number }
  scenes: Scene[]
  audio: {
    bgm?: { assetId, gainDb, duckDb }        // 말할 때 자동 덕킹
    sfx: { assetId, at, gainDb }[]
  }
  revisionOf: string | null                   // 결과물이 있는 컴포지션은 제자리 수정 금지
  createdAt: number
}

Scene {
  id
  role: 'hook' | 'demo' | 'explain' | 'cta' | 'filler'   // 템플릿이 role별로 다르게 그린다
  source: { videoId, in: number, out: number }           // 원본 초
  speed: number                                          // 기본 1. 0.5=슬로우, 1.5=빠르게
  reframe: {
    mode: 'auto' | 'fixed' | 'keyframes'
    keyframes: { t: number, rect: { x, y, w, h } }[]     // 원본 정규화 좌표. auto면 렌더가 채워 되쓴다
    padding: number                                      // 피사체 여백 비율
  }
  captions: Caption[]
  overlays: Overlay[]
  transitionIn: 'cut' | 'fade' | 'whip' | 'zoom'
}

Caption {
  id, start: number, end: number      // 장면 로컬 초
  text: string                        // 2~7자 분절된 한 덩어리. 문장 통째로 넣지 않는다
  secondary?: string                  // 영문 등 보조 문구
  emphasis: { from: number, to: number }[]   // text 내 문자 인덱스
  slot: 'main' | 'top'                // 실제 좌표는 템플릿이 결정
}

Overlay {
  id, kind: 'titleCard'|'arrow'|'circle'|'image'|'counter'|'progress'
  start, end
  anchor: { x: number, y: number }    // 0..1 정규화
  payload: Record<string, unknown>    // kind별. spec.json이 스키마를 정의
}
```

**AI가 쓸 수 없는 것**: 폰트, 색, 글자 크기, 자막 절대 좌표, 애니메이션 곡선, 외곽선 두께.
이 값들이 `Composition`에 나타나면 **스키마 검증에서 거절**한다. 그런 필드를 추가하지 않는다.

기타 테이블:

- `Video` — 원본. `path`, `duration`, `kind: 'raw'|'reference'`, `status`
- `Proxy` — 720p 프리뷰
- `Digest` — `§6` 산출물 (JSON + 팩된 텍스트 + 프레임 시트 경로)
- `Output` — 컴포지션 렌더 결과 파일. `compositionId`, `reviewReport`
- `Job` — `type`, `status`, `progress`, `payload`, `error`
- `Chat` — `Video`별 대화. 메시지에 `Output` 카드가 붙는다

---

## 6. 분석 파이프라인 — Digest

AI가 영상을 "읽는" 유일한 창구. 영상을 프레임으로 통째로 넣지 않는다. 팩된 텍스트 + 소수 이미지.

워커 5개가 병렬로 돌고 하나의 `digest.md`로 합쳐진다.

1. **transcript** — whisper.cpp, **word-level timestamp 필수**. 문장 단위로 묶어 표기
2. **subject** — 0.5s 간격 사람 bbox + keypoint. 리프레이밍 근거이자 "시범 중 / 말하는 중" 판정 근거
3. **audio** — 무음 구간, RMS 곡선 요약
4. **scene** — ffmpeg scene score 기반 컷 지점
5. **frames** — 씬 전환 직후 프레임을 4칸 격자로, 최대 2장

```
# VIDEO v_01   duration 182.4s   1920x1080   30fps   audio: yes

## TRANSCRIPT
[002.52-005.36] 오늘은 거북목 스트레칭 알려드릴게요
[005.80-008.11] 이거 하나만 해도 목이 진짜 편해져요

## SUBJECT  (0.5s, 정규화 xywh, pose)
002.5  0.41 0.22 0.18 0.62  .97  standing
003.0  0.40 0.21 0.19 0.63  .96  standing
...
(요약) 인물 평균 화면 점유 높이 0.61 · 좌우 이동 0.12 · 12.4s~19.8s 바닥 자세

## AUDIO
silence 012.4-014.1 (1.7s)   silence 041.0-041.9 (0.9s)

## SCENES
cut 031.2  cut 058.9

## FRAMES
sheets/v_01_0.png   (000s / 031s / 059s / 090s)
```

규칙:
- **동작을 추측하지 않는다.** 자막만 보고 "이때 스트레칭 중"이라고 쓰지 않는다. `SUBJECT`와 `FRAMES`로 확인한다.
- 다이제스트는 캐시한다. 원본이 바뀌지 않으면 재생성하지 않는다.
- 사용자가 `ai.frames=false`로 끄면 `FRAMES` 섹션을 뺀다.

---

## 7. 렌더 파이프라인

```
Composition
   │
   ├─ 1. plan      장면별 필요한 원본 구간 계산, reframe.mode='auto'면 키프레임을 채워 되쓴다
   ├─ 2. clips     ffmpeg: 장면별 trim + speed + reframe crop → 1080x1920 무자막 클립
   ├─ 3. compose   Remotion: 클립 + 자막 + 오버레이 + BGM/SFX → out.mp4
   ├─ 4. mux       ffmpeg: 최종 인코딩(NVENC/VideoToolbox), +faststart
   ├─ 5. gate      §8 품질 게이트 코드 측정
   └─ 6. self-eval 실패 항목이 있으면 프레임 시트 + 게이트 리포트를 AI에 되먹임
                   → Composition 수정 → 2번부터 재실행 (최대 2회)
```

- ffmpeg 명령은 **문자열 조립 금지**. `packages/media`의 빌더만 쓴다.
- 자막을 ffmpeg으로 그리지 않는다. `drawtext`, `subtitles`, ASS 전부 금지.
- 리프레임 키프레임은 스무딩한다(0.4s 저역통과). 프레임이 떨리면 즉시 실패.
- 3번은 Remotion 렌더 서버를 재사용한다. 매 렌더마다 Chromium을 새로 띄우면 10분 목표를 못 맞춘다.
- 중간 산출물은 `~/.madi/work/<compositionId>/`. 성공 시 정리, 실패 시 남긴다.

---

## 8. 품질 게이트

`src/review/gate.ts`. **코드로 측정한다.** AI 판단에 맡기지 않는다.
`Output.reviewReport`에 항목별 pass/fail + 측정값을 남긴다.

| # | 항목 | 기준 |
|---|---|---|
| G1 | 피사체 크기 | 인물 bbox 높이 >= 프레임 높이 55% 인 구간이 전체 길이의 80% 이상 |
| G2 | 피사체 잘림 | 머리 상단·발목 keypoint가 프레임 밖으로 나가는 구간 5% 이하 |
| G3 | 리프레임 안정 | 인접 키프레임 간 중심 이동 <= 프레임 폭의 3%/frame |
| G4 | 자막 크기 | 글자 높이 >= 프레임 높이 **3.2%** (실측 3.7% 에 여유 -15%. `docs/findings/2026-09-23-reference-measurement.md`) |
| G5 | 자막 분절 | 한 덩어리 <= 13자, 2줄 이내 (실측: 12자까지 한 줄) |
| G6 | 자막 싱크 | 캡션 start와 대응 word start 오차 <= 0.15s |
| G7 | 자막 가림 | 자막 박스가 어깨선 위 keypoint를 덮지 않음 |
| G8 | 훅 | 0~1.5초 구간에 `role:'hook'` 장면 또는 titleCard 존재 |
| G9 | 정적 구간 | 무음 + 저모션이 1.2초 이상 이어지는 구간 없음 |
| G10 | 컷 리듬 | 장면 길이 중앙값 1.5~4.0초 |
| G11 | 길이 | `meta.targetDurationSec` ±15% |
| G12 | 오디오 | 클리핑 없음, LUFS -16 ~ -13, BGM 덕킹 동작 |

- G1, G4, G6은 **하드 게이트**. 실패하면 사용자에게 보여주지 않고 self-eval로 되돌린다.
- 나머지는 소프트. 리포트에 남기고 채팅에서 한 줄로 알린다.
- 템플릿이 기준을 덮어쓸 수 있다 (`spec.json.gateOverrides`). 단 하드 게이트는 덮어쓸 수 없다.

---

## 9. 스타일 템플릿 규약

**스타일은 학습하지 않는다. 사람이 쓴다.** 절차는 `docs/style-authoring.md`.

1. 크리에이터 실제 릴스 5편을 프레임 캡처해 `reference/`에 넣는다
2. 자막 폰트·크기·외곽선·위치·분절 길이·등장 모션을 눈으로 재서 `tokens.ts`에 적는다
3. 훅 레이아웃, role별 화면 구성, 리프레임 목표 점유율을 `layout.ts`에 적는다
4. `spec.json`에 AI가 쓸 수 있는 role·slot·overlay kind와 각 payload 스키마를 적는다
5. `reference/` 중 1편을 손으로 `Composition`으로 재현해 렌더하고 원본과 나란히 본다 → **이게 통과 기준**

`suhyun.short.v1` 기준값 (실제 채널 관측):

```
자막 본문   Pretendard ExtraBold, 폭 88% 이내, 흰색 #FFFFFF,
            외곽선 검정 8px, 하단 26% 지점, 2~7자 분절, pop-in 100ms ease-out
자막 보조   영문, 노란색 이탤릭, 본문 바로 아래, 본문의 0.55배
훅          0~1.2초, 상단 대형 텍스트 + 줌 1.00→1.06
리프레임    인물 bbox 높이가 프레임 높이의 72%를 채우도록, 스무딩 0.4s
BGM         -22dB, 말하는 구간 -6dB 추가 덕킹
```

전작의 기본값(노란 박스 `#E8C33F`, 56px)은 **디자인 시안 색이었지 크리에이터 스타일이 아니었다.** 같은 실수를 반복하지 않는다.

---

## 10. AI 에이전트 규칙

### 도구는 2개뿐

`apps/engine/src/mcp/tools.ts`

| 도구 | 하는 일 |
|---|---|
| `read_digest(videoId)` | `§6` 다이제스트 텍스트 반환. 프레임 시트는 MCP 이미지 블록으로 동봉 |
| `write_composition(json)` | zod 검증 후 저장. 실패하면 에러 메시지를 그대로 돌려줘 고치게 한다 |

- **`render`는 AI가 호출하지 않는다.** 컴포지션이 저장되면 큐가 렌더한다.
- 도구를 늘리고 싶어지면 먼저 "이게 없으면 AI가 뭘 못 하나"를 적는다. 대부분은 프롬프트나 템플릿 문제다.
- 에이전트는 파일을 직접 만지지 않는다. 읽기는 `sheets/**`만 허용.

### 컨텍스트 조립 순서 (`src/agent/prompt.ts`)

```
1. 제작 지침 (playbook)          — 숏폼 편집 일반 규칙. 고정
2. 템플릿 spec.json               — 쓸 수 있는 role · slot · overlay와 payload 스키마
3. 품질 게이트 요약 (§8)          — 지켜야 할 수치
4. 사용자 규칙 (설정에서 직접 쓴 것)
5. digest                         — read_digest 결과
6. 대화 이력 / 수정 요청
```

세기 순서: **사용자 규칙 > 템플릿 spec > 품질 게이트 > 제작 지침.**

### 동작 규칙

- 첫 진입: 다이제스트 생성 → AI 1턴 → `Composition` 초안 → 장면 카드로 표시. **자동 렌더하지 않는다.** 사용자가 고르면 렌더.
- 수정 요청은 항상 새 `Composition`(`revisionOf`)을 만든다. 이전 결과물도 계속 자기 컴포지션으로 재현 가능해야 한다.
- 수정 요청이 오면 고친 뒤 **"앞으로도 이렇게 할까요?"**를 한 번 묻고, 예일 때만 사용자 규칙에 적는다.
- self-eval 턴은 사용자에게 보이지 않는다. 게이트 리포트 + 프레임 시트를 주고 컴포지션만 고치게 한다. 설명 문장을 요구하지 않는다.
- 응답은 채팅에 스트리밍. 도구 호출 내부는 노출하지 않는다.
- AI 미연결 상태에서는 러너를 스폰하지 않는다. 이때 UI는 "AI를 연결하면 편집안을 만들어요" 한 줄만 보여준다. **AI 없는 편집 경로를 따로 만들지 않는다.**

---

## 11. 촬영 규칙 (docs/shooting.md)

편집 난이도를 낮추는 가장 싼 방법은 촬영을 규칙화하는 것이다. 크리에이터에게 A4 한 장으로 준다.

- 가로가 아니라 **세로로**, 인물이 화면 높이의 70% 이상 차지하게
- 순서 고정: 훅 멘트 → 동작 시범 3회 → 마무리 한마디
- 각 블록 시작 전에 **1초 정지**. 컷 경계가 된다
- 실수하면 **박수 한 번** 치고 다시. 박수 = "직전 테이크 버려" 신호로 자동 인식
- 배경은 단색 벽. BGM은 나중에 넣으니 현장에서 틀지 않는다

이 규칙을 지킨 촬영본은 AI 판단이 90% 줄어든다. 지키지 않은 촬영본도 동작해야 하지만, 품질은 보장하지 않는다.

---

## 12. 개발 단계

각 단계는 **통과 조건을 만족하기 전에 다음으로 가지 않는다.** 전작은 이 게이트가 없어서 6단계까지 갔는데 0단계를 통과하지 못한 상태였다.

**0. 렌더러 스파이크** (AI 없음, DB 없음, UI 없음)
크리에이터 실제 릴스 1편을 손으로 `Composition` JSON 작성 → Remotion 렌더.
- 통과: 원본과 나란히 놓고 **자막·구도·리듬이 같은 채널 영상으로 보인다**
- 실패 시 여기서 멈추고 컴포지터를 다시 고른다. 절대 다음으로 가지 않는다

**1. 리프레이밍**
사람 감지 워커 → bbox 트랙 → 키프레임 → 클립 렌더.
- 통과: G1 · G2 · G3 통과. 전작 출력과 before/after 비교 이미지

**2. 템플릿 + 자막**
`suhyun.short.v1` 완성, 자막 분절 규칙, 강조.
- 통과: G4 · G5 · G6 · G7 통과

**3. 파이프라인 연결**
폴더 감시 → 다이제스트 → 큐 → 렌더 → 갤러리. AI 없이 수동 Composition으로.
- 통과: 원본 넣고 3분 안에 무자막 아닌 완성 영상이 나온다

**4. AI 1턴**
러너 + MCP 2도구 + 프롬프트 조립.
- 통과: 새 촬영본에서 사람 손 없이 게이트 하드 3개 통과

**5. self-eval 루프**
게이트 실패 → 되먹임 → 재렌더.
- 통과: 10편 중 8편이 1회 되먹임 안에 하드 게이트 통과

**6. 채팅 수정 + 장면 카드 UI**
- 통과: 크리에이터가 혼자 3편을 만들고, **각 편 10분 이내**

**7. 패키징**
electron-builder, cloudflared, 자동 업데이트. 전작 설정 이식.

**8. 롱폼**
챕터 분리, 숏폼 자동 추출, 롱폼 구성 채팅.
- 6단계 통과 전에는 시작하지 않는다. 숏폼이 안 되는데 롱폼을 붙이면 실패 면적만 넓어진다

---

## 13. 라이선스 확인 사항

- **Remotion — 확인 완료 (2026-09-23). 무료 라이선스로 진행한다.**
  - Remotion은 source-available 자체 라이선스(OSI 오픈소스 아님). Free License 대상은 "개인" 또는 "직원 3인 이하 영리조직" 또는 비영리. **개인은 상업적 사용·수익화 모두 무료.**
  - 이 앱처럼 "사용자가 자신의 영상을 템플릿 기반으로 만들고 렌더하게 하는 것"은 공식 FAQ가 허용 예시로 명시.
  - 금지: Remotion 자체를 파생·재판매, 사용자가 **자기 Remotion 코드를 올려서** 렌더하게 하는 서비스. 우리는 둘 다 아니다.
  - **스케일 리스크**: 인원이 4명이 되는 순간 Company License. 이 제품은 "Remotion for Automators"(렌더당 $0.01, 월 최소 $100)에 해당한다. **사람을 뽑기 전에 다시 계산한다.**
  - Electron 바이너리에 번들하는 것에 대한 명시 조항은 공식 문서에 없음. "Remotion으로 영상을 만드는 것"에 해당한다고 보지만 문서화되어 있지 않다. 판매 시작 전에 한 번 더 확인한다.
  - 대안 유지: Motion Canvas는 현재 MIT(2024년 GPLv3 전환 논의가 있었으므로 의존할 버전의 LICENSE를 그때 확인). Remotion 조건이 바뀌면 이쪽.
- **폰트**: Pretendard(OFL) 자체 호스팅. 다른 폰트를 쓰려면 번들 가능 여부를 먼저 본다.
- **BGM/SFX**: 기본 제공 음원은 상업 이용 가능한 것만. 출처를 `resources/audio/LICENSE.md`에 남긴다.
- **구독 CLI**: 유료 제품에 붙이기 전 Anthropic·OpenAI 약관 재확인.

---

## 14. 개발 규칙

- 커밋 단위는 작게. 워커 하나 또는 화면 하나.
- 새 기능은 `packages/shared`의 zod 스키마부터. 엔진·UI·AI가 같은 타입을 쓴다.
- ffmpeg 명령은 문자열 조립 금지. `packages/media` 빌더만.
- 자막을 ffmpeg으로 그리지 않는다.
- 워커는 순수 함수 + 스폰. 테스트는 `fixtures/`의 5초 샘플로.
- 렌더 관련 변경은 **반드시 프레임 시트를 첨부**해 PR/커밋에 남긴다. 눈으로 확인하지 않은 렌더 변경은 머지하지 않는다.
- UI 문구·에러 문구는 `apps/web/src/copy.ts` 한 파일에. 하드코딩 금지.
- 로그는 `~/.madi/logs/`. 사용자에게 경로를 노출하지 않는다.
- 사용 이벤트(요청 종류, 소요 시간, 게이트 통과율)를 로컬 SQLite `events`에 기록. 외부 전송 없음. 판매 판단 근거로 쓴다.
- **"편집 시간 10분"을 계속 측정한다.** 원본 투입부터 다운로드까지 실측을 `events`에 남기고, 회귀하면 그 커밋을 되돌린다.

---

## 15. 명령

```
pnpm i
pnpm sidecars        # ffmpeg, whisper.cpp, onnx 모델, cloudflared 내려받기
pnpm dev             # engine(개발) + web(HMR)
pnpm spike           # 0단계: fixtures의 수동 Composition 렌더 후 비교 시트 출력
pnpm build
pnpm test
pnpm e2e
pnpm db:migrate
pnpm db:studio
pnpm package
```

---

## 16. 하지 않는 것 (지금은)

- 풀 타임라인 편집기, 트랙, 키프레임 UI
- 범용 편집 도구화. 타깃은 운동·재활 크리에이터로 고정
- 스타일 자동 학습. 템플릿은 사람이 쓴다
- AI 없이 동작하는 별도 편집 경로
- SaaS 배포, 다중 사용자, 계정 시스템, 텔레메트리 전송 (설계상 막지는 않되 구현 안 함)
- API 키 방식 AI 호출 (`AgentProvider` 구현 추가로 대응 가능하게만)
- 브라우저 내 영상 처리 (ffmpeg.wasm 등)
- 다크 모드
- 롱폼 (6단계 통과 전까지)

---

## 17. 타깃 환경

- 1차 타깃은 **크리에이터 PC 한 대**. OS와 GPU는 `docs/target-machine.md`에 기록하고 그 조합의 바이너리만 우선 빌드한다.
- 지원 브라우저: 최신 Chrome / Safari. 모바일은 375 기준 갤러리 · 편집안 · 결과물 3화면만.
