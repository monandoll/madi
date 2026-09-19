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

const FAKE_YTDLP = path.join(FIXTURES, 'fake-ytdlp.mjs');
const FAKE_CLAUDE = path.join(FIXTURES, 'fake-claude.mjs');

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
  process.env['MADI_YTDLP'] = FAKE_YTDLP;
  process.env['MADI_CLAUDE_BIN'] = FAKE_CLAUDE;
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  delete process.env['MADI_CLAUDE_BIN'];
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

  it('링크로 배우기: 받아서(가짜 yt-dlp) 분석하고 배운 수에 더해진다', async () => {
    await waitFor(async () => (await style()).linkImport, 10_000);
    // 주소가 아니면 400
    expect((await api('/api/style/links', json('POST', { url: '햄스트링 루틴 영상' }))).status).toBe(400);
    const res = await api<StyleResponse>('/api/style/links', json('POST', { url: '봐봐 https://www.youtube.com/shorts/gaps 이거' }));
    expect(res.status).toBe(200);
    const link = res.body.references.find((r) => r.source === 'link')!;
    expect(link).toMatchObject({ url: 'https://www.youtube.com/shorts/gaps', title: '유튜브 영상' });
    expect(['queued', 'downloading']).toContain(link.status);
    await waitFor(async () => (await style()).references.find((r) => r.id === link.id)?.status === 'done', 60_000);
    const s = await style();
    const done = s.references.find((r) => r.id === link.id)!;
    expect(done.title).toBe('gaps');
    expect(done.path).toBe(path.join(home, 'references', `${link.id}.mp4`));
    expect(fs.existsSync(done.path)).toBe(true);
    expect(done.stats).toMatchObject({ aspect: '16:9', hasAudio: true });
    expect(s.learned?.count).toBe(4);
    // 같은 링크를 또 넣어도 하나
    await api('/api/style/links', json('POST', { url: 'https://www.youtube.com/shorts/gaps' }));
    expect((await style()).references.filter((r) => r.source === 'link')).toHaveLength(1);
    // 폴더를 다시 훑어도 링크 완성본은 missing 이 되지 않는다
    await api('/api/style/relearn', { method: 'POST' });
    await waitFor(async () => (await style()).learned?.count === 4, 30_000);
    expect((await style()).references.find((r) => r.id === link.id)?.status).toBe('done');
  });

  it('링크로 배우기: 못 가져오면 이유 코드가 남고, 다시 배우기가 다시 받는다, 빼면 파일도 사라진다', async () => {
    const res = await api<StyleResponse>('/api/style/links', json('POST', { url: 'https://www.instagram.com/reel/private' }));
    expect(res.status).toBe(200);
    const link = res.body.references.find((r) => r.url === 'https://www.instagram.com/reel/private')!;
    await waitFor(async () => (await style()).references.find((r) => r.id === link.id)?.status === 'failed', 30_000);
    let s = await style();
    expect(s.references.find((r) => r.id === link.id)).toMatchObject({ status: 'failed', error: 'link_private', title: '인스타그램 영상' });
    expect(s.learned?.count).toBe(4);
    // 다시 배우기 → 다시 받는다 (또 실패)
    await api('/api/style/relearn', { method: 'POST' });
    await waitFor(async () => {
      const r = (await style()).references.find((r) => r.id === link.id);
      return r?.status === 'queued' || r?.status === 'downloading';
    }, 10_000);
    await waitFor(async () => (await style()).references.find((r) => r.id === link.id)?.status === 'failed', 30_000);
    // 빼기
    expect((await api(`/api/style/references/${link.id}`, { method: 'DELETE' })).status).toBe(200);
    expect((await api(`/api/style/references/${link.id}`, { method: 'DELETE' })).status).toBe(404);
    const okLink = (await style()).references.find((r) => r.source === 'link' && r.status === 'done')!;
    expect(fs.existsSync(okLink.path)).toBe(true);
    await api(`/api/style/references/${okLink.id}`, { method: 'DELETE' });
    expect(fs.existsSync(okLink.path)).toBe(false);
    s = await style();
    expect(s.references.filter((r) => r.source === 'link')).toHaveLength(0);
    expect(s.learned?.count).toBe(3);
  });
});

/**
 * 기획안 §7 · §8 · §12: AI 가 연결되면 완성본의 뜻을 읽어 메모하고, 여러 편에서 반복되는 것만 기억으로 남기며,
 * 사용자가 그 기억을 보고 지울 수 있다. AI 없이 배운 것(숫자)은 그대로.
 */
