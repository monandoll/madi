import { type Cut, EditPlan, type Segment, type TimeRange, type Video } from '@madi/shared';
import { type Format, formatLine } from '../agent/playbook.js';
import { extractJson, transcriptText } from '../style/insight.js';

/**
 * 촬영본 편집안 — 순수 함수 (기획안 §4 · §13). 파일 · DB · 프로세스를 모른다.
 *
 *   자막 + 무음(가만히 / 동작 중) + 장면 전환 + 관련 기억 → planPrompt → AI 한 턴 → parsePlan → EditPlan
 *   EditPlan → planBlock (다음 채팅 요청의 프롬프트에) · planCuts (편집안대로 롱폼 만들기)
 *
 * 완성본 읽기(insight.ts)와 같은 방식이지만 질문이 다르다: "이 제작자는 어떻게 만드나"가 아니라 "이 촬영본을 어떻게 만들까".
 */

export const PLAN_MARKER = '## 편집안';

const r1 = (n: number) => Math.round(n * 10) / 10;

function clock(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

export interface PlanMaterial {
  video: Pick<Video, 'title' | 'durationSec' | 'width' | 'height' | 'hasAudio'>;
  segments: Segment[] | null;
  /** 잘라도 되는 침묵 (가만히 있었다) */
  silences: TimeRange[];
  /** 말은 없지만 동작이 이어지는 침묵 — 시범일 가능성 */
  movingSilences: TimeRange[];
  /** 장면 전환 시각 */
  scenes: number[];
  format: Format;
  /** "# 기억" 블록 (관련 기억 + 비슷한 완성본 요약). 없으면 빈 문자열. */
  memory: string;
}

/** 편집안을 JSON 으로 쓰게 하는 프롬프트. system 은 역할 · 기준, prompt 는 재료. */
export function planPrompt(m: PlanMaterial): { system: string; prompt: string } {
  const dur = m.video.durationSec ?? 0;
  const hasText = !!m.segments?.length;
  const system = [
    "너는 '마디'의 편집 기획자다. 운동 · 재활 · 스트레칭 크리에이터의 **촬영본**(아직 편집 안 한 영상)을 읽고 편집안 초안을 쓴다. 파일은 만들지 않는다 — 사용자가 보고 고른다.",
    '',
    '규칙:',
    '- 자막과 준 정보에 있는 것만 쓴다. 없는 운동 지식이나 의학적 조언을 지어내지 않는다. 자세의 정답을 판정하지 않는다.',
    '- 시각은 초(숫자). 영상 길이 안에서만.',
    '- sections: 이야기 순서. 구간마다 note 에 **어떻게 편집할지 한 줄** (예: "핵심 질문을 먼저 보이게", "시범 속도 그대로", "반복 설명은 첫 번째만").',
    '- keepRanges: 지우면 뜻이 달라지는 곳 — 동작 시범, 시범 중 침묵, 주의사항 · 횟수 · 조건 문장. "동작 중 침묵" 으로 준 구간은 여기 넣는다.',
    '- cutCandidates: 반복 설명(repeat) · NG · 되풀이(ng) · 잡담 · 촬영 세팅 멘트(aside) · 가만히 있던 침묵(silence). 이유 한 줄. keepRanges 와 겹치지 않게.',
    '- shortCandidates: 하나의 설명이 **완결**되는 구간만 (질문 → 설명 → 시범, 또는 동작 하나 + 횟수 · 주의). 자극적인 한 문장만 따지 않는다. 20~60초. 채널(reels · shorts · tiktok · any)과 이유.',
    '- terms: 자막이 잘못 적었을 법한 운동 · 해부학 용어의 바른 표기. tags: 검색용 낱말(부위 · 동작 · 고민) 3~8개.',
    '- 답은 JSON 하나만. 설명 · 마크다운 · 코드펜스 없이 `{` 로 시작해 `}` 로 끝낸다.',
    ...(m.memory ? ['', '이 제작자에 대해 아는 것 (편집안에 반영한다):', m.memory] : []),
  ].join('\n');
  const prompt = [
    PLAN_MARKER,
    '',
    `제목: ${m.video.title}`,
    `길이(초): ${Math.round(dur)} · ${clock(dur)} · ${m.video.width ?? '?'}x${m.video.height ?? '?'} · 소리 ${m.video.hasAudio === false ? '없음' : '있음'}`,
    `목표 포맷: ${formatLine(m.format)}`,
    m.scenes.length ? `장면 전환: ${m.scenes.map((t) => clock(t)).join(', ')}` : '장면 전환: 없음',
    m.silences.length ? `가만히 있던 침묵: ${m.silences.map((s) => `${clock(s.start)}–${clock(s.end)}`).join(', ')}` : '',
    m.movingSilences.length ? `동작 중 침묵 (말은 없지만 움직임이 이어짐 — 시범일 가능성): ${m.movingSilences.map((s) => `${clock(s.start)}–${clock(s.end)}`).join(', ')}` : '',
    '',
    hasText ? `자막:\n${transcriptText(m.segments!)}` : '자막: 없음 (소리가 없거나 말이 없다 — 장면 · 침묵으로만 판단한다)',
    '',
    '아래 모양의 JSON 으로 답해라 (값은 한국어):',
    JSON.stringify(
      {
        purpose: '이 영상이 전하려는 것 한두 문장',
        audience: '누구를 위한 영상인지',
        hook: '어디서 어떻게 시작할지',
        sections: [{ title: '구간 이름', start: 0, end: 30, kind: 'intro|setup|demo|qa|closing|other', note: '이 구간을 어떻게 편집할지' }],
        keepRanges: [{ start: 0, end: 0, why: '왜 지우면 안 되는지' }],
        cutCandidates: [{ start: 0, end: 0, why: '왜 빼도 되는지', kind: 'repeat|ng|aside|silence|other' }],
        shortCandidates: [{ start: 0, end: 0, title: '숏폼 제목', why: '왜 독립된 숏폼이 되는지', channel: 'reels|shorts|tiktok|any' }],
        terms: ['용어'],
        tags: ['태그'],
      },
      null,
      2,
    ),
  ]
    .filter((l) => l !== '')
    .join('\n');
  return { system, prompt };
}

/** AI 답 → EditPlan. 시각은 길이 안으로, 뒤집힌 구간은 버린다. 취지가 없으면 null (지어내지 않는다). */
export function parsePlan(
  text: string,
  opts: { videoId: string; provider: 'claude' | 'codex'; durationSec: number; fromTranscript: boolean; now?: number },
): EditPlan | null {
  const raw = extractJson(text);
  if (!raw || typeof raw !== 'object') return null;
  const obj = raw as Record<string, unknown>;
  const dur = Math.max(0, opts.durationSec);
  const range = (v: unknown): { raw: Record<string, unknown>; start: number; end: number } | null => {
    if (typeof v !== 'object' || v === null) return null;
    const o = v as Record<string, unknown>;
    const start = Math.max(0, Math.min(dur, num(o['start'])));
    const end = Math.max(0, Math.min(dur, num(o['end'])));
    if (!(end > start)) return null;
    return { raw: o, start: r1(start), end: r1(end) };
  };
  const arr = (v: unknown) => (Array.isArray(v) ? v : []);
  const ranges = (v: unknown) => arr(v).map(range).filter((x): x is NonNullable<typeof x> => !!x);
  const strArr = (v: unknown, max: number) =>
    uniq(
      arr(v)
        .filter((x): x is string => typeof x === 'string' && x.trim().length > 0)
        .map((x) => x.trim().slice(0, max)),
    );
  const candidate = {
    videoId: opts.videoId,
    purpose: str(obj['purpose'], 300),
    audience: str(obj['audience'], 200),
    hook: str(obj['hook'], 200),
    sections: ranges(obj['sections'])
      .map((o) => ({ title: str(o.raw['title'], 60) || '구간', start: o.start, end: o.end, kind: pick(o.raw['kind'], ['intro', 'setup', 'demo', 'qa', 'closing', 'other'] as const, 'other'), note: str(o.raw['note'], 200) }))
      .slice(0, 40),
    keepRanges: ranges(obj['keepRanges'])
      .map((o) => ({ start: o.start, end: o.end, why: str(o.raw['why'], 200) }))
      .slice(0, 40),
    cutCandidates: ranges(obj['cutCandidates'])
      .map((o) => ({ start: o.start, end: o.end, why: str(o.raw['why'], 200), kind: pick(o.raw['kind'], ['repeat', 'ng', 'aside', 'silence', 'other'] as const, 'other') }))
      .slice(0, 60),
    shortCandidates: ranges(obj['shortCandidates'])
      .map((o) => ({ start: o.start, end: o.end, title: str(o.raw['title'], 60) || '숏폼', why: str(o.raw['why'], 200), channel: pick(o.raw['channel'], ['reels', 'shorts', 'tiktok', 'any'] as const, 'any') }))
      .slice(0, 12),
    terms: strArr(obj['terms'], 40).slice(0, 40),
    tags: strArr(obj['tags'], 30)
      .map((t) => t.replace(/^#/, '').toLowerCase())
      .slice(0, 12),
    fromTranscript: opts.fromTranscript,
    provider: opts.provider,
    createdAt: opts.now ?? Date.now(),
  };
  if (!candidate.purpose) return null;
  const parsed = EditPlan.safeParse(candidate);
  return parsed.success ? parsed.data : null;
}

/**
 * 편집안대로 잘라낼 컷: 잘라낼 후보에서 남길 구간과 겹치는 부분을 뺀다.
 * 사용자가 "이대로 만들기"를 눌렀을 때만 쓴다 — 편집안 자체는 파일을 만들지 않는다.
 */
export function planCuts(plan: Pick<EditPlan, 'cutCandidates' | 'keepRanges'>, durationSec: number): Cut[] {
  const out: Cut[] = [];
  for (const c of plan.cutCandidates) {
    let pieces: TimeRange[] = [{ start: Math.max(0, c.start), end: Math.min(durationSec, c.end) }];
    for (const k of plan.keepRanges) {
      pieces = pieces.flatMap((p) => {
        if (k.end <= p.start || k.start >= p.end) return [p];
        const left = k.start > p.start ? [{ start: p.start, end: k.start }] : [];
        const right = k.end < p.end ? [{ start: k.end, end: p.end }] : [];
        return [...left, ...right];
      });
    }
    for (const p of pieces) if (p.end - p.start >= 0.3) out.push({ start: r1(p.start), end: r1(p.end), reason: 'ai' });
  }
  return out.sort((a, b) => a.start - b.start);
}

const CUT_LABEL: Record<EditPlan['cutCandidates'][number]['kind'], string> = { repeat: '반복', ng: 'NG', aside: '잡담', silence: '침묵', other: '기타' };

/** 다음 채팅 요청의 프롬프트에 붙일 편집안 요약. 에이전트가 숏폼 · 컷을 고를 때 이걸 먼저 본다. */
export function planBlock(plan: EditPlan): string {
  const out = ['# 이 영상의 편집안 (이미 읽어 둔 것 — 구간을 고를 때 여기서 시작한다. 사용자가 다르게 말하면 사용자를 따른다)', '', `취지: ${plan.purpose}`];
  if (plan.hook) out.push(`시작: ${plan.hook}`);
  if (plan.sections.length) {
    out.push('구성:');
    for (const s of plan.sections) out.push(`- ${clock(s.start)}–${clock(s.end)} ${s.title}${s.note ? ` — ${s.note}` : ''}`);
  }
  if (plan.keepRanges.length) out.push(`남길 구간: ${plan.keepRanges.map((k) => `${clock(k.start)}–${clock(k.end)} (${k.why})`).join(' · ')}`);
  if (plan.cutCandidates.length) out.push(`잘라낼 후보: ${plan.cutCandidates.map((c) => `${clock(c.start)}–${clock(c.end)} [${CUT_LABEL[c.kind]}] ${c.why}`).join(' · ')}`);
  if (plan.shortCandidates.length) {
    out.push('숏폼 후보:');
    for (const s of plan.shortCandidates) out.push(`- ${clock(s.start)}–${clock(s.end)} ${s.title} (${s.channel}) — ${s.why}`);
  }
  if (plan.terms.length) out.push(`용어 표기: ${plan.terms.join(', ')}`);
  return out.join('\n');
}

// ---- 작은 것들 ----

function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const m = /^(\d+):(\d{1,2})(?:\.(\d+))?$/.exec(v.trim());
    if (m) return Number(m[1]) * 60 + Number(m[2]) + (m[3] ? Number(`0.${m[3]}`) : 0);
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function str(v: unknown, max: number): string {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}

function pick<T extends string>(v: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.find((k) => k === v) ?? fallback;
}

function uniq<T>(xs: T[]): T[] {
  return [...new Set(xs)];
}
