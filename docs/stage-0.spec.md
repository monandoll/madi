# Stage 0 — 자막 렌더 스파이크 (CoreText)

`AGENTS.md §12-0`. 이 단계를 통과하기 전에 1단계로 가지 않는다.

## 상태 (2026-09-25)

**A 통과 · B 4/5 통과 · B-2(구도)는 촬영 원본 대기.**

| | 판정 | |
|---|---|---|
| A. 자막 한 장 | **통과** | 3.54% / 0.2354 / 0.2021 — 세 항목 전부 |
| B-1 자막 | **통과** | 네이티브 1080p 원본과 측정값이 자릿수까지 같다 |
| B-2 구도 | **보류** | 소스가 이미 9:16 크롭된 완성본이라 리프레이밍을 검증할 수 없다 |
| B-3 리듬 | **통과** | 자막 전환 경계 60개 시각 전부 포개짐 |
| B-4 훅 | **통과(제한적)** | 자막은 동일. 훅 *구성*은 이 소스로 검증 불가 |
| B-5 종합 | **통과** | 나란히 놓고 구분되지 않는다 |

근거와 프레임: `docs/findings/2026-09-25-coretext-caption-measurement.md`.

**1단계(리프레이밍)는 촬영 원본(`spike/source/raw.mp4`)이 들어올 때까지 시작하지 않는다.**
B-2 를 판정하지 못한 채로 리프레이밍을 만들면 무엇에 맞추는지 모르는 채로 만드는 것이다.
채널에 16:9 롱폼도 없어서 대용도 없다.

그동안은 **1단계를 막지 않는 준비 작업만** 한다 — 레이아웃 어휘 재조사(10편),
스키마 갭 반영, `PoseProvider` 감지 정확도 스파이크.

## 목적

**CoreText + CALayer 로 크리에이터 자막을 재현할 수 있는지** 확인한다.
이어서 공개 숏폼 1편을 `Composition` 으로 손으로 옮겨 적고 렌더해서 원본과 나란히 본다.

AI 실험이 아니다. **렌더러의 표현력 상한을 재는 실험**이다.
전작이 실패한 이유는 렌더러가 트림·정적크롭·ASS자막밖에 못 했기 때문이고,
그 한계를 재보지 않은 채 AI 부터 붙였기 때문이다. 이번에는 순서를 뒤집는다.

## 이미 끝난 것 (Remotion 스파이크에서 얻은 것)

방향을 웹 → Swift 네이티브로 바꿨지만 **측정 결과는 그대로 쓴다.**

- 원본 실측표 — `AGENTS.md §9`, `docs/findings/2026-09-23-reference-measurement.md`
- 레이아웃 어휘 빈도 — `docs/findings/2026-09-23-layout-survey.md`
- 참고 프레임 34장 — `reference/`
- 측정 도구 — `tools/measure.mjs` (PNG 를 재므로 무엇이 그렸는지 무관)
- `Composition` 스키마 설계 — `AGENTS.md §5` (zod → Swift Codable 로 포팅)

**버리는 것**: `fontSize 78`, `baselineNudgeRatio 0.153`, `gapRatio 0.062`.
CSS 줄상자 때문에 나온 보정값이다. CoreText 는 폰트 메트릭을 직접 주므로 다시 잡는다.

## 범위 밖 (이 단계에서 만들지 않는 것)

- AI / 에이전트 / MCP
- GRDB 스키마 / 마이그레이션
- PhotoKit 가져오기 / 폴더 감시
- 작업 큐
- Vision / WhisperKit (1단계)
- 자동 리프레이밍 (좌표는 손으로 적는다)
- 배포 / 엔타이틀먼트 / `.dmg`
- SwiftUI 본 UI (프리뷰 창 하나만)

필요하다고 느껴지면 0단계를 벗어난 것이다. 멈추고 spec 을 먼저 고친다.

## 산출물

| 파일 | 내용 |
|---|---|
| `Madi/Model/Composition.swift` | `AGENTS.md §5` Codable 타입 + `assertNoStyleValues()` |
| `Madi/Templates/StyleSchema.swift` | 스타일 파라미터 정의 · 검증 범위 · 기본값. **AI 접근 불가** |
| `Resources/styles/short.v1.json` | 스타일 **값**. `§9` 실측표에서 역산. 빌드 없이 바뀐다 |
| `Madi/Templates/CaptionLayer.swift` | CoreText 자막 레이어. 값은 주입받는다 |
| `Madi/Render/Renderer.swift` | Composition → AVMutableComposition + CALayer → AVAssetExportSession |
| `Madi/Render/StillRenderer.swift` | 프레임 1장만 PNG 로. 측정·대조용 |
| `MadiTests/CompositionTests.swift` | 파싱 · 길이 · 오프셋 · 스타일값 차단 · 역구간 |
| `spike/composition.json` | `reference/` 1편을 손으로 옮겨 적은 것 |

