/**
 * 스타일 자산. AGENTS.md §9.
 *
 * ★ 이 파일의 값은 **`spike/reference/frames/` 를 눈으로 재서** 채운다.
 *   추측해서 채우지 않는다. 전작이 기본값을 디자인 시안 색(#E8C33F 노란 박스)으로
 *   박아 놓고 "스타일 학습"이라고 부른 게 §0-4 실패 원인이다.
 *
 * 아래 값은 유튜브 숏츠 1편을 화면으로만 본 **미측정 추정치**다.
 * `pnpm spike:frames` 로 프레임을 뽑고 실제로 재서 전부 덮어쓴 뒤 MEASURED 를 true 로 바꾼다.
 */

export const MEASURED = false as boolean;

/**
 * 잠정 실측 (2026-09-23).
 *
 * 출처: 유튜브 숏츠 `EDpBGkaNJmU` 1편, 브라우저 canvas 캡처 10프레임, 720x1280.
 * 아래 값은 여기서 재서 1080x1920 으로 환산했다.
 *
 * ★ 아직 MEASURED=false 인 이유:
 *   - 1편만 쟀다. §9 절차는 5편을 요구한다
 *   - 유튜브 720p 재인코딩본이다. 인스타 릴스 원본과 자막이 다를 수 있다
 *     (이 영상은 auto-dubbed 버전이라 영문 보조자막이 붙어 있다)
 *   - reference/final.mp4 가 들어오면 다시 재고 그때 true 로 바꾼다
 *
 * 확정된 판정:
 *   - 자막 크기는 **고정**이다. fit-to-width 가 아니다.
 *     글자 수 9~12자에서 폭 비율은 0.61~0.82 로 변하는데 글자 높이는 47~49px 로 일정했다.
 *     → 폭 기준 자동 스케일을 구현하지 않는다.
 *   - 강조색은 쓰지 않는다. 본문은 전부 흰색이었다.
 *   - 보조 문구(영문)는 **노란색**이 맞다.
 */

export const FRAME = {
  width: 1080,
  height: 1920,
  fps: 30,
} as const;

/**
 * 자막 본문.
 * 품질 게이트 G4: 글자 높이 >= 프레임 높이의 4.5% (1920 기준 86px).
 * 전작은 fontSize 56 (2.9%) 이었고 그래서 자동 자막처럼 보였다.
 */
export const CAPTION = {
  fontFamily: 'Pretendard Variable, Pretendard, sans-serif',
  /**
   * px. 1920 높이 기준.
   * 실측: 글자 높이 47~49px @1280 = 프레임의 3.7% → 1920 환산 71px.
   * 프로브에서 fontSize 92 가 글자 높이 91px 을 냈으므로 92 x (71/91) ≈ 72.
   */
  fontSize: 72,
  fontWeight: 800,
  color: '#FFFFFF',
  /** 검은 외곽선. strokeWidth 는 **바깥으로 나간** 두께다 (Caption.tsx 가 2배로 넘긴다). */
  strokeColor: '#000000',
  /** 실측: 4~5px @720 → 1080 환산 6~7.5px */
  strokeWidth: 7,
  /** 화면 폭 대비 최대 사용 비율 */
  maxWidthRatio: 0.88,
  /**
   * 화면 아래에서 띄우는 비율.
   * 실측: 4개 프레임에서 0.2344~0.2352 로 거의 흔들리지 않았다. 가장 신뢰도 높은 값.
   */
  bottomRatio: 0.235,
  lineHeight: 1.18,
  /** 한 덩어리 최대 글자 수. 실측: 12자까지 한 줄로 갔다. 품질 게이트 G5 */
  maxChars: 13,
  maxLines: 2,
  /** 등장 애니메이션 */
  popInMs: 100,
  popInScaleFrom: 0.86,
} as const;

/**
 * 강조 단어. 색만 바꾼다. 크기를 바꾸면 줄바꿈이 흔들린다.
 * ★ 실측 영상에서는 강조를 **쓰지 않았다**. 본문은 전부 흰색.
 *   기능은 남겨두되 기본으로 쓰지 않는다. 쓸 근거가 생기면 그때 색을 정한다.
 */
export const CAPTION_EMPHASIS = {
  color: '#FFE04D',
} as const;

/** 보조 문구(영문 등). 본문 바로 아래. */
export const CAPTION_SECONDARY = {
  /** 실측: 본문 약 48px 대비 보조 약 22px @720 → 0.46 */
  scale: 0.48,
  color: '#FFE04D',
  italic: true,
  strokeWidth: 5,
  /** 본문과의 간격 (본문 fontSize 대비) */
  gapRatio: 0.18,
} as const;

/** 훅 타이틀. 품질 게이트 G8: 0~1.5초. */
export const HOOK = {
  fontSize: 110,
  fontWeight: 900,
  color: '#FFFFFF',
  strokeColor: '#000000',
  strokeWidth: 10,
  /** 화면 위에서 띄우는 비율 */
  topRatio: 0.14,
  durationSec: 1.2,
  zoomFrom: 1.0,
  zoomTo: 1.06,
} as const;

/**
 * 리프레이밍 목표.
 * 품질 게이트 G1: 인물 bbox 높이 >= 프레임 높이의 55% 인 구간이 80% 이상.
 * 목표치는 그보다 넉넉하게 잡는다.
 */
export const REFRAME = {
  /** 인물 bbox 높이가 프레임 높이의 이만큼을 채우도록 */
  targetSubjectHeightRatio: 0.72,
  /** 저역통과 스무딩 시간(초). 이보다 짧으면 프레임이 떨린다 (G3) */
  smoothingSec: 0.4,
  /** 피사체 주변 여백 */
  padding: 0.08,
} as const;

export const AUDIO = {
  bgmGainDb: -22,
  bgmDuckDb: -6,
  sfxGainDb: -8,
  /** 품질 게이트 G12 */
  targetLufs: -14,
} as const;

/** 값을 실측 전에 렌더하면 경고. 조용히 지나가지 않는다. */
export function warnIfUnmeasured(): void {
  if (!MEASURED) {
    console.warn(
      '\n[tokens] 아직 실측 전 값입니다. spike/reference/frames/ 를 보고 채운 뒤 MEASURED=true 로 바꾸세요.\n' +
        '  AGENTS.md §9 / docs/stage-0.spec.md 작업순서 3~4\n',
    );
  }
}
