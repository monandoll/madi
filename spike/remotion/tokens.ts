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
  /** px. 1920 높이 기준. TODO: frames/ 에서 실측 */
  fontSize: 92,
  fontWeight: 800,
  color: '#FFFFFF',
  /** 검은 외곽선. TODO: 실측 */
  strokeColor: '#000000',
  strokeWidth: 8,
  /** 화면 폭 대비 최대 사용 비율 */
  maxWidthRatio: 0.88,
  /** 화면 아래에서 띄우는 비율 (0.26 = 하단 26% 지점) TODO: 실측 */
  bottomRatio: 0.26,
  lineHeight: 1.18,
  /** 한 덩어리 최대 글자 수. 품질 게이트 G5 */
  maxChars: 12,
  maxLines: 2,
  /** 등장 애니메이션 */
  popInMs: 100,
  popInScaleFrom: 0.86,
} as const;

/** 강조 단어. 색만 바꾼다. 크기를 바꾸면 줄바꿈이 흔들린다. */
export const CAPTION_EMPHASIS = {
  color: '#FFE04D',
} as const;

/** 보조 문구(영문 등). 본문 바로 아래. */
export const CAPTION_SECONDARY = {
  scale: 0.55,
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