## 통과 조건

### A. 자막 한 장 (먼저)

`StillRenderer` 로 자막 한 장을 그려 `tools/measure.mjs` 로 잰다.

| 항목 | 목표 | 허용 |
|---|---|---|
| 본문 글자 높이 | 프레임 높이의 3.59% | ±0.1% |
| 본문 아래끝 | 아래에서 0.2352 | ±0.003 |
| 보조 문구 베이스라인 | 아래에서 0.2023 | ±0.003 |

한 줄 최대 글자 수는 **15자**다 (`AGENTS.md §9`). 13자로 두면 원본이 한 줄로 쓰는 자막이 두 줄로 쪼개진다.

배경 없이 재고, 그다음 `reference/` 프레임 위에 겹쳐서 눈으로 본다.
**세 항목이 다 들어오기 전에 B 로 가지 않는다.** 자막 한 장이 틀리면 영상 전체가 틀린다.

### B. 영상 한 편

`spike/composition.json` → 렌더 → 원본과 같은 시각 프레임을 나란히 붙여 본다.

1. **자막** — 크기 · 굵기 · 외곽선 · 위치 · 한 번에 뜨는 글자 수가 원본과 구분하기 어렵다
2. **구도** — 인물 크기와 화면 내 위치가 비슷하다 (리프레임 좌표는 손으로 적어도 된다)
3. **리듬** — 컷 지점과 자막 전환 타이밍이 어긋나 보이지 않는다
4. **훅** — 0~1.5초가 원본과 같은 인상을 준다
5. **종합** — 두 영상을 나란히 놓고 **같은 채널 영상으로 보인다**

5개 전부 만족해야 통과. 하나라도 "비슷한데 좀 다르다"면 통과가 아니다.

## 실패 시

합성 방식을 바꾼다. 1단계로 가지 않는다.

1. `AVVideoCompositionCoreAnimationTool` 로 안 되는 게 정확히 무엇인지 적는다
   (이미 하나 나왔다 — **내보내기에서만 적용된다.** `AVAssetWriter` · `AVPlayer` ·
   `AVAssetImageGenerator` 는 무시한다. `AGENTS.md §7` 참고)
2. 커스텀 `AVVideoCompositing` 으로 프레임별 합성한다. 제어는 늘고 코드는 늘어난다
3. 둘 다 안 되면 비용을 일정에 반영한 뒤 사람이 결정한다

## 알려진 함정

- **외곽선은 두 번 그린다.** 양수 `strokeWidth` 로 획만 깔고 그 위에 fill 을 얹는다.
  음수로 주면 fill → stroke 순이라 획 절반이 글자 안쪽을 파먹는다. 원본은 안 깎였다
  (`docs/findings/2026-09-25-coretext-caption-measurement.md §1`).
  값은 폰트 크기 대비 백분율이고 획 **가운데** 기준이다 (절대 px 가 아니다).
- **CALayer 애니메이션의 `beginTime`** 은 `AVCoreAnimationBeginTimeAtZero` 기준이어야 한다.
  0 을 그대로 쓰면 무시된다. `isRemovedOnCompletion = false`, `fillMode = .both`.
- **글자 높이 ≠ 폰트 크기.** `CTFontGetBoundingBox` / `CTLineGetBoundsWithOptions(.useGlyphPathBounds)`
  로 실제 그려지는 높이를 구해 목표에서 역산한다. Remotion 때는 0.889 배였는데
  CoreText 는 다르다. 추측하지 말고 잰다.
- **Pretendard Variable 의 웨이트** 지정. CoreText 에서 variable 축(`wght`)을 명시하지 않으면
  기본 웨이트로 그려진다. ExtraBold 가 나오는지 첫 장에서 확인한다.
- **프리뷰와 내보내기는 경로가 다르다.** `animationTool` 은 내보내기에서만 적용된다.
  같아야 하는 것은 `videoComposition` 이 아니라 **레이어 트리를 만드는 함수**다 (`AGENTS.md §7`).

## 작업 순서

1. `Composition.swift` + 테스트
2. `reference/` 프레임에서 자막 값 역산 → `StyleSchema.swift`(스키마) + `short.v1.json`(값)
3. `CaptionLayer.swift` + `StillRenderer` → **A 통과까지 반복**
4. `Renderer.swift` (AVMutableComposition + CoreAnimationTool + AVAssetExportSession)
5. `spike/composition.json` 손으로 작성
6. 렌더 → 비교 → B 판정

3번을 건너뛰지 않는다.
