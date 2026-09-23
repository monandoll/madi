# 스타일 템플릿 작성법

AGENTS.md §9. **스타일은 학습하지 않는다. 사람이 잰다.**

전작은 완성본에서 스타일을 "학습"시키려 했다. 완성본은 자막이 이미 번인되어 있어서
폰트 크기나 외곽선 두께를 역추출할 수 없다. 추출된 건 결국 "컷 길이 평균" 같은 것뿐이었고,
실제 기본값은 디자인 시안의 노란 박스(`#E8C33F`, 56px)가 그대로 박혔다.
크리에이터 실제 스타일은 흰 글씨 + 검은 외곽선이었다. 그게 §0-4 실패다.

재는 데 30분 걸린다. 학습시키려다 2주 날리지 않는다.

---

## 1. 프레임 뽑기

```bash
cd spike
pnpm frames        # reference/final.mp4 → reference/frames/*.png (0.5초 간격)
```

자막이 **가장 길게 나온 프레임**과 **가장 짧게 나온 프레임** 2장을 고른다.
이 두 장이면 크기·줄바꿈·분절 규칙이 다 나온다.

---

## 2. 재는 법

프레임을 이미지 편집기(미리보기 앱의 사각형 선택으로 충분)에서 열고 픽셀을 읽는다.
**원본 프레임은 1080x1920이다.** 리사이즈된 걸 재면 값이 전부 틀어지므로 확인부터 한다.

| tokens.ts 값 | 재는 법 |
|---|---|
| `CAPTION.fontSize` | 받침 없는 글자(예: "다", "이")의 **위아래 끝 픽셀 높이**. 글자 높이 ≈ fontSize × 0.72 이므로 잰 값 ÷ 0.72 |
| `CAPTION.strokeWidth` | 글자 획 바깥 검은 테두리의 한쪽 두께(px). 양쪽 합이 아니다 |
| `CAPTION.bottomRatio` | 자막 블록 **아래쪽 끝**에서 프레임 하단까지 픽셀 ÷ 1920 |
| `CAPTION.maxWidthRatio` | 가장 긴 자막 줄의 좌우 폭 ÷ 1080. 보통 0.85~0.92 |
| `CAPTION.maxChars` | 여러 프레임에서 한 번에 뜬 글자 수의 **최댓값** (공백 포함) |
| `CAPTION.lineHeight` | 2줄일 때 줄 기준선 간격 ÷ fontSize |
| `CAPTION.color` / `strokeColor` | 스포이드. 안티에일리어싱 경계가 아니라 **글자 안쪽**을 찍는다 |
| `CAPTION_EMPHASIS.color` | 색이 다른 단어가 있으면 그 색. 없으면 강조 기능을 쓰지 않는다 |
| `CAPTION_SECONDARY.*` | 보조 문구(영문 등)가 있으면. `scale` = 보조 fontSize ÷ 본문 fontSize |
| `HOOK.fontSize` / `topRatio` | 0~1.5초 구간 프레임에서 같은 방식으로 |
| `REFRAME.targetSubjectHeightRatio` | 인물의 **머리끝~발목** 픽셀 높이 ÷ 1920. 여러 프레임 평균 |

### 애니메이션

`popInMs`, `popInScaleFrom`, `zoomFrom/To`는 픽셀로 못 잰다. 연속 프레임 2~3장을 비교해서
"몇 프레임 만에 제자리로 오는가"를 세고 fps로 나눈다. 30fps에서 3프레임이면 100ms.

정확할 필요 없다. **눈에 띄게 다르지만 않으면 된다.**

---

## 3. 대조 (가장 중요)

값을 채웠으면 영상을 렌더하기 전에 **정지 화면 한 장**부터 맞춘다.

```bash
pnpm studio        # Remotion Studio
```

Studio에서 자막 한 덩어리만 띄우고, 같은 문구가 나온 `reference/frames/` 프레임과
**나란히 놓고** 본다. 화면 캡처해서 겹쳐 봐도 좋다.

여기서 다르면 영상 전체가 다르다. 이 단계를 건너뛰고 렌더부터 돌리지 않는다.

확인할 것:
- 글자 크기가 원본과 같은가 (제일 자주 틀리는 값)
- 외곽선이 두껍거나 얇지 않은가
- 자막 블록의 세로 위치가 같은가
- 줄바꿈 지점이 같은가

---

## 4. 확정

`tokens.ts`의 `MEASURED`를 `true`로 바꾼다. 그 전에는 렌더할 때마다 경고가 뜬다.

```ts
export const MEASURED = true;
```

---

## 5. 템플릿으로 승격 (2단계)

0단계를 통과하면 `spike/remotion/`을 `packages/templates/suhyun.short.v1/`로 옮긴다.

```
packages/templates/suhyun.short.v1/
  index.tsx        Remotion 루트
  tokens.ts        여기서 잰 값
  layout.ts        role 별 화면 구성, 리프레임 목표치
  spec.json        AI 가 쓸 수 있는 role · slot · overlay kind 와 payload 스키마
  reference/       근거로 쓴 프레임 캡처 (지우지 않는다)
```

`reference/`를 지우지 않는 이유: 나중에 "자막이 좀 작은 것 같은데"라는 말이 나왔을 때
근거 없이 값을 흔들지 않기 위해서다. 값은 항상 프레임을 다시 보고 바꾼다.

---

## 새 크리에이터를 받을 때

템플릿을 하나 더 만든다. 기존 것을 파라미터화하지 않는다.
파라미터가 늘어나면 그게 곧 "AI가 스타일을 정하는" 상태로 되돌아가는 길이다 (§0-4).

릴스 5편 보고 30분 재면 새 템플릿 하나가 나온다. 그게 학습보다 빠르고 정확하다.
