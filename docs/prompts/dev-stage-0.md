# 개발 담당 AI 프롬프트 — 0단계

아래 전체를 그대로 붙여넣는다. **0단계 전용**이다. 통과하면 1단계 프롬프트를 새로 준다.

---

너는 macOS 네이티브 앱 **마디(madi)** 를 만든다. Swift · SwiftUI 단일 언어다.
저장소는 `/Users/kimeunjoong/orca/madi`, 브랜치는 `rebuild` 다.

## 먼저 읽을 것 (순서대로, 전부)

1. `AGENTS.md` — 전체. 이게 유일한 지침서다. `§0 반복 금지 목록`부터 읽어라
2. `docs/stage-0.spec.md` — **네가 지금 할 일의 범위와 통과 조건**
3. `docs/findings/2026-09-23-reference-measurement.md` — 자막 실측값과 그것을 얻은 절차
4. `docs/findings/2026-09-23-layout-survey.md` — 레이아웃 어휘 빈도
5. `docs/style-authoring.md` — 값을 재는 방법
6. `archive/README.md` — 버린 웹 스파이크에서 얻은 교훈. 같은 실수를 반복하지 않기 위해 읽는다

## 이 프로젝트의 역사 (중요)

전작(`legacy/v0.2` 브랜치, 148커밋, Electron + Node + ffmpeg)이 있었고 **결과물 품질이 처참해서 버렸다.**
원인은 인프라가 아니라 편집을 표현하는 자료구조였다. `AGENTS.md §0` 에 7개로 정리돼 있다.

그 다음 웹 + Remotion 으로 0단계를 시작했고, **자막을 원본과 1px 이내까지 맞추는 데 성공했다.**
그러다 아키텍처를 Swift 네이티브 단일로 바꾸면서 그 구현은 버렸다 (`archive/remotion-spike/`).
**측정 결과는 버리지 않았다.** 렌더러와 무관한 사실이라서다.

즉 너는 **목표 숫자가 이미 확정된 상태에서** 시작한다. 처음보다 훨씬 쉽다.

## 지금 할 일 — 0단계만

`docs/stage-0.spec.md` 를 따른다. 요약하면:

### A. 자막 한 장을 숫자로 맞춘다 (먼저)

CoreText 로 자막을 그려 PNG 로 뽑고, `tools/measure.mjs` 로 재서 목표에 맞춘다.

| 항목 | 목표 | 허용 |
|---|---|---|
| 본문 글자 높이 | 프레임 높이의 3.59% | ±0.1% |
| 본문 아래끝 | 아래에서 0.2352 | ±0.003 |
| 보조 문구 아래끝 | 아래에서 0.204 | ±0.003 |

```bash
node tools/measure.mjs out/caption-probe.png
```

PASS/FAIL 이 찍힌다. **세 항목이 다 PASS 되기 전에 B 로 가지 않는다.**
그다음 `reference/yt_11s.png` 같은 원본 프레임을 배경으로 깔아 겹쳐서 눈으로도 확인한다.

### B. 영상 한 편을 재현한다

`reference/` 중 1편을 손으로 `Composition` JSON 으로 옮겨 적고,
AVMutableComposition + CoreAnimationTool + AVAssetWriter 로 렌더해서 원본과 나란히 본다.

통과 조건 5개는 `docs/stage-0.spec.md` 에 있다. 마지막이 **"같은 채널 영상으로 보인다"** 다.
하나라도 "비슷한데 좀 다르다"면 통과가 아니다.

## 하드 규칙

1. **범위를 벗어나지 않는다.** `docs/stage-0.spec.md` 의 "범위 밖" 목록을 만들지 않는다.
   AI · GRDB · PhotoKit · 큐 · Vision · WhisperKit · 배포 · 본 UI 전부 다음 단계다.
   필요하다고 느껴지면 만들지 말고 **멈추고 물어본다.**
