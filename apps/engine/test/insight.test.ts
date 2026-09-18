/**
 * 완성본의 뜻 읽기 — 순수 함수.
 * AI 답이 지저분해도(코드펜스 · 앞뒤 말 · "1:23" 시각) 메모가 되고, 이상한 구간은 버리며, 새 영상엔 관련 기억만 붙는다.
 */
import { describe, expect, it } from 'vitest';
import type { MemoryItem, Reference, Segment } from '@madi/shared';
import { extractJson, insightPrompt, insightSummary, memoryBlock, memoryPrompt, parseInsight, parseMemory, retrieve, transcriptText } from '../src/style/insight.js';

const seg = (start: number, end: number, text: string): Segment => ({ id: `s${start}`, start, end, text, words: [] });
const SEGS = [seg(0, 3, '안녕하세요 오늘은 어깨 스트레칭입니다'), seg(3, 8, '견갑골을 뒤로 모으고'), seg(8, 15, '열 번 반복하세요 통증이 있으면 멈추세요')];

const ref = (over: Partial<Reference> = {}): Reference => ({
  id: 'r1',
  path: '/x/a.mp4',
  fileName: 'a.mp4',
  title: '어깨 스트레칭',
  sizeBytes: 1,
  status: 'done',
  source: 'folder',
  url: null,
  stats: { durationSec: 15, width: 1080, height: 1920, hasAudio: true, aspect: '9:16', silenceCount: 0, maxSilenceSec: 0, sceneCount: 3, cutsPerMin: 12, sceneTimes: [3, 8, 12], pair: null },
  insight: null,
  excluded: false,
  error: null,
  createdAt: 1,
  updatedAt: 1,
  ...over,
});

describe('transcriptText', () => {
  it('타임코드와 글을 한 줄씩', () => {
    expect(transcriptText(SEGS)).toBe('[0:00–0:03] 안녕하세요 오늘은 어깨 스트레칭입니다\n[0:03–0:08] 견갑골을 뒤로 모으고\n[0:08–0:15] 열 번 반복하세요 통증이 있으면 멈추세요');
  });

  it('너무 길면 앞뒤를 남기고 가운데를 줄인다', () => {
    const many = Array.from({ length: 400 }, (_, i) => seg(i, i + 1, `문장 ${i} 입니다 조금 길게 씁니다`));
    const t = transcriptText(many, 2000);
    expect(t.length).toBeLessThan(2400);
    expect(t).toContain('문장 0 ');
    expect(t).toContain('문장 399 ');
    expect(t).toContain('가운데 생략');
  });
});

describe('insightPrompt', () => {
  it('자막과 답 모양을 같이 준다, 지어내지 말라고 한다', () => {
    const { system, prompt } = insightPrompt(ref(), SEGS);
    expect(system).toContain('지어내지 않는다');
    expect(prompt).toContain('## 완성본 분석');
    expect(prompt).toContain('[0:03–0:08] 견갑골을 뒤로 모으고');
    expect(prompt).toContain('"shortCandidates"');
    // 장면 전환 시각과 제목 · 내용 관계도 묻는다 (기획안 §7 · §8.1)
    expect(prompt).toContain('장면 전환: 0:03, 0:08, 0:12');
    expect(prompt).toContain('"titleNote"');
    expect(system).toContain('titleNote');
  });
});

describe('extractJson', () => {
  it('코드펜스 · 앞뒤 말이 있어도 꺼낸다', () => {
    expect(extractJson('네, 정리했습니다.\n```json\n{"a":1}\n```\n끝')).toEqual({ a: 1 });
    expect(extractJson('{"a":{"b":2}} 이상입니다')).toEqual({ a: { b: 2 } });
    expect(extractJson('JSON 없음')).toBeNull();
  });
});

describe('parseInsight', () => {
  const good = {
    purpose: '어깨가 뻐근한 사람을 위한 스트레칭',
    audience: '사무직',
    hook: '불편함을 먼저 말한다',
    tone: '존댓말 설명조',
    sections: [
      { title: '도입', start: 0, end: 3, kind: 'intro' },
      { title: '시범', start: '0:03', end: '0:15', kind: 'demo' },
    ],
    keyPoints: ['견갑골을 뒤로 모으고'],
    keepRanges: [{ start: 8, end: 15, why: '횟수와 주의사항' }],
    cutCandidates: [],
    shortCandidates: [{ start: 3, end: 15, title: '견갑골 모으기', why: '설명과 시범이 완결' }],
    terms: ['견갑골', ' 견갑골 ', '외회전'],
    subtitleNotes: '짧게',
    titleNote: '제목의 "견갑골"을 0:03 부터 시범으로 보여 준다',
    tags: ['어깨', '#견갑골', '어깨'],
  };

  it('모양 그대로 메모가 된다 ("1:23" 시각도, 중복 용어 · 태그는 하나로)', () => {
    const i = parseInsight(`\`\`\`json\n${JSON.stringify(good)}\n\`\`\``, { provider: 'claude', durationSec: 15, now: 5 })!;
    expect(i).not.toBeNull();
    expect(i.purpose).toBe(good.purpose);
    expect(i.sections[1]).toEqual({ title: '시범', start: 3, end: 15, kind: 'demo' });
    expect(i.terms).toEqual(['견갑골', '외회전']);
    expect(i.tags).toEqual(['어깨', '견갑골']);
    expect(i.titleNote).toBe(good.titleNote);
    expect(i.provider).toBe('claude');
    expect(i.createdAt).toBe(5);
  });

  it('영상 길이 밖 · 뒤집힌 구간은 버린다', () => {
    const i = parseInsight(JSON.stringify({ ...good, keepRanges: [{ start: 20, end: 30, why: 'x' }, { start: 9, end: 4, why: 'y' }, { start: 10, end: 99, why: 'z' }] }), {
      provider: 'codex',
      durationSec: 15,
    })!;
    expect(i.keepRanges).toEqual([{ start: 10, end: 15, why: 'z' }]);
  });

  it('취지가 없거나 JSON 이 아니면 null (지어내지 않는다)', () => {
    expect(parseInsight('모르겠습니다', { provider: 'claude', durationSec: 15 })).toBeNull();
    expect(parseInsight(JSON.stringify({ tags: ['a'] }), { provider: 'claude', durationSec: 15 })).toBeNull();
  });
});