describe('완성본의 뜻 읽기 · 기억', () => {
  it('AI 를 연결하고 다시 배우기 → 완성본마다 메모, 반복되는 것만 기억', { timeout: 150_000 }, async () => {
    const before = await style();
    expect(before.insightOn).toBe(false);
    expect(before.references.every((r) => r.insight === null)).toBe(true);

    await api('/api/settings', json('PATCH', { ai: { provider: 'claude' } }));
    expect((await style()).insightOn).toBe(true);
    // 자막은 analyze 가 whisper 로 뜬다. whisper 가 없는 PC(이 샌드박스)에서도 뜻 읽기를 검사하려고 자막을 직접 넣어 둔다.
    for (const r of before.references.filter((x) => x.stats?.hasAudio)) {
      if (!engine.refs.segmentsOf(r.id)) {
        engine.refs.update(r.id, {
          segments: [
            { id: 's1', start: 0, end: 1.5, text: '안녕하세요 오늘은 스트레칭입니다', words: [] },
            { id: 's2', start: 1.5, end: 4, text: '천천히 호흡하면서 열 번 반복하세요', words: [] },
          ],
        });
      }
    }
    // 숫자만 배운 완성본(자막 있음)을 이제 읽는다
    await api('/api/style/relearn', { method: 'POST' });
    await waitFor(async () => {
      const s = await style();
      const withAudio = s.references.filter((r) => r.stats?.hasAudio);
      return withAudio.length > 0 && withAudio.every((r) => r.insight);
    }, 90_000);
    const s = await style();
    const one = s.references.find((r) => r.title === '햄스트링 완성')!;
    expect(one.insight).toMatchObject({ provider: 'claude', tags: expect.arrayContaining(['햄스트링']) });
    expect(one.insight!.purpose).toContain('햄스트링');
    expect(one.insight!.shortCandidates[0]).toMatchObject({ title: '햄스트링 한 동작' });
    // 화면 시트도 보여 줬다 (기획안 §10)
    expect(one.insight!.visual).toBe('사람이 가운데 크게, 자막은 아래');
    expect(one.insight!.frameTimes.length).toBeGreaterThan(0);
    // 시각은 영상 길이 안
    for (const k of one.insight!.keepRanges) expect(k.end).toBeLessThanOrEqual(one.stats!.durationSec);
    // 소리 없는 완성본은 읽을 게 없다
    expect(s.references.find((r) => r.title === '무음 완성')!.insight).toBeNull();

    // 완성본 메모들 → 제작자 기억 (2초 뒤 한 번)
    await waitFor(async () => (await style()).memory.some((m) => m.source === 'reference'), 30_000);
    const mem = (await style()).memory;
    expect(mem.map((m) => m.text)).toContain('동작 시범 중 말이 없는 구간은 잘라내지 않는다');
    const topic = mem.find((m) => m.scope === 'topic')!;
    expect(topic).toMatchObject({ topics: ['어깨'], kind: 'style', source: 'reference' });
    expect(mem.find((m) => m.kind === 'term')?.text).toBe('견갑골');
    // 근거는 아는 완성본 id 만
    for (const m of mem) for (const id of m.evidence) expect(s.references.some((r) => r.id === id)).toBe(true);
    // 완성본에서 온 것은 전부 "제안" — 확인하기 전엔 편집에 안 쓴다 (기획안 §12)
    expect(mem.filter((m) => m.source === 'reference').every((m) => m.status === 'proposed')).toBe(true);
    expect(engine.styleService.recall({ id: 'v-shoulder', title: '어깨 가동성 루틴' } as never)).not.toContain('[방식 · 어깨]');
  });

  it('제안은 확인해야 편집에 쓰인다 (한 줄씩 · 모두)', async () => {
    const before = (await style()).memory;
    const one = before.find((m) => m.scope === 'topic')!;
    const patched = StyleResponse.parse((await api(`/api/style/memory/${one.id}`, json('PATCH', { status: 'approved' }))).body);
    expect(patched.memory.find((m) => m.id === one.id)?.status).toBe('approved');
    expect(patched.memory.filter((m) => m.status === 'proposed').length).toBe(before.length - 1);
    expect(engine.styleService.recall({ id: 'v-shoulder', title: '어깨 가동성 루틴' } as never)).toContain('[방식 · 어깨]');
    expect((await api(`/api/style/memory/${one.id}`, json('PATCH', {}))).status).toBe(400);
    expect((await api('/api/style/memory/없음', json('PATCH', { status: 'approved' }))).status).toBe(404);
    const all = StyleResponse.parse((await api('/api/style/memory/approve', json('POST', {}))).body);
    expect(all.memory.every((m) => m.status === 'approved')).toBe(true);
  });

  it('기억 글을 고치면 그 글로 바뀌고 확인된 것으로 남는다', async () => {
    const m = (await style()).memory.find((x) => x.kind === 'keep')!;
    const r = StyleResponse.parse((await api(`/api/style/memory/${m.id}`, json('PATCH', { text: '시범 중 침묵은 2초까지 남긴다' }))).body);
    expect(r.memory.find((x) => x.id === m.id)).toMatchObject({ text: '시범 중 침묵은 2초까지 남긴다', status: 'approved', source: 'reference' });
    expect(engine.styleService.recall({ id: 'v', title: '아무 영상' } as never)).toContain('시범 중 침묵은 2초까지 남긴다');
  });

  it('완성본을 학습에서 빼면 숫자에서도 기억 검색에서도 빠지고, 다시 넣으면 돌아온다', async () => {
    const s0 = await style();
    const shoulder = s0.references.find((r) => r.title === '어깨 루틴_final')!;
    const count = s0.learned!.count;
    const off = StyleResponse.parse((await api(`/api/style/references/${shoulder.id}`, json('PATCH', { excluded: true }))).body);
    expect(off.references.find((r) => r.id === shoulder.id)?.excluded).toBe(true);
    expect(off.learned?.count).toBe(count - 1);
    expect(engine.styleService.recall({ id: 'v-shoulder', title: '어깨 가동성 루틴' } as never)).not.toContain('비슷한 완성본: 어깨 루틴_final');
    expect((await api('/api/style/references/없음', json('PATCH', { excluded: true }))).status).toBe(404);
    const on = StyleResponse.parse((await api(`/api/style/references/${shoulder.id}`, json('PATCH', { excluded: false }))).body);
    expect(on.references.find((r) => r.id === shoulder.id)?.excluded).toBe(false);
    expect(on.learned?.count).toBe(count);
    expect(engine.styleService.recall({ id: 'v-shoulder', title: '어깨 가동성 루틴' } as never)).toContain('비슷한 완성본: 어깨 루틴_final');
  });

  it('편집할 때는 관련 기억만 붙는다 (어깨 영상엔 어깨 기억, 다른 영상엔 안 붙음)', async () => {
    const shoulder = { id: 'v-shoulder', title: '어깨 가동성 루틴' } as never;
    const knee = { id: 'v-knee', title: '무릎 재활 1단계' } as never;
    const a = engine.styleService.recall(shoulder);
    const b = engine.styleService.recall(knee);
    expect(a).toContain('# 기억');
    expect(a).toContain('[방식 · 어깨] 어깨는 견갑골 움직임이 보이게 잡는다');
    expect(a).toContain('[용어] 이 채널이 쓰는 표기: 견갑골');
    expect(a).toContain('### 비슷한 완성본: 어깨 루틴_final');
    expect(b).toContain('# 기억');
    expect(b).not.toContain('어깨는 견갑골');
    expect(b).not.toContain('비슷한 완성본');
    // 시스템 프롬프트에도 그대로
    expect(engine.agent.systemPrompt(shoulder)).toContain('[방식 · 어깨]');
  });

  it('직접 쓴 기억은 바로 쓰이고, 어느 것이든 빼면 사라진다 (뺀 제안은 다시 배워도 안 돌아온다)', async () => {
    const added = StyleResponse.parse((await api('/api/style/memory', json('POST', { text: '도입은 3초 안에 동작', scope: 'all' }))).body);
    const mine = added.memory.find((m) => m.source === 'user')!;
    expect(mine).toMatchObject({ text: '도입은 3초 안에 동작', kind: 'style', scope: 'all', status: 'approved' });
    expect((await api('/api/style/memory', json('POST', { text: 'x' }))).status).toBe(400);
    const ref = added.memory.find((m) => m.source === 'reference')!;
    const after = StyleResponse.parse((await api(`/api/style/memory/${ref.id}`, { method: 'DELETE' })).body);
    expect(after.memory.some((m) => m.id === ref.id)).toBe(false);
    expect((await api('/api/style/memory/없음', { method: 'DELETE' })).status).toBe(404);
    expect(engine.styleService.recall({ id: 'v', title: '아무 영상' } as never)).toContain('도입은 3초 안에 동작');
    expect(engine.memory.dismissed()).toContain(ref.text);
    // 다시 정리해도 뺀 글은 돌아오지 않는다
    await engine.styleService.rememory();
    expect((await style()).memory.some((m) => m.text === ref.text)).toBe(false);
  });

  it('완성본을 다 빼면 완성본에서 온 기억도 비운다', async () => {
    for (const r of (await style()).references.filter((x) => x.source === 'link')) await api(`/api/style/references/${r.id}`, { method: 'DELETE' });
    await api('/api/settings', json('PATCH', { referenceFolders: [] }));
    await waitFor(async () => {
      const s = await style();
      return s.references.length === 0 && !s.memory.some((m) => m.source === 'reference');
    }, 15_000);
    // 직접 쓴 것은 남는다
    expect((await style()).memory.some((m) => m.source === 'user')).toBe(true);
  });

  it('전부 지우기', async () => {
    await api('/api/style/memory', json('POST', { text: '하나 더' }));
    expect((await style()).memory.length).toBeGreaterThan(0);
    const r = StyleResponse.parse((await api('/api/style/memory', { method: 'DELETE' })).body);
    expect(r.memory).toEqual([]);
  });
});
