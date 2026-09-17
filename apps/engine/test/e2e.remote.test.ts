/**
 * 밖에서 접속 e2e: 빠른 터널을 켜면 주소가 생기고(가짜 cloudflared), 밖에서 들어온 요청은 6자리 숫자를 먼저 묻는다.
 * "밖에서 들어온" 것은 cloudflared 가 붙이는 헤더로 가른다 — 터널도 127.0.0.1 로 붙기 때문이다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { HealthResponse, RemoteResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let engine: Engine;

/** 터널을 지나온 척: cloudflared 가 늘 붙이는 헤더 */
const REMOTE = { 'cf-connecting-ip': '203.0.113.9', 'cf-ray': '8a0f-ICN' };

const get = (p: string, headers: Record<string, string> = {}) => fetch(`${engine.url}${p}`, { headers });
const post = (p: string, body: unknown, headers: Record<string, string> = {}) =>
  fetch(`${engine.url}${p}`, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
const setMode = (mode: 'off' | 'quick' | 'token', extra: Record<string, unknown> = {}) =>
  fetch(`${engine.url}/api/settings`, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ remoteMode: mode, ...extra }) });
const remote = async (headers: Record<string, string> = {}) => RemoteResponse.parse(await (await get('/api/remote', headers)).json());
const errCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

beforeAll(async () => {
  home = tempHome('madi-remote-e2e-');
  process.env['MADI_QUIET'] = '1';
  process.env['MADI_CLOUDFLARED'] = path.join(FIXTURES, 'fake-cloudflared.mjs');
  process.env['MADI_FAKE_TUNNEL_HOST'] = 'madi-e2e';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  delete process.env['MADI_CLOUDFLARED'];
  delete process.env['MADI_FAKE_TUNNEL_HOST'];
  fs.rmSync(home, { recursive: true, force: true });
});

describe('밖에서 접속', () => {
  it('처음엔 꺼져 있고, 이 PC 에서는 숫자 없이 다 보인다', async () => {
    const r = await remote();
    expect(r.mode).toBe('off');
    expect(r.status).toBe('off');
    expect(r.url).toBeNull();
    expect(r.pin).toBeNull();
    expect(r.devices).toBe(0);
    expect((await get('/api/videos')).status).toBe(200);
  });

  it('꺼져 있으면 밖에서 들어와도 막힌다 (터널이 없으니 올 일도 없지만)', async () => {
    const res = await get('/api/videos', REMOTE);
    expect(res.status).toBe(401);
    expect(await errCode(res)).toBe('needs_pair');
  });

  it('빠른 터널을 켜면 계정·토큰 없이 주소가 생긴다', async () => {
    expect((await setMode('quick')).status).toBe(200);
    await waitFor(async () => (await remote()).status === 'running');
    const r = await remote();
    expect(r.mode).toBe('quick');
    expect(r.url).toBe('https://madi-e2e.trycloudflare.com');
    expect(r.error).toBeNull();
    // 같은 주소가 health 에도 실린다
    const health = HealthResponse.parse(await (await get('/api/health')).json());
    expect(health.tunnel).toEqual({ status: 'running', error: null, url: 'https://madi-e2e.trycloudflare.com' });
  });

  it('숫자는 이 PC 화면에서만 보인다', async () => {
    const mine = await remote();
    expect(mine.pin).toMatch(/^\d{6}$/);
    // 짝짓기 전에는 밖에서 상태조차 못 본다 (숫자를 훔쳐 볼 길이 없다)
    expect((await get('/api/remote', REMOTE)).status).toBe(401);
  });

  it('밖에서 온 요청은 숫자를 맞혀야 통과한다', async () => {
    expect((await get('/api/videos', REMOTE)).status).toBe(401);
    expect((await get('/media/proxies/none.mp4', REMOTE)).status).toBe(401);
    // 실시간 알림(WebSocket)도 막힌다 — 짝짓기 전에 남의 영상 제목이 흘러가면 안 된다
    expect((await get('/ws', REMOTE)).status).toBe(401);

    const wrongPin = await post('/api/remote/pair', { pin: '000000' }, REMOTE);
    expect([403, 200]).toContain(wrongPin.status); // 000000 이 진짜 숫자일 확률 백만분의 일
    const pin = (await remote()).pin!;
    const paired = await post('/api/remote/pair', { pin }, REMOTE);
    expect(paired.status).toBe(200);
    const cookie = paired.headers.get('set-cookie') ?? '';
    expect(cookie).toContain('madi_pair=');
    expect(cookie).toContain('HttpOnly');

    const token = /madi_pair=([^;]+)/.exec(cookie)![1]!;
    const withCookie = { ...REMOTE, cookie: `madi_pair=${token}` };
    expect((await get('/api/videos', withCookie)).status).toBe(200);
    expect((await get('/ws', withCookie)).status).not.toBe(401);
    // 짝지은 뒤에는 밖에서도 상태가 보이지만 숫자는 여전히 안 보인다
    const theirs = await remote(withCookie);
    expect(theirs.url).toBe('https://madi-e2e.trycloudflare.com');
    expect(theirs.pin).toBeNull();
    expect((await remote()).devices).toBe(1);
    // 표가 없는 다른 폰은 여전히 막힌다
    expect((await get('/api/videos', { ...REMOTE, cookie: 'madi_pair=someone-else' })).status).toBe(401);
  });

  it('숫자가 아니면 400, 꺼져 있으면 409', async () => {
    const bad = await post('/api/remote/pair', { pin: 12345 }, REMOTE);
    expect(bad.status).toBe(400);
    expect(await errCode(bad)).toBe('bad_pin');

    await setMode('off');
    const off = await post('/api/remote/pair', { pin: '123456' }, REMOTE);
    expect(off.status).toBe(409);
    expect(await errCode(off)).toBe('remote_off');
  });

  it('끄면 터널이 내려가고 짝지은 폰도 끊긴다', async () => {
    await waitFor(async () => (await remote()).status === 'off');
    const r = await remote();
    expect(r.mode).toBe('off');
    expect(r.url).toBeNull();
    expect(r.devices).toBe(0);
    expect(fs.existsSync(path.join(home, 'pairs.json'))).toBe(true);
  });

  it('다시 켜면 새 숫자로 다시 짝짓는다', async () => {
    await setMode('quick');
    await waitFor(async () => (await remote()).status === 'running');
    const pin = (await remote()).pin!;
    const paired = await post('/api/remote/pair', { pin }, REMOTE);
    expect(paired.status).toBe(200);
    expect((await remote()).devices).toBe(1);
    await setMode('off');
  });
});
