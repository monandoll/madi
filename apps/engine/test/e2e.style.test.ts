/**
 * 5단계 e2e: 완성본 폴더 → 분석(진짜 ffmpeg) → 배운 값이 style.md 와 params 에 들어가고, 무음 기준이 바뀐다.
 * 자막 짝 맞추기는 whisper 가 있을 때만 (없으면 pair 는 null 로 넘어간다).
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { StyleResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let refDir: string;
let engine: Engine;

const api = async <T>(p: string, init?: RequestInit): Promise<{ status: number; body: T }> => {
  const res = await fetch(`${engine.url}${p}`, init);
  return { status: res.status, body: (await res.json()) as T };
};
const json = (method: string, body?: unknown): RequestInit => ({ method, headers: { 'content-type': 'application/json' }, body: body === undefined ? null : JSON.stringify(body) });
const style = async () => StyleResponse.parse((await api('/api/style')).body);

beforeAll(async () => {
  home = tempHome('madi-style-');
  refDir = path.join(home, 'finished');
  fs.mkdirSync(refDir);
  process.env['MADI_QUIET'] = '1';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('스타일 학습', () => {
  it('처음엔 기본 규칙만, 배운 것 없음', async () => {
    const s = await style();
    expect(s.learned).toBeNull();
    expect(s.references).toEqual([]);
    expect(s.rules.length).toBeGreaterThan(0);
    expect(s.rules.every((r) => !r.learned)).toBe(true);
    expect(s.silenceMinSec).toBe(0.7);
  });

  it('규칙 추가 → 목록에, 빼기 → 사라짐, 잘못된 index 는 400', async () => {
    const before = (await style()).rules.length;
    const added = StyleResponse.parse((await api('/api/style/rules', json('POST', { rule: '인트로는 3초만' }))).body);
    expect(added.rules).toHaveLength(before + 1);
    expect(added.rules[before]).toEqual({ text: '인트로는 3초만', learned: false });
    expect(fs.readFileSync(engine.style.mdPath, 'utf8')).toContain('- 인트로는 3초만');
    const removed = StyleResponse.parse((await api(`/api/style/rules/${before}`, { method: 'DELETE' })).body);
    expect(removed.rules).toHaveLength(before);
    expect((await api('/api/style/rules/99', { method: 'DELETE' })).status).toBe(400);
    expect((await api('/api/style/rules', json('POST', { rule: 'x' }))).status).toBe(400);
  });

  it('완성본 폴더를 정하면 분석해서 배운다 (가로 16:9 샘플 2개)', async () => {
    fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(refDir, '햄스트링 완성.mp4'));
    fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(refDir, '어깨 루틴_final.mp4'));
    fs.writeFileSync(path.join(refDir, 'notes.txt'), 'x');
    await api('/api/settings', json('PATCH', { referenceFolders: [refDir] }));
    await waitFor(async () => {
      const s = await style();
      return s.references.length === 2 && s.references.every((r) => r.status === 'done');
    }, 90_000);
    const s = await style();
    expect(s.references.map((r) => r.title).sort()).toEqual(['어깨 루틴_final', '햄스트링 완성']);
    for (const r of s.references) {
      expect(r.stats).toMatchObject({ aspect: '16:9', hasAudio: true, pair: null });
      expect(r.stats!.durationSec).toBeGreaterThan(4);
    }
    expect(s.learned).toMatchObject({ count: 2, aspect: '16:9' });
    // 무음 샘플(2초 무음 두 번)이 "남아 있는 무음" 기준을 올린다
    expect(s.silenceMinSec).toBeGreaterThan(0.7);
    expect(s.silenceMinSec).toBe(s.learned!.silenceMinSec);
    const learnedRules = s.rules.filter((r) => r.learned);
    expect(learnedRules[0]!.text).toContain('(배움) 완성본 2개 기준: 가로 16:9');
    expect(learnedRules[1]!.text).toContain(`무음은 ${s.silenceMinSec}초를 넘으면`);
    const md = fs.readFileSync(engine.style.mdPath, 'utf8');
    expect(md).toContain('<!-- learned:start -->');
    expect(md.indexOf('- 자막은 문장 단위')).toBeLessThan(md.indexOf('learned:start'));
    // 배운 줄은 못 지운다
    const idx = s.rules.findIndex((r) => r.learned);
    expect((await api(`/api/style/rules/${idx}`, { method: 'DELETE' })).status).toBe(400);
    // 에이전트 시스템 프롬프트에도 들어간다
    expect(engine.agent.systemPrompt()).toContain('(배움) 완성본 2개 기준');
  });

  it('폴더를 빼면 완성본이 목록에서 빠지고 배운 값도 사라진다', async () => {
    await api('/api/settings', json('PATCH', { referenceFolders: [] }));
    await waitFor(async () => (await style()).references.length === 0, 10_000);
    const s = await style();
    expect(s.learned).toBeNull();
    expect(s.silenceMinSec).toBe(0.7);
    expect(s.rules.some((r) => r.learned)).toBe(false);
    // 다시 넣으면 다시 분석 없이(크기 같음) 되살아난다
    await api('/api/settings', json('PATCH', { referenceFolders: [refDir] }));
    await waitFor(async () => (await style()).learned?.count === 2, 60_000);
  });

  it('다시 배우기는 폴더를 다시 훑는다 (새 파일 반영)', async () => {
    fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(refDir, '무음 완성.mp4'));
    await api('/api/style/relearn', { method: 'POST' });
    await waitFor(async () => (await style()).learned?.count === 3, 60_000);
    const s = await style();
    expect(s.references.find((r) => r.title === '무음 완성')?.stats?.hasAudio).toBe(false);
  });
});