2. **값을 추측하지 않는다.** 폰트 크기, 여백, 외곽선 두께를 감으로 정하지 마라.
   `reference/` 프레임을 재서 역산하고, 왜 그 값인지 주석에 남긴다.
   (전작이 망한 원인 중 하나가 디자인 시안 색을 그대로 박고 "학습됐다"고 한 것이다)
3. **렌더 출력을 바꾸는 변경은 프레임을 뽑아서 눈으로 확인하고 커밋에 첨부한다.**
   측정 숫자만 보고 통과라고 하지 않는다.
4. **자막을 이미지로 미리 굽지 않는다.** CoreText 로 매번 그린다.
5. **스타일 값을 `Composition` 에 넣지 않는다.** 폰트·색·크기·좌표는 `Templates/` 가 정한다.
   `assertNoStyleValues()` 로 막고 테스트를 쓴다 (`AGENTS.md §5`).
6. **Universal 2 로 빌드한다** (`ARCHS = arm64 x86_64`). 0단계에서 아키텍처 분기 코드는 필요 없다.
7. `AGENTS.md` 를 네 판단으로 고치지 않는다. 충돌하는 게 있으면 발견을 보고하고 물어본다.
8. Node · 웹 · Remotion · ffmpeg · 외부 바이너리를 도입하지 않는다.
   `tools/measure.mjs` 만 예외다 (측정 도구, 제품 코드 아님).

## 미리 알려주는 함정

`docs/stage-0.spec.md` 의 "알려진 함정" 을 반드시 읽어라. 요약:

- `NSAttributedString.strokeWidth` 는 **음수**여야 외곽선+채우기가 함께 그려진다.
  값은 절대 px 가 아니라 폰트 크기 대비 백분율이다.
- CALayer 애니메이션 `beginTime` 은 `AVCoreAnimationBeginTimeAtZero` 기준이어야 한다.
  0 을 쓰면 무시된다. `isRemovedOnCompletion = false`, `fillMode = .both`.
- **글자 높이 ≠ 폰트 크기.** `CTLineGetBoundsWithOptions(.useGlyphPathBounds)` 로 실제 높이를
  구해 목표에서 역산한다. 웹(CSS)에서는 0.889 배였는데 CoreText 는 다르다. 재라.
- Pretendard Variable 의 `wght` 축을 명시하지 않으면 기본 웨이트로 그려진다.
  ExtraBold 가 나오는지 첫 장에서 확인한다.
- 프리뷰(`AVPlayer`)와 최종 렌더가 **같은 `videoComposition`** 을 쓰게 한다.
  다르면 사용자가 신뢰를 잃는다.

## 작업 순서

1. Xcode 프로젝트 생성 (`Madi.xcodeproj`), Universal 2 설정, Pretendard 번들
2. `Madi/Model/Composition.swift` + `MadiTests/CompositionTests.swift`
   (`AGENTS.md §5` 그대로. 스타일 값 차단 테스트 포함)
3. `reference/` 프레임에서 자막 값 역산 → `Madi/Templates/SuhyunShortV1/Tokens.swift`
4. `CaptionLayer.swift` + `StillRenderer.swift` → **A 통과까지 반복**
5. `Renderer.swift` (AVMutableComposition + CoreAnimationTool + AssetWriter)
6. `spike/composition.json` 손으로 작성 → 렌더 → B 판정

3~4번이 이 단계의 본체다. 시간을 거기 쓴다. **4번을 건너뛰고 5번으로 가지 않는다.**

## 보고 방식

각 단계 끝에 이렇게 보고한다.

- 한 일 / 측정 숫자 / PASS·FAIL
- 추측으로 정한 값이 있으면 **그것만 따로 목록으로** 적는다
- 막힌 것과 다음에 할 것
- 렌더 관련이면 프레임 이미지 경로

커밋은 작게 하고, 커밋 메시지에 **측정 숫자를 남긴다.**
나중에 값이 왜 그렇게 정해졌는지 추적할 수 있어야 한다.
