import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { dropHallucinations, isNoiseText, parseWhisperJson, termsPrompt, tokensToWords } from '../src/workers/whisper.js';

const FIX = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures');
const raw = fs.readFileSync(path.join(FIX, 'whisper-full.json'), 'utf8');

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
  it('Buffer 로 읽으면 토큰 경계에서 잘린 한글이 되살아난다 (utf8 로 읽으면 � 가 된다)', () => {
    const buf = fs.readFileSync(path.join(FIX, 'whisper-split-bytes.json'));
    expect(buf.toString('utf8')).toContain('\uFFFD'); // 파일 자체는 utf8 로 못 읽는 바이트가 있다
    const { segments } = parseWhisperJson(buf);
    const first = segments[0]!;
    expect(first.text).toBe('무릎을 세웁니다');
    expect(first.words.map((w) => w.text)).toEqual(['무릎을', '세웁니다']);
    expect(first.words[0]).toMatchObject({ start: 0, end: 0.7, p: 0.8 });
    for (const seg of segments) {
      expect(seg.text).not.toContain('\uFFFD');
      for (const w of seg.words) expect(w.text).not.toContain('\uFFFD');
    }
  });
});

describe('무음에서 지어낸 문장', () => {
  it('괄호 태그·기호·반복은 소음', () => {
    expect(isNoiseText('[음악]')).toBe(true);
    expect(isNoiseText('(박수)')).toBe(true);
    expect(isNoiseText('...')).toBe(true);
    expect(isNoiseText('♪♪')).toBe(true);
    expect(isNoiseText('네네네네네네네네')).toBe(true);
    expect(isNoiseText('감사합니다감사합니다감사합니다감사합니다')).toBe(true);
    expect(isNoiseText('매트에 앉아서 한쪽 무릎을 세웁니다')).toBe(false);
    expect(isNoiseText('번째]')).toBe(false); // 글자가 있으면 글로 본다 — 무음 구간 판정이 잡는다
  });
  it('문장 구간의 80% 이상이 무음이면 버리고, 말이 있는 구간은 남긴다', () => {
    const buf = fs.readFileSync(path.join(FIX, 'whisper-split-bytes.json'));
    const { segments } = parseWhisperJson(buf);
    expect(segments.map((s) => s.text)).toEqual(['무릎을 세웁니다', '[음악]', '번째]', '네네네네네네네네']);
    // 2초부터 끝까지 무음
    const kept = dropHallucinations(segments, [{ start: 1.9, end: 10 }]);
    expect(kept.map((s) => s.text)).toEqual(['무릎을 세웁니다']);
    // 무음이 없으면 태그·반복만 빠진다
    expect(dropHallucinations(segments, []).map((s) => s.text)).toEqual(['무릎을 세웁니다', '번째]']);
    // 절반만 무음이면 남긴다
    expect(dropHallucinations(segments.slice(2, 3), [{ start: 5.0, end: 5.3 }])).toHaveLength(1);
  });
});

describe('termsPrompt', () => {
  it('용어를 whisper 첫 프롬프트 한 줄로. 없으면 빈 문자열, 중복 · 한 글자는 빼고 40개까지', () => {
    expect(termsPrompt([])).toBe('');
    expect(termsPrompt(['견갑골', ' 견갑골', '외회전', 'x'])).toBe('운동 · 재활 설명 영상. 용어: 견갑골, 외회전.');
    expect(termsPrompt(Array.from({ length: 60 }, (_, i) => `용어${i}`)).split(', ')).toHaveLength(40);
  });
});
