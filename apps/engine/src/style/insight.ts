import { type MemoryItem, type MemoryKind, type MemoryScope, type Reference, ReferenceInsight, type Segment } from '@madi/shared';
import { z } from 'zod';

/**
 * 완성본의 뜻 읽기 — 순수 함수. 파일 · DB · 프로세스를 모른다.
 *
 * 흐름 (기획안 §7 · §8 · §10):
 *   자막(타임코드) → insightPrompt → AI 한 턴 → parseInsight → 영상별 기억(ReferenceInsight)
 *   영상별 기억들 → memoryPrompt → AI 한 턴 → parseMemory → 제작자 기억(MemoryItem[])
 *   새 영상 편집 → retrieve → 관련 기억 + 비슷한 완성본 요약만 컨텍스트에
 *
 * 처음 읽을 때 넉넉히 쓰고, 그 뒤로는 저장한 메모만 꺼낸다. 영상을 매번 다시 읽지 않는다.
 */

const r1 = (n: number) => Math.round(n * 10) / 10;

function clock(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

/** 자막을 AI 가 읽을 한 줄씩으로. 너무 길면 앞뒤를 남기고 가운데를 줄인다 (긴 롱폼 대비). */
export function transcriptText(segments: Segment[], maxChars = 24_000): string {
  const lines = segments.map((s) => `[${clock(s.start)}–${clock(s.end)}] ${s.text.trim()}`);
  const full = lines.join('\n');
  if (full.length <= maxChars) return full;
  const head: string[] = [];
  const tail: string[] = [];
  let used = 0;
  for (let i = 0, j = lines.length - 1; i <= j && used < maxChars; ) {
    if (head.length <= tail.length) {
      head.push(lines[i]!);
      used += lines[i]!.length + 1;
      i++;
    } else {
      tail.unshift(lines[j]!);
      used += lines[j]!.length + 1;
      j--;
    }
  }
  return [...head, '… (가운데 생략) …', ...tail].join('\n');
}

export const INSIGHT_MARKER = '## 완성본 분석';
export const MEMORY_MARKER = '## 기억 정리';

/** 완성본 하나를 읽고 JSON 메모를 쓰게 하는 프롬프트. system 은 역할, prompt 는 재료. */
export function insightPrompt(ref: Pick<Reference, 'title' | 'stats'>, segments: Segment[]): { system: string; prompt: string } {
  const st = ref.stats;
  const system = [
    "너는 '마디'의 편집 분석가다. 운동 · 재활 · 스트레칭 영상 크리에이터의 **완성본**(이미 편집돼 올라간 영상)을 자막으로 읽고, 이 제작자가 영상을 어떻게 짜는지 메모를 남긴다.",
    '',
    '규칙:',
    '- 자막에 있는 것만 쓴다. 없는 운동 지식이나 의학적 조언을 지어내지 않는다.',
    '- 시각은 자막의 타임코드를 그대로 초(숫자)로 쓴다.',
    '- 동작 시범 중의 침묵, 주의사항, 횟수 · 조건 문장은 keepRanges 에 넣는다 — 잘라내면 뜻이 달라지는 곳이다.',
    '- shortCandidates 는 하나의 설명이 완결되는 구간만. 자극적인 한 문장만 따지 않는다. 각각 왜 골랐는지 한 줄.',
    '- terms 는 이 영상에 나온 운동 · 해부학 용어 (견갑골, 외회전, 흉추, 햄스트링 …). 자막이 잘못 적었을 법한 것도 바른 표기로.',
    '- tags 는 검색용 낱말: 부위 · 동작 · 고민 (예: 어깨, 견갑골, 거북목, 스쿼트). 3~8개.',
    '- 답은 JSON 하나만. 설명 · 마크다운 · 코드펜스 없이 `{` 로 시작해 `}` 로 끝낸다.',
  ].join('\n');
  const prompt = [
    INSIGHT_MARKER,
    '',
    `제목: ${ref.title}`,
    st ? `길이: ${clock(st.durationSec)} · ${st.aspect} · 컷 ${st.sceneCount}번` : '',
    '',
    '자막:',
    transcriptText(segments),
    '',
    '아래 모양의 JSON 으로 답해라 (값은 한국어):',
    JSON.stringify(
      {
        purpose: '이 영상이 전하려는 것 한두 문장',
        audience: '누구를 위한 영상인지 · 어떤 고민을 푸는지',
        hook: '처음 몇 초를 어떻게 여는지',
        tone: '말투',
        sections: [{ title: '구간 이름', start: 0, end: 30, kind: 'intro|setup|demo|qa|closing|other' }],
        keyPoints: ['핵심 설명 문장 그대로'],
        keepRanges: [{ start: 0, end: 0, why: '왜 지우면 안 되는지' }],
        cutCandidates: [{ start: 0, end: 0, why: '반복 설명 · NG 인 이유' }],
        shortCandidates: [{ start: 0, end: 0, title: '숏폼 제목', why: '왜 독립된 숏폼이 되는지' }],
        terms: ['용어'],
        subtitleNotes: '자막 길이 · 강조 방식',
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

/** 답에서 JSON 하나를 꺼낸다 (코드펜스 · 앞뒤 말이 붙어 있어도). */
export function extractJson(text: string): unknown | null {
  const fenced = /```(?:json)?\s*([\s\S]*?)```/.exec(text);
  const body = fenced?.[1] ?? text;
  const s = body.indexOf('{');
  const e = body.lastIndexOf('}');
  if (s < 0 || e <= s) return null;
  try {
    return JSON.parse(body.slice(s, e + 1));
  } catch {
    return null;
  }
}

const Loose = z.object({}).passthrough();

/**
 * AI 답 → ReferenceInsight. 시각은 영상 길이 안으로 잘라 넣고, 시작 ≥ 끝인 구간은 버린다.
 * 모양이 아예 아니면 null (실패로 남긴다 — 지어내지 않는다).
 */
export function parseInsight(text: string, opts: { provider: 'claude' | 'codex'; durationSec: number; now?: number }): ReferenceInsight | null {
  const raw = extractJson(text);
  if (!raw || !Loose.safeParse(raw).success) return null;
  const obj = raw as Record<string, unknown>;
  const dur = Math.max(0, opts.durationSec);
  const range = (v: unknown) => {
    if (typeof v !== 'object' || v === null) return null;
    const o = v as Record<string, unknown>;
    const start = Math.max(0, Math.min(dur, num(o['start'])));
    const end = Math.max(0, Math.min(dur, num(o['end'])));
    if (!(end > start)) return null;
    return { ...o, start: r1(start), end: r1(end) };
  };
  const arr = (v: unknown) => (Array.isArray(v) ? v : []);
  const strArr = (v: unknown, max: number) =>
    arr(v)
      .filter((x): x is string => typeof x === 'string' && x.trim().length > 0)
      .map((x) => x.trim().slice(0, max))
      .slice(0, 40);
  const candidate = {
    purpose: str(obj['purpose'], 300),
    audience: str(obj['audience'], 200),
    hook: str(obj['hook'], 200),
    tone: str(obj['tone'], 200),
    sections: arr(obj['sections'])
      .map(range)
      .filter((x): x is NonNullable<typeof x> => !!x)
      .map((o) => ({ title: str(o['title'], 60) || '구간', start: o.start, end: o.end, kind: sectionKind(o['kind']) }))
      .slice(0, 30),
    keyPoints: strArr(obj['keyPoints'], 200).slice(0, 20),
    keepRanges: arr(obj['keepRanges'])
      .map(range)
      .filter((x): x is NonNullable<typeof x> => !!x)
      .map((o) => ({ start: o.start, end: o.end, why: str(o['why'], 200) }))
      .slice(0, 30),
    cutCandidates: arr(obj['cutCandidates'])
      .map(range)
      .filter((x): x is NonNullable<typeof x> => !!x)
      .map((o) => ({ start: o.start, end: o.end, why: str(o['why'], 200) }))
      .slice(0, 30),
    shortCandidates: arr(obj['shortCandidates'])
      .map(range)
      .filter((x): x is NonNullable<typeof x> => !!x)
      .map((o) => ({ start: o.start, end: o.end, title: str(o['title'], 60) || '숏폼', why: str(o['why'], 200) }))
      .slice(0, 12),
    terms: uniq(strArr(obj['terms'], 40)).slice(0, 40),
    subtitleNotes: str(obj['subtitleNotes'], 200),
    tags: uniq(strArr(obj['tags'], 30).map(normTag)).slice(0, 12),
    provider: opts.provider,
    createdAt: opts.now ?? Date.now(),
  };
  if (!candidate.purpose) return null;
  const parsed = ReferenceInsight.safeParse(candidate);
  return parsed.success ? parsed.data : null;
}

/** 여러 완성본 메모 → 제작자 기억 프롬프트. 반복해서 나타나는 것만 남기라고 한다. */
export function memoryPrompt(refs: Pick<Reference, 'id' | 'title' | 'insight'>[]): { system: string; prompt: string } {
  const system = [
    "너는 '마디'의 편집 분석가다. 한 크리에이터의 완성본 여러 편에서 뽑은 메모를 읽고, **여러 편에 반복해서 나타나는 것만** 제작자 기억으로 남긴다.",
    '',
    '규칙:',
    '- 한 편에만 있는 것은 쓰지 않는다. 둘 이상에서 반복되는 방식 · 표현 · 기준만.',
    '- 한 줄은 편집할 때 바로 따를 수 있는 구체적인 문장으로 ("도입은 시청자의 불편함을 질문으로 던지고 시작한다").',
    '- kind: style(구성 · 말투 · 자막 방식) · keep(반드시 남기는 것) · avoid(피하는 표현 · 편집) · term(자주 쓰는 용어 — text 는 용어 자체).',
    '- scope: 모든 영상에 해당하면 all, 특정 부위 · 주제에서만이면 topic 과 topics(태그) 를 준다.',
    '- evidence 에는 근거가 된 완성본 id 들.',
    '- 8~20줄. 답은 JSON 하나만, `{` 로 시작해 `}` 로 끝낸다.',
  ].join('\n');
  const body = refs
    .filter((r) => r.insight)
    .map((r) => {
      const i = r.insight!;
      return [
        `### ${r.title} (id: ${r.id})`,
        `취지: ${i.purpose}`,
        i.audience ? `대상: ${i.audience}` : '',
        i.hook ? `도입: ${i.hook}` : '',
        i.tone ? `말투: ${i.tone}` : '',
        i.sections.length ? `구성: ${i.sections.map((s) => `${s.title}(${s.kind})`).join(' → ')}` : '',
        i.keepRanges.length ? `남긴 것: ${i.keepRanges.map((k) => k.why).join(' / ')}` : '',
        i.cutCandidates.length ? `줄인 것: ${i.cutCandidates.map((k) => k.why).join(' / ')}` : '',
        i.shortCandidates.length ? `숏폼 후보: ${i.shortCandidates.map((k) => `${k.title} — ${k.why}`).join(' / ')}` : '',
        i.terms.length ? `용어: ${i.terms.join(', ')}` : '',
        i.subtitleNotes ? `자막: ${i.subtitleNotes}` : '',
        `태그: ${i.tags.join(', ')}`,
      ]
        .filter(Boolean)
        .join('\n');
    })
    .join('\n\n');
  const prompt = [
    MEMORY_MARKER,
    '',
    body,
    '',
    '아래 모양의 JSON 으로 답해라:',
    JSON.stringify({ items: [{ text: '기억 한 줄', kind: 'style|keep|avoid|term', scope: 'all|topic', topics: ['태그'], evidence: ['완성본 id'] }] }, null, 2),
  ].join('\n');
  return { system, prompt };
}

export interface ParsedMemoryItem {
  text: string;
  kind: MemoryKind;
  scope: Exclude<MemoryScope, 'video'>;
  topics: string[];
  evidence: string[];
}

/** AI 답 → 제작자 기억 줄들. 근거 id 는 아는 완성본만 남긴다. */
export function parseMemory(text: string, knownRefIds: Set<string>): ParsedMemoryItem[] {
  const raw = extractJson(text) as { items?: unknown } | null;
  const items = Array.isArray(raw?.items) ? raw!.items : [];
  const out: ParsedMemoryItem[] = [];
  const seen = new Set<string>();
  for (const v of items) {
    if (typeof v !== 'object' || v === null) continue;
    const o = v as Record<string, unknown>;
    const t = str(o['text'], 300);
    if (!t || seen.has(t)) continue;
    seen.add(t);
    const kind = (['style', 'keep', 'avoid', 'term'] as const).find((k) => k === o['kind']) ?? 'style';
    const topics = uniq((Array.isArray(o['topics']) ? o['topics'] : []).filter((x): x is string => typeof x === 'string').map(normTag)).slice(0, 8);
    const scope: ParsedMemoryItem['scope'] = o['scope'] === 'topic' && topics.length ? 'topic' : 'all';
    const evidence = (Array.isArray(o['evidence']) ? o['evidence'] : []).filter((x): x is string => typeof x === 'string' && knownRefIds.has(x));
    out.push({ text: t, kind, scope, topics, evidence });
    if (out.length >= 30) break;
  }
  return out;
}

/** 새 영상에 붙일 것 — 관련 기억 + 비슷한 완성본 요약. */
export interface Retrieved {
  /** 항상 붙는 것(all) + 이 영상 주제에 맞는 것(topic) + 이 영상에만(video) */
  items: MemoryItem[];
  /** 태그가 겹치는 완성본 (많이 겹치는 순) */
  similar: Reference[];
  /** 이 영상에서 뽑은 낱말들 (디버그 · 표시용) */
  tags: string[];
}

/**
 * 새 영상의 제목 · 자막에서 낱말을 뽑아, 태그가 겹치는 기억과 완성본을 고른다.
 * 벡터 검색 없이 낱말 겹침으로 시작한다 (기획안 §11: 초기엔 태그 · 전문 검색으로 충분).
 */
export function retrieve(
  query: { videoId: string; title: string; transcript?: Segment[] | null },
  memory: MemoryItem[],
  refs: Reference[],
  opts: { maxSimilar?: number } = {},
): Retrieved {
  const vocab = uniq([...refs.flatMap((r) => r.insight?.tags ?? []), ...memory.flatMap((m) => m.topics)]);
  const text = `${query.title} ${(query.transcript ?? []).map((s) => s.text).join(' ')}`;
  const tags = vocab.filter((t) => t.length >= 2 && text.includes(t));
  const tagSet = new Set(tags);
  const items = memory.filter((m) => {
    if (m.scope === 'all') return true;
    if (m.scope === 'video') return m.videoId === query.videoId;
    return m.topics.some((t) => tagSet.has(t));
  });
  const similar = refs
    .filter((r) => r.insight)
    .map((r) => ({ r, score: r.insight!.tags.filter((t) => tagSet.has(t)).length }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score || b.r.updatedAt - a.r.updatedAt)
    .slice(0, opts.maxSimilar ?? 2)
    .map((x) => x.r);
  return { items, similar, tags };
}

/** 완성본 메모 한 편 → 프롬프트에 넣을 짧은 요약 (몇 줄). */
export function insightSummary(ref: Pick<Reference, 'title' | 'insight'>): string {
  const i = ref.insight;
  if (!i) return '';
  const lines = [`### 비슷한 완성본: ${ref.title}`, `- 취지: ${i.purpose}`];
  if (i.hook) lines.push(`- 도입: ${i.hook}`);
  if (i.sections.length) lines.push(`- 구성: ${i.sections.map((s) => `${s.title}(${clock(s.start)}~${clock(s.end)})`).join(' → ')}`);
  if (i.keepRanges.length) lines.push(`- 남긴 것: ${i.keepRanges.slice(0, 4).map((k) => k.why).join(' / ')}`);
  if (i.shortCandidates.length) lines.push(`- 숏폼으로 뽑은 방식: ${i.shortCandidates.slice(0, 3).map((k) => `${k.title} — ${k.why}`).join(' / ')}`);
  if (i.subtitleNotes) lines.push(`- 자막: ${i.subtitleNotes}`);
  return lines.join('\n');
}

const KIND_LABEL: Record<MemoryKind, string> = { style: '방식', keep: '반드시', avoid: '피함', term: '용어' };

/** 시스템 프롬프트의 "# 기억" 블록. 없으면 빈 문자열. */
export function memoryBlock(r: Retrieved): string {
  if (r.items.length === 0 && r.similar.length === 0) return '';
  const out = ['# 기억 (이 제작자의 완성본과 지난 편집에서 배운 것 — 제작 지침보다 세고, 사용자가 직접 쓴 규칙보다는 약하다)', ''];
  const terms = r.items.filter((m) => m.kind === 'term').map((m) => m.text);
  const rest = r.items.filter((m) => m.kind !== 'term');
  for (const m of rest) out.push(`- [${KIND_LABEL[m.kind]}${m.scope === 'video' ? ' · 이 영상만' : m.scope === 'topic' ? ` · ${m.topics.join(',')}` : ''}] ${m.text}`);
  if (terms.length) out.push(`- [용어] 이 채널이 쓰는 표기: ${terms.join(', ')} — 자막이 다르게 적었으면 이걸로 고친다.`);
  for (const ref of r.similar) out.push('', insightSummary(ref));
  return out.join('\n');
}

// ---- 작은 것들 ----

function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    // "1:23" 도 받아 준다
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

function sectionKind(v: unknown): ReferenceInsight['sections'][number]['kind'] {
  const kinds = ['intro', 'setup', 'demo', 'qa', 'closing', 'other'] as const;
  return kinds.find((k) => k === v) ?? 'other';
}

function normTag(t: string): string {
  return t.trim().replace(/^#/, '').toLowerCase();
}

function uniq<T>(xs: T[]): T[] {
  return [...new Set(xs)];
}
