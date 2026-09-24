# archive

버린 시도를 남겨 둔다. **빌드하지 않는다.** 참고용이다.

## `remotion-spike/`

2026-09-23. 웹(Node + Remotion) 기준으로 만든 0단계 스파이크.
아키텍처를 Swift 네이티브 단일로 바꾸면서 버렸다.

**여기서 얻어 지금도 쓰는 것:**

- 원본 실측값 → `AGENTS.md §9`, `docs/findings/2026-09-23-reference-measurement.md`
- 레이아웃 어휘 빈도 → `docs/findings/2026-09-23-layout-survey.md`
- 참고 프레임 34장 → `reference/`
- 측정 도구 → `tools/measure.mjs`
- `Composition` 스키마 설계 → `AGENTS.md §5`

**왜 남겨 두나:**

측정 절차가 여기 들어 있다. 프로브 → 측정 → 보정을 3회 왕복해서 원본과 1px 이내로
맞춘 기록이고, CoreText 로 다시 할 때 같은 절차를 밟는다.
`remotion/Caption.tsx` 의 레이아웃 구조(본문 아래끝 기준 앵커, 보조 문구를 아래에 매달기)는
CoreText 로 옮길 때 그대로 참고한다.

**교훈으로 남은 것:**

- `bottomRatio` 는 블록 전체가 아니라 **본문 아래끝** 기준이어야 한다.
  전체 기준으로 잡으면 보조 문구가 있을 때 본문이 밀려 올라간다 (54px @1920)
- CSS 는 글자가 아니라 줄상자를 배치한다. 그래서 `baselineNudgeRatio` 가 필요했다.
  CoreText 는 메트릭을 직접 주므로 이 꼼수가 필요 없을 수 있다
- 추측으로 값을 고치면 틀린다. `fontSize` 를 150 으로 키우려다 실측하니 반대였다
