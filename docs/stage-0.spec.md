# Stage 0 — 렌더러 스파이크

`AGENTS.md §12-0`. 이 단계를 통과하기 전에 1단계로 가지 않는다.

## 목적

크리에이터가 실제로 올린 숏폼 1편을, 손으로 쓴 `Composition` JSON + Remotion으로 **눈에 띄게 다르지 않게** 재현할 수 있는지 확인한다.

이건 AI 실험이 아니다. **렌더러의 표현력 상한을 재는 실험**이다.
전작(`legacy/v0.2`)이 실패한 이유는 렌더러가 트림·정적크롭·ASS자막밖에 못 했기 때문이고, 그 한계를 재보지 않은 채 AI부터 붙였기 때문이다. 이번에는 그 순서를 뒤집는다.

## 범위 밖 (이 단계에서 절대 만들지 않는 것)

- AI / 에이전트 / MCP
- SQLite / Drizzle / 마이그레이션
- Electron / 트레이 / 패키징
- Hono 서버 / 웹 UI / 업로드 / 터널
- whisper / 사람 감지 / Digest 생성
- 작업 큐
- 자동 리프레이밍 (좌표는 손으로 적는다)

위 항목이 필요하다고 느껴지면 그건 0단계를 벗어난 것이다. 멈추고 spec을 먼저 고친다.

## 입력

- `spike/reference/final.mp4` — 크리에이터가 실제 업로드한 숏폼 1편 (목표)
- `spike/reference/raw.mp4` — 같은 편의 편집 전 촬영본 (있으면. 없으면 final을 소스로 쓰고 자막만 다시 얹는다)
- `spike/public/frames/` — `final.mp4`에서 0.5초 간격으로 뽑은 캡처. 자막 크기·위치·색·분절을 눈으로 재는 근거

## 산출물

| 파일 | 내용 |
|---|---|
| `packages/shared/src/composition.ts` | ✅ `AGENTS.md §5` zod 스키마. Composition · Scene · Caption · Overlay |
| `spike/composition.json` | `final.mp4`을 손으로 옮겨 적은 Composition. 스키마 검증 통과해야 함 |
| `spike/remotion/tokens.ts` | 폰트 · 색 · 크기 · 외곽선 · 모션 상수. `frames/`에서 실측한 값 |
| `spike/remotion/Caption.tsx` | 자막 컴포넌트. pop-in, 외곽선, 보조문구, 강조 |
| `spike/remotion/Short.tsx` | 9:16 컴포지션 루트 |
| `spike/render.mjs` | `composition.json` → `spike/out/final.mp4` |
| `spike/compare.mjs` | `out/final.mp4`와 `reference/final.mp4`를 같은 시각에서 나란히 붙인 비교 시트 PNG |
| `spike/probe.mjs` | ✅ 영상 없이 자막 한 장만 렌더 (`out/caption-probe.png`). 작업순서 4 용 |

## Files to Create/Modify

```
package.json
pnpm-workspace.yaml
.nvmrc
.gitignore
.editorconfig
docs/stage-0.spec.md
packages/shared/package.json
packages/shared/tsconfig.json
packages/shared/src/index.ts
packages/shared/src/composition.ts
packages/shared/src/composition.test.ts
spike/composition.example.json
spike/frames.mjs
spike/remotion/index.ts
spike/package.json
spike/tsconfig.json
spike/composition.json
spike/render.mjs
spike/compare.mjs
spike/remotion/Root.tsx
spike/remotion/Short.tsx
spike/remotion/Caption.tsx
spike/remotion/Overlay.tsx
spike/remotion/tokens.ts
spike/remotion/Probe.tsx
spike/remotion/font.ts
spike/probe.mjs
spike/webpack-override.mjs
spike/ensure-browser.mjs
spike/remotion.config.ts
spike/public/fonts/PretendardVariable.woff2
spike/public/reference/*.png
```

