import { describe, expect, it } from 'vitest';
import type { Segment } from '@madi/shared';
import { mergeSubtitleLines } from '../src/agent/subtitles.js';
import { classifyAgentError } from '../src/agent/runner.js';
import { withKnownDirs } from '../src/agent/detect.js';

const seg = (start: number, end: number, text: string): Segment => ({ id: `${start}`, start, end, text, words: [] });

describe('자막 문장 고치기', () => {
  const existing = [seg(0, 2, '���번째'), seg(2.5, 4, '무릎을 세웁니다'), seg(4.5, 6, '천천히 내려요')];

  it('겹치는 문장을 사용자 문장으로 바꾸고 나머지는 둔다', () => {
    const out = mergeSubtitleLines(existing, [{ start: 0, end: 2, text: '안녕하세요 앱 소개합니다' }]);
    expect(out.map((s) => s.text)).toEqual(['안녕하세요 앱 소개합니다', '무릎을 세웁니다', '천천히 내려요']);
    expect(out[0]).toMatchObject({ start: 0, end: 2, words: [] });
    expect(out[0]!.id).not.toBe('0');
  });

  it('자막이 없거나 replaceAll 이면 준 줄이 전부', () => {
    expect(mergeSubtitleLines([], [{ start: 1, end: 3, text: '첫 줄' }]).map((s) => s.text)).toEqual(['첫 줄']);
    const out = mergeSubtitleLines(existing, [{ start: 0, end: 6, text: '한 줄로' }], true);
    expect(out).toHaveLength(1);
  });

  it('살짝 스치는 문장은 두고, 절반 넘게 겹치면 뺀다', () => {
    const out = mergeSubtitleLines(existing, [{ start: 3.9, end: 5.9, text: '새 줄' }]);
    // 4.5–6 (천천히) 는 1.4/1.5 겹침 → 빠짐, 2.5–4 (무릎) 는 0.1/1.5 → 남음
    expect(out.map((s) => s.text)).toEqual(['���번째', '무릎을 세웁니다', '새 줄']);
  });

  it('시각이 뒤집히거나 너무 짧은 줄, 빈 글을 바로잡는다', () => {
    const out = mergeSubtitleLines([], [
      { start: 5, end: 3, text: '거꾸로' },
      { start: 1, end: 1.1, text: '  짧음 ' },
      { start: 2, end: 3, text: '   ' },
    ]);
    expect(out.map((s) => [s.start, s.end, s.text])).toEqual([
      [1, 1.3, '짧음'],
      [3, 5, '거꾸로'],
    ]);
  });
});

describe('AI CLI 오류 분류', () => {
  it('로그인·node·기타', () => {
    expect(classifyAgentError('exit 1: Error: Not logged in. Run `codex login`')).toBe('ai_login');
    expect(classifyAgentError('401 Unauthorized')).toBe('ai_login');
    expect(classifyAgentError('exit 127: env: node: No such file or directory')).toBe('ai_node_missing');
    expect(classifyAgentError('stream disconnected')).toBe('ai_failed');
  });
  it('withKnownDirs 는 PATH 를 지우지 않고 있는 폴더만 덧붙인다', () => {
    const env = withKnownDirs({ PATH: '/only/me' });
    const parts = env['PATH']!.split(process.platform === 'win32' ? ';' : ':');
    expect(parts[0]).toBe('/only/me');
    expect(parts.length).toBeGreaterThan(1);
    expect(new Set(parts).size).toBe(parts.length);
    if (process.platform !== 'win32') expect(parts).toContain('/usr/bin');
  });
});
