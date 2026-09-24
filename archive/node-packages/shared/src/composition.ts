import { z } from 'zod';

/**
 * 영상 편집의 코어 자료구조.
 *
 * 전작(`legacy/v0.2`)의 `Edit`은 trim · cuts · 정적크롭 · ASS자막만 표현할 수 있었다.
 * 줌 · BGM · 효과음 · 오버레이 · 훅카드가 구조적으로 불가능했고, 그게 결과물이 처참했던 원인이다.
 * AGENTS.md §0-1.
 *
 * 규칙: 렌더는 항상 Composition 으로부터 재현 가능해야 한다 (AGENTS.md §1-8).
 *
 * ★ 스타일 값(폰트 · 색 · 글자 크기 · 자막 절대 좌표 · 애니메이션 곡선 · 외곽선 두께)은
 *   이 스키마에 **없다**. 전부 `templateId` 가 가리키는 템플릿이 정한다 (AGENTS.md §1-2, §9).
 *   그런 필드를 추가하자는 제안이 오면 거절한다. 전작 §0-4 가 그렇게 망했다.
 */

/** 0..1 정규화 좌표 · 크기. 원본 해상도와 무관하게 쓴다. */
export const Norm = z.number().min(0).max(1);

export const NormRect = z.object({
  x: Norm,
  y: Norm,
  w: z.number().min(0).max(1),
  h: z.number().min(0).max(1),
});
export type NormRect = z.infer<typeof NormRect>;

export const NormPoint = z.object({ x: Norm, y: Norm });
export type NormPoint = z.infer<typeof NormPoint>;

// ---------------------------------------------------------------------------
// 자막
// ---------------------------------------------------------------------------

/**
 * 자막 한 덩어리. **문장을 통째로 넣지 않는다.**
 * whisper 문장 세그먼트를 그대로 그린 게 전작이 "자동 생성 자막"처럼 보인 이유다 (AGENTS.md §0-3).
 * 품질 게이트 G5: 12자 이내, 2줄 이내.
 */
export const Caption = z.object({
  id: z.string(),
  /** 장면 로컬 초 (Scene.source.in 기준 0). */
  start: z.number().min(0),
  end: z.number().min(0),
  text: z.string().min(1).max(40),
  /** 영문 번역 등 보조 문구. 템플릿이 본문 아래에 작게 그린다. */
  secondary: z.string().max(80).optional(),
  /** text 안에서 강조할 문자 구간 (반개구간 [from, to)). 색·굵기는 템플릿이 정한다. */
  emphasis: z
    .array(z.object({ from: z.number().int().min(0), to: z.number().int().min(0) }))
    .default([]),
  /** 논리 슬롯. 실제 좌표는 템플릿의 layout 이 정한다. */
  slot: z.enum(['main', 'top']).default('main'),
})
  .refine((c) => c.end > c.start, { message: 'caption.end must be greater than caption.start' })
  .refine((c) => c.emphasis.every((e) => e.to > e.from && e.to <= c.text.length), {
    message: 'caption.emphasis range out of bounds',
  });
export type Caption = z.infer<typeof Caption>;

// ---------------------------------------------------------------------------
// 오버레이
// ---------------------------------------------------------------------------

/**
 * 화면 위에 얹는 것. 물리치료 콘텐츠는 해부학 그림 · 화살표 · 횟수 카운터가 핵심이라
 * 전작처럼 이게 불가능하면 크리에이터 스타일을 절대 못 따라간다.
 *
 * payload 의 구체 스키마는 템플릿의 `spec.json` 이 정의한다.
 * 여기서는 kind 별 최소 계약만 강제한다.
 */
export const OverlayKind = z.enum([
  'titleCard', // 훅 타이틀
  'arrow', // 방향 지시
  'circle', // 부위 강조
  'image', // 해부학 그림 등
  'counter', // 횟수
  'progress', // 진행 바
]);
export type OverlayKind = z.infer<typeof OverlayKind>;

