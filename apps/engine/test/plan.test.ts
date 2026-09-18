/**
 * 촬영본 편집안 — 순수 함수. 재료가 프롬프트에 다 들어가고, 지저분한 답도 편집안이 되며, 남길 구간은 컷에서 빠진다.
 */
import { describe, expect, it } from 'vitest';
import type { EditPlan, Segment } from '@madi/shared';
import { parsePlan, planBlock, planCuts, planPrompt } from '../src/plan/prompt.js';

const seg = (start: number, end: number, text: string): Segment => ({ id: `s${start}`, start, end, text, words: [] });
const video = { title: '어깨 스트레칭 촬영본', durationSec: 120, width: 1920, height: 1080, hasAudio: true };

describe('planPrompt', () => {
  it('자막 · 침묵(가만히 / 동작 중) · 장면 · 기억이 다 들어가고, 파일을 만들지 말라고 한다', () => {
    const { system, prompt } = planPrompt({
      video,
      segments: [seg(0, 3, '안녕하세요'), seg(3, 10, '견갑골을 뒤로 모으고')],
      silences: [{ start: 10, end: 12 }],
      movingSilences: [{ start: 12, end: 20 }],
      scenes: [12, 60],
      format: 'long',
      memory: '# 기억\n- [방식] 도입은 질문으로',
    });
    expect(system).toContain('파일은 만들지 않는다');
    expect(system).toContain('지어내지 않는다');
    expect(system).toContain('# 기억');
    expect(prompt).toContain('## 편집안');
    expect(prompt).toContain('길이(초): 120');
    expect(prompt).toContain('16:9');
    expect(prompt).toContain('장면 전환: 0:12, 1:00');
    expect(prompt).toContain('가만히 있던 침묵: 0:10–0:12');
    expect(prompt).toContain('동작 중 침묵');
    expect(prompt).toContain('0:12–0:20');
    expect(prompt).toContain('[0:03–0:10] 견갑골을 뒤로 모으고');
    expect(prompt).toContain('"shortCandidates"');
  });

  it('자막이 없으면 그렇다고 말한다', () => {
    const { system, prompt } = planPrompt({ video: { ...video, hasAudio: false }, segments: null, silences: [], movingSilences: [], scenes: [], format: 'reels', memory: '' });
    expect(prompt).toContain('자막: 없음');
    expect(system).not.toContain('# 기억');
  });
});

describe('parsePlan', () => {
  const good = {
    purpose: '어깨가 뻐근한 사람을 위한 스트레칭',
    hook: '인사를 빼고 동작 설명부터',
    sections: [
      { title: '도입', start: 0, end: 5, kind: 'intro', note: '인사는 빼고' },
      { title: '시범', start: '0:05', end: '2:00', kind: 'demo', note: '속도 그대로' },
    ],
    keepRanges: [{ start: 20, end: 60, why: '시범' }],
    cutCandidates: [
      { start: 0, end: 3, why: '인사', kind: 'aside' },
      { start: 90, end: 80, why: '뒤집힘' },
      { start: 100, end: 500, why: '길이 밖', kind: 'repeat' },
    ],
    shortCandidates: [{ start: 5, end: 40, title: '견갑골 모으기', why: '완결', channel: 'reels' }, { start: 40, end: 70, title: '둘', why: '', channel: 'x' }],
    terms: ['견갑골', '견갑골'],
    tags: ['#어깨', '스트레칭'],
  };

  it('코드펜스 · "1:23" 시각 · 모르는 값이 있어도 편집안이 된다', () => {
    const p = parsePlan(`네.\n\`\`\`json\n${JSON.stringify(good)}\n\`\`\``, { videoId: 'v', provider: 'claude', durationSec: 120, fromTranscript: true, now: 7 })!;
    expect(p).not.toBeNull();
    expect(p.sections[1]).toEqual({ title: '시범', start: 5, end: 120, kind: 'demo', note: '속도 그대로' });
    expect(p.cutCandidates).toEqual([
      { start: 0, end: 3, why: '인사', kind: 'aside' },
      { start: 100, end: 120, why: '길이 밖', kind: 'repeat' },
    ]);
    expect(p.shortCandidates[1]!.channel).toBe('any');
    expect(p.terms).toEqual(['견갑골']);
    expect(p.tags).toEqual(['어깨', '스트레칭']);
    expect(p).toMatchObject({ videoId: 'v', provider: 'claude', fromTranscript: true, createdAt: 7 });
  });

  it('취지가 없거나 JSON 이 아니면 null', () => {
    expect(parsePlan('모르겠습니다', { videoId: 'v', provider: 'claude', durationSec: 10, fromTranscript: false })).toBeNull();
    expect(parsePlan('{"tags":["a"]}', { videoId: 'v', provider: 'claude', durationSec: 10, fromTranscript: false })).toBeNull();
  });
});

describe('planCuts / planBlock', () => {
  const plan = parsePlan(
    JSON.stringify({
      purpose: 'p',
      sections: [{ title: '도입', start: 0, end: 10, kind: 'intro', note: '핵심부터' }],
      keepRanges: [{ start: 4, end: 6, why: '주의사항' }],
      cutCandidates: [
        { start: 0, end: 2, why: '인사', kind: 'aside' },
        { start: 3, end: 8, why: '반복', kind: 'repeat' },
        { start: 5.9, end: 6.1, why: '너무 짧아짐' },
      ],
      shortCandidates: [{ start: 2, end: 10, title: '한 동작', why: '완결', channel: 'shorts' }],
      terms: ['견갑골'],
    }),
    { videoId: 'v', provider: 'codex', durationSec: 10, fromTranscript: true },
  ) as EditPlan;

  it('남길 구간과 겹치는 부분은 컷에서 빠진다 (가운데가 갈라진다)', () => {
    expect(planCuts(plan, 10)).toEqual([
      { start: 0, end: 2, reason: 'ai' },
      { start: 3, end: 4, reason: 'ai' },
      { start: 6, end: 8, reason: 'ai' },
    ]);
  });

  it('프롬프트 블록에 구성 · 남길 곳 · 후보 · 용어가 한 줄씩', () => {
    const b = planBlock(plan);
    expect(b).toContain('# 이 영상의 편집안');
    expect(b).toContain('- 0:00–0:10 도입 — 핵심부터');
    expect(b).toContain('남길 구간: 0:04–0:06 (주의사항)');
    expect(b).toContain('[반복] 반복');
    expect(b).toContain('- 0:02–0:10 한 동작 (shorts) — 완결');
    expect(b).toContain('용어 표기: 견갑골');
  });
});