이 목록 밖의 파일을 만들어야 한다면 먼저 이 spec을 고친다.

## 통과 조건

`pnpm spike` 실행 → 비교 시트를 사람이 눈으로 보고 판정한다.

1. **자막** — 글자 크기 · 폰트 굵기 · 외곽선 · 화면상 위치 · 한 번에 뜨는 글자 수가 원본과 구분하기 어렵다
2. **구도** — 인물 크기와 화면 내 위치가 원본과 비슷하다 (리프레이밍 좌표는 손으로 적어도 된다)
3. **리듬** — 컷 지점과 자막 전환 타이밍이 원본과 어긋나 보이지 않는다
4. **훅** — 0~1.5초 구간이 원본과 같은 인상을 준다
5. **종합** — 두 영상을 나란히 놓고 **같은 채널 영상으로 보인다**

5개 전부 만족해야 통과. 하나라도 "비슷한데 좀 다르다"면 통과가 아니다.

## 실패 시

컴포지터를 바꾼다. 1단계로 가지 않는다.

1. Remotion으로 안 되는 게 정확히 무엇인지 적는다
2. `video/motion-canvas` 스킬로 같은 실험을 반복한다
3. 둘 다 안 되면 WebCodecs + canvas 자체 구현을 검토하고, 그 비용을 일정에 반영한 뒤 사람이 결정한다

## 선결 확인

- ~~Remotion 상업 라이선스~~ — **해소됨 (2026-09-23).** 개인은 상업적 사용·판매 포함 무료. `AGENTS.md §13` 참조. 인원 4명이 되면 재계산
- **Pretendard Variable** 번들 가능 여부 (OFL)
- ffmpeg 설치 (`brew install ffmpeg`). 0단계는 사이드카 번들 없이 시스템 ffmpeg을 쓴다

## 작업 순서

1. ~~Remotion 라이선스 확인~~ — 완료
2. ~~`packages/shared/src/composition.ts`~~ — 완료 (테스트 7개 포함)
3. `public/frames/` 뽑고 자막 값 실측 → `tokens.ts`
4. `Caption.tsx` 먼저 만들고 정지 프레임 1장으로 원본과 대조 (여기서 대부분 결판난다)
5. `Short.tsx` + `composition.json` 채우기
6. `render.mjs` → `compare.mjs`
7. 비교 시트 보고 통과 조건 5개 판정

4번을 건너뛰지 않는다. 자막 한 장이 원본과 다르면 영상 전체가 다르다.
4번은 `pnpm --filter @madi/spike probe` 로 영상 없이 돌릴 수 있다.
`PROBE_TEXT` · `PROBE_SECONDARY` · `PROBE_BACKDROP` 환경변수로 바꾼다.
`PROBE_BACKDROP` 은 `spike/public/` 안의 경로다 — `reference/yt_11s.png` 처럼 쓴다 (`public/` 접두사 금지).

## 알려진 환경 요구

- 첫 렌더에서 Remotion 이 Chrome Headless Shell(약 94MB)을 자동으로 내려받는다.
  - **macOS**: 받은 바이너리에 `com.apple.quarantine` 이 붙어 실행이 차단된다.
    Remotion 은 "Failed to launch the browser process!" 만 보여줘서 원인을 알기 어렵다.
    `ensure-browser.mjs` 가 렌더 진입점에서 자동으로 푼다. 새 진입점을 만들면 이것도 같이 부른다.
    수동: `xattr -dr com.apple.quarantine spike/node_modules/.remotion`
- `compare.mjs` · `frames.mjs` 는 시스템 `ffmpeg` 을 쓴다 (`brew install ffmpeg`). `FFMPEG_PATH` 로 지정 가능.
- webpack 이 TS 의 `./x.js` 임포트를 풀도록 `webpack-override.mjs` 를 쓴다. 새 렌더 진입점을 만들면 이걸 같이 넘긴다.