export const Overlay = z.object({
  id: z.string(),
  kind: OverlayKind,
  /** 장면 로컬 초. */
  start: z.number().min(0),
  end: z.number().min(0),
  anchor: NormPoint,
  /** kind 별 내용. 템플릿 spec.json 이 검증한다. 스타일 값은 넣지 않는다. */
  payload: z.record(z.unknown()).default({}),
}).refine((o) => o.end > o.start, { message: 'overlay.end must be greater than overlay.start' });
export type Overlay = z.infer<typeof Overlay>;

// ---------------------------------------------------------------------------
// 리프레이밍
// ---------------------------------------------------------------------------

/**
 * 세로(9:16) 변환에서 원본의 어디를 잡을지, **시간에 따라**.
 * 전작은 `cropFocus: number` 하나로 x좌표만 고정해서 인물이 화면 구석에 작게 박혔다 (AGENTS.md §0-2).
 *
 * - `auto`   : 렌더가 subject 트랙을 보고 키프레임을 채운 뒤 **이 필드에 다시 적는다**.
 *              (렌더는 항상 Composition 으로부터 재현 가능해야 하므로)
 * - `fixed`  : keyframes 의 첫 항목을 전 구간 고정.
 * - `keyframes`: 주어진 대로.
 */
export const ReframeTrack = z.object({
  mode: z.enum(['auto', 'fixed', 'keyframes']).default('auto'),
  /** 장면 로컬 초 기준. mode='auto' 이고 아직 안 풀렸으면 빈 배열. */
  keyframes: z.array(z.object({ t: z.number().min(0), rect: NormRect })).default([]),
  /** 피사체 주변 여백 비율. 템플릿의 목표 점유율과 함께 쓴다. */
  padding: z.number().min(0).max(0.5).default(0.08),
}).refine((r) => r.mode === 'auto' || r.keyframes.length > 0, {
  message: "reframe.keyframes required when mode is not 'auto'",
});
export type ReframeTrack = z.infer<typeof ReframeTrack>;

// ---------------------------------------------------------------------------
// 장면
// ---------------------------------------------------------------------------

/**
 * role 은 템플릿이 "어떻게 그릴지"를 고르는 키다. 좌표나 스타일이 아니다.
 * 품질 게이트 G8 은 0~1.5초에 role='hook' 장면 또는 titleCard 를 요구한다.
 */
export const SceneRole = z.enum(['hook', 'demo', 'explain', 'cta', 'filler']);
export type SceneRole = z.infer<typeof SceneRole>;

export const Scene = z.object({
  id: z.string(),
  role: SceneRole,
  /** 원본 파일의 초. parts 재배치는 scenes 의 **배열 순서**로 표현한다 (원본 순서와 달라도 된다). */
  source: z.object({
    videoId: z.string(),
    in: z.number().min(0),
    out: z.number().min(0),
  }).refine((s) => s.out > s.in, { message: 'source.out must be greater than source.in' }),
  /** 1=원속, 0.5=슬로우, 1.5=빠르게. 결과 길이는 (out-in)/speed. */
  speed: z.number().min(0.25).max(4).default(1),
  reframe: ReframeTrack.default({ mode: 'auto', keyframes: [], padding: 0.08 }),
  captions: z.array(Caption).default([]),
  overlays: z.array(Overlay).default([]),
  transitionIn: z.enum(['cut', 'fade', 'whip', 'zoom']).default('cut'),
});
export type Scene = z.infer<typeof Scene>;

/** 장면의 결과물 길이(초). speed 반영. */
export function sceneDuration(scene: Scene): number {
  return (scene.source.out - scene.source.in) / scene.speed;
}

// ---------------------------------------------------------------------------
// 오디오
// ---------------------------------------------------------------------------

