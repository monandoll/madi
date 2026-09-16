import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import type { ReferenceStats, Segment } from '@madi/shared';
import { StyleProfile } from '../src/agent/style.js';
import { aggregate, aspectOf, learnedRuleLines, looksLikeSameVideo, normalizeTitle, pairDiff, scanReferenceFoldersForTest } from './learn-helpers.js';
import { tempHome } from './helpers.js';

const stat = (o: Partial<ReferenceStats>): ReferenceStats => ({
  durationSec: 30,
  width: 1080,
  height: 1920,
  hasAudio: true,
  aspect: '9:16',
  silenceCount: 3,
  maxSilenceSec: 0.8,
  sceneCount: 4,
  cutsPerMin: 8,
  pair: null,
  ...o,
});

describe('learn', () => {
  it('비율', () => {
    expect(aspectOf(1080, 1920)).toBe('9:16');
    expect(aspectOf(1920, 1080)).toBe('16:9');
    expect(aspectOf(1080, 1080)).toBe('other');
  });

  it('완성본 통계를 합친다: 비율 다수결, 무음 기준은 남아 있는 최대 무음의 90분위 + 0.1', () => {
    const l = aggregate([stat({}), stat({ durationSec: 40, maxSilenceSec: 1.2 }), stat({ durationSec: 20, maxSilenceSec: 0.5, cutsPerMin: 4 })], 1000)!;
    expect(l).toMatchObject({ count: 3, aspect: '9:16', medianDurationSec: 30, cutsPerMin: 8, keptRatio: null, learnedAt: 1000 });
    expect(l.silenceMinSec).toBe(1.3);
    expect(aggregate([])).toBeNull();
    expect(aggregate([stat({ aspect: '9:16' }), stat({ aspect: '16:9' })])!.aspect).toBe('mixed');
    // 소리 없는 완성본만 있으면 기본 0.7, 상한 3초
    expect(aggregate([stat({ hasAudio: false })])!.silenceMinSec).toBe(0.7);
    expect(aggregate([stat({ maxSilenceSec: 9 })])!.silenceMinSec).toBe(3);
  });

  it('배운 값 → 문장', () => {
    const lines = learnedRuleLines({ count: 3, aspect: '9:16', medianDurationSec: 32, silenceMinSec: 1.3, cutsPerMin: 8, keptRatio: 0.62, introTrimSec: 4, learnedAt: 0 });
    expect(lines[0]).toBe('(배움) 완성본 3개 기준: 세로 9:16, 보통 32초 길이.');
    expect(lines[1]).toBe('(배움) 무음은 1.3초를 넘으면 잘라낸다.');
    expect(lines[2]).toBe('(배움) 컷은 1분에 8번쯤.');
    expect(lines[3]).toBe('(배움) 원본의 62% 정도만 남긴다. 앞부분은 4초쯤 잘라낸다.');
  });

  it('제목 정규화로 원본과 완성본을 짝짓는다', () => {
    expect(normalizeTitle('햄스트링 스트레칭_완성.mp4')).toBe('햄스트링 스트레칭');
    expect(normalizeTitle('Hamstring Final v2')).toBe('hamstring');
    expect(looksLikeSameVideo('햄스트링 스트레칭 숏폼1', '햄스트링 스트레칭')).toBe(true);
    expect(looksLikeSameVideo('어깨 루틴', '햄스트링 스트레칭')).toBe(false);
    expect(looksLikeSameVideo('v2', 'v3')).toBe(false);
  });

  it('자막 LCS 로 원본의 어디가 남았는지 본다', () => {
    const seg = (i: number, text: string): Segment => ({ id: `s${i}`, start: i * 5, end: i * 5 + 4, text, words: [] });
    const original = ['안녕하세요', '오늘은 햄스트링', '잡담 하나', '무릎을 펴고', '골반부터 접으세요', '끝 인사'].map((t, i) => seg(i, t));
    const finished = ['오늘은 햄스트링', '무릎을 펴고', '골반부터 접으세요'].map((t, i) => seg(i, t));
    const d = pairDiff(original, finished, 30, 'v1')!;
    expect(d).toMatchObject({ videoId: 'v1', introTrimSec: 5, outroTrimSec: 30 - 24, cutCount: 1 });
    expect(d.keptRatio).toBe(0.5); // 6문장 중 3문장, 길이 같음
    expect(pairDiff(original, [seg(0, '전혀 다른 말')], 30, 'v1')).toBeNull();
    expect(pairDiff([], finished, 30, 'v1')).toBeNull();
  });

  it('StyleProfile: 학습 블록은 사용자 규칙 뒤에 붙고, 지울 수 없고, 다시 배우면 바뀐다', () => {
    const home = tempHome('madi-learn-');
    const s = new StyleProfile(path.join(home, 'style'));
    const userRules = s.rulesList().length;
    s.setLearned({ count: 2, aspect: '9:16', medianDurationSec: 30, silenceMinSec: 1.1, cutsPerMin: 6, keptRatio: null, introTrimSec: null, learnedAt: 1 }, ['(배움) 하나', '(배움) 둘']);
    let list = s.rulesList();
    expect(list.filter((r) => r.learned).map((r) => r.text)).toEqual(['(배움) 하나', '(배움) 둘']);
    expect(s.params().silenceMinSec).toBe(1.1);
    expect(s.params().learned?.count).toBe(2);
    // 사용자 규칙은 블록 앞에 들어간다
    s.appendRule('인트로는 3초만');
    list = s.rulesList();
    expect(list[userRules]).toEqual({ text: '인트로는 3초만', learned: false });
    expect(list[list.length - 1]).toEqual({ text: '(배움) 둘', learned: true });
    // 배운 줄은 못 지운다, 사용자 줄은 지운다
    expect(s.removeRule(list.length - 1)).toBe(false);
    expect(s.removeRule(userRules)).toBe(true);
    expect(s.rulesList().some((r) => r.text === '인트로는 3초만')).toBe(false);
    // 다시 배우면 블록 교체, 없애면 기본값으로
    s.setLearned(null, []);
    expect(s.rulesList().some((r) => r.learned)).toBe(false);
    expect(s.params().silenceMinSec).toBe(0.7);
    expect(fs.readFileSync(s.mdPath, 'utf8')).not.toContain('learned:start');
    fs.rmSync(home, { recursive: true, force: true });
  });

  it('완성본 폴더 스캔: 영상만, 하위 2단계, 숨김 제외', () => {
    const home = tempHome('madi-scan-');
    fs.mkdirSync(path.join(home, 'a', 'b', 'c'), { recursive: true });
    for (const f of ['a/x.mp4', 'a/y.txt', 'a/.hidden.mp4', 'a/b/z.mov', 'a/b/c/deep.mp4']) fs.writeFileSync(path.join(home, f), '');
    expect(scanReferenceFoldersForTest([path.join(home, 'a')]).map((p) => path.relative(home, p).split(path.sep).join('/'))).toEqual(['a/b/z.mov', 'a/x.mp4']);
    fs.rmSync(home, { recursive: true, force: true });
  });
});
