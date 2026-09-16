import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { parseWhisperJson, tokensToWords } from '../src/workers/whisper.js';

const raw = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures/whisper-full.json'), 'utf8');

describe('whisper json', () => {
  it('서브워드 토큰을 어절로 묶고 특수 토큰은 버린다', () => {
    const { language, segments } = parseWhisperJson(raw);
    expect(language).toBe('ko');
    expect(segments).toHaveLength(2); // [_BEG_] 만 있는 문장은 버림
    const first = segments[0]!;
    expect(first.text).toBe('매트에 앉아서 한쪽 무릎을 세웁니다');
    expect(first.words.map((w) => w.text)).toEqual(['매트에', '앉아서', '한쪽', '무릎을', '세웁니다']);
    expect(first.words[0]).toMatchObject({ start: 0, end: 0.7, p: 0.8 }); // p 는 서브워드 중 최소
    expect(first.words[3]).toMatchObject({ start: 2, end: 2.5 });
    expect(first.start).toBe(0);
    expect(first.end).toBe(3.2);
  });
  it('토큰이 없는 문장은 문장 텍스트만', () => {
    const { segments } = parseWhisperJson(raw);
    expect(segments[1]).toMatchObject({ start: 3.6, end: 5, text: '발끝을 몸쪽으로 당기는 게 중요해요', words: [] });
  });
  it('tokensToWords 는 빈 입력에 빈 배열', () => {
    expect(tokensToWords([])).toEqual([]);
  });
});