describe('memoryPrompt / parseMemory', () => {
  const a = ref({ id: 'a', title: 'A', insight: parseInsight(JSON.stringify({ purpose: 'p', tags: ['어깨'] }), { provider: 'claude', durationSec: 10 }) });
  const b = ref({ id: 'b', title: 'B', insight: parseInsight(JSON.stringify({ purpose: 'q', tags: ['무릎'] }), { provider: 'claude', durationSec: 10 }) });

  it('완성본 메모들을 id 와 함께 넘기고 반복되는 것만 남기라 한다', () => {
    const { system, prompt } = memoryPrompt([a, b]);
    expect(system).toContain('반복해서 나타나는 것만');
    expect(prompt).toContain('### A (id: a)');
    expect(prompt).toContain('### B (id: b)');
  });

  it('답을 기억 줄로. 모르는 근거 id 는 버리고, topic 인데 topics 가 없으면 all', () => {
    const text = JSON.stringify({
      items: [
        { text: '도입은 질문으로 연다', kind: 'style', scope: 'all', evidence: ['a', 'zzz'] },
        { text: '시범 중 침묵은 남긴다', kind: 'keep', scope: 'topic', topics: [], evidence: ['b'] },
        { text: '견갑골', kind: 'term', scope: 'topic', topics: ['어깨'], evidence: [] },
        { text: '도입은 질문으로 연다', kind: 'style', scope: 'all' },
        { text: '', kind: 'style' },
      ],
    });
    const items = parseMemory(text, new Set(['a', 'b']));
    expect(items).toEqual([
      { text: '도입은 질문으로 연다', kind: 'style', scope: 'all', topics: [], evidence: ['a'] },
      { text: '시범 중 침묵은 남긴다', kind: 'keep', scope: 'all', topics: [], evidence: ['b'] },
      { text: '견갑골', kind: 'term', scope: 'topic', topics: ['어깨'], evidence: [] },
    ]);
  });
});

describe('retrieve / memoryBlock', () => {
  const mem = (over: Partial<MemoryItem>): MemoryItem => ({ id: 'm', text: 't', kind: 'style', scope: 'all', topics: [], videoId: null, source: 'reference', status: 'approved', evidence: [], createdAt: 1, ...over });
  const memory = [
    mem({ id: '1', text: '도입은 질문으로', scope: 'all' }),
    mem({ id: '2', text: '어깨는 시범을 두 번', scope: 'topic', topics: ['어깨'] }),
    mem({ id: '3', text: '무릎은 천천히', scope: 'topic', topics: ['무릎'] }),
    mem({ id: '4', text: '이 영상만 인트로 없이', scope: 'video', videoId: 'v1', source: 'feedback' }),
    mem({ id: '5', text: '견갑골', kind: 'term', scope: 'all' }),
  ];
  const shoulder = ref({ id: 'a', title: '어깨 완성본', insight: parseInsight(JSON.stringify({ purpose: 'p', hook: '질문', tags: ['어깨', '견갑골'] }), { provider: 'claude', durationSec: 10 }) });
  const knee = ref({ id: 'b', title: '무릎 완성본', insight: parseInsight(JSON.stringify({ purpose: 'q', tags: ['무릎'] }), { provider: 'claude', durationSec: 10 }) });

  it('제목 · 자막에 나온 태그로 관련 기억과 비슷한 완성본만 고른다', () => {
    const r = retrieve({ videoId: 'v1', title: '어깨 루틴', transcript: [seg(0, 1, '견갑골을 모으세요')] }, memory, [shoulder, knee]);
    expect(r.tags.sort()).toEqual(['견갑골', '어깨']);
    expect(r.items.map((m) => m.id)).toEqual(['1', '2', '4', '5']);
    expect(r.similar.map((x) => x.id)).toEqual(['a']);
  });

  it('다른 영상의 video 기억은 안 붙는다', () => {
    const r = retrieve({ videoId: 'v2', title: '무릎', transcript: null }, memory, [shoulder, knee]);
    expect(r.items.map((m) => m.id)).toEqual(['1', '3', '5']);
    expect(r.similar.map((x) => x.id)).toEqual(['b']);
  });

  it('기억 블록: 종류 · 범위 표시, 용어는 한 줄로, 비슷한 완성본 요약이 붙는다', () => {
    const r = retrieve({ videoId: 'v1', title: '어깨', transcript: null }, memory, [shoulder, knee]);
    const block = memoryBlock(r);
    expect(block).toContain('# 기억');
    expect(block).toContain('[방식] 도입은 질문으로');
    expect(block).toContain('[방식 · 어깨] 어깨는 시범을 두 번');
    expect(block).toContain('[방식 · 이 영상만] 이 영상만 인트로 없이');
    expect(block).toContain('[용어] 이 채널이 쓰는 표기: 견갑골');
    expect(block).toContain('### 비슷한 완성본: 어깨 완성본');
    expect(block).toContain('- 도입: 질문');
  });

  it('아무것도 없으면 빈 블록', () => {
    expect(memoryBlock(retrieve({ videoId: 'v', title: 'x' }, [], []))).toBe('');
    expect(insightSummary(ref())).toBe('');
  });
});