export const AudioTracks = z.object({
  bgm: z
    .object({
      assetId: z.string(),
      gainDb: z.number().min(-60).max(12).default(-22),
      /** 말하는 구간에서 추가로 낮출 양. 품질 게이트 G12. */
      duckDb: z.number().min(-40).max(0).default(-6),
    })
    .optional(),
  /** 컴포지션 전체 타임라인 기준 초. */
  sfx: z
    .array(z.object({ assetId: z.string(), at: z.number().min(0), gainDb: z.number().min(-60).max(12).default(-8) }))
    .default([]),
}).default({ sfx: [] });
export type AudioTracks = z.infer<typeof AudioTracks>;

// ---------------------------------------------------------------------------
// 컴포지션
// ---------------------------------------------------------------------------

export const Platform = z.enum(['reels', 'shorts', 'tiktok']);
export type Platform = z.infer<typeof Platform>;

export const Composition = z.object({
  id: z.string(),
  videoId: z.string(),
  /** packages/templates/<templateId> 를 가리킨다. 스타일은 전부 여기 있다. */
  templateId: z.string().min(1),
  templateVersion: z.number().int().min(1).default(1),
  size: z.object({ w: z.number().int().positive(), h: z.number().int().positive() })
    .default({ w: 1080, h: 1920 }),
  fps: z.number().int().min(24).max(60).default(30),
  meta: z.object({
    title: z.string().default(''),
    platform: Platform.default('reels'),
    /** 품질 게이트 G11 이 ±15% 로 검사한다. */
    targetDurationSec: z.number().positive(),
  }),
  scenes: z.array(Scene).min(1),
  audio: AudioTracks,
  /** 결과물이 있는 컴포지션은 제자리에서 고치지 않는다. 새 것을 만들고 여기에 이전 id 를 적는다. */
  revisionOf: z.string().nullable().default(null),
  createdAt: z.number().int(),
});
export type Composition = z.infer<typeof Composition>;

/** 결과물 전체 길이(초). */
export function compositionDuration(comp: Composition): number {
  return comp.scenes.reduce((acc, s) => acc + sceneDuration(s), 0);
}

/** 각 장면이 결과물 타임라인에서 시작하는 초. */
export function sceneOffsets(comp: Composition): number[] {
  const out: number[] = [];
  let t = 0;
  for (const s of comp.scenes) {
    out.push(t);
    t += sceneDuration(s);
  }
  return out;
}

/**
 * AI 가 스타일 값을 밀어 넣으려는 시도를 잡는다 (AGENTS.md §5).
 * 스키마만으로는 unknown payload 안쪽을 못 막으므로 한 번 더 훑는다.
 */
const FORBIDDEN_STYLE_KEYS = [
  'font', 'fontFamily', 'fontSize', 'color', 'colour', 'background', 'backgroundColor',
  'boxColor', 'outline', 'outlineColor', 'outlineWidth', 'stroke', 'strokeWidth',
  'bold', 'italic', 'opacity', 'easing', 'shadow', 'x', 'y', 'top', 'bottom', 'left', 'right',
];

export function assertNoStyleValues(comp: Composition): void {
  const bad: string[] = [];
  comp.scenes.forEach((scene, si) => {
    scene.overlays.forEach((ov, oi) => {
      for (const key of Object.keys(ov.payload)) {
        if (FORBIDDEN_STYLE_KEYS.includes(key)) {
          bad.push(`scenes[${si}].overlays[${oi}].payload.${key}`);
        }
      }
    });
  });
  if (bad.length) {
    throw new Error(
      `스타일 값은 Composition 에 넣을 수 없습니다. 템플릿이 정합니다 (AGENTS.md §1-2).\n` +
        bad.map((b) => `  - ${b}`).join('\n'),
    );
  }
}

/** 파싱 + 스타일 값 검사. 외부에서는 항상 이걸 쓴다. */
export function parseComposition(input: unknown): Composition {
  const comp = Composition.parse(input);
  assertNoStyleValues(comp);
  return comp;
}
