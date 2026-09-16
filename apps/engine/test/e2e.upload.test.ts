/**
 * 폰에서 올리기 e2e: tus 프로토콜로 두 조각에 나눠 올리면 첫 영상 폴더에 파일이 생기고, 감시가 갤러리에 등록한다.
 * 영상 폴더가 없거나 영상이 아니면 만들기부터 400.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { VideosResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { freePort, SAMPLE_5S, tempHome, waitFor } from './helpers.js';

let home: string;
let folder: string;
let engine: Engine;

const TUS = { 'Tus-Resumable': '1.0.0' };
const meta = (name: string) => `filename ${Buffer.from(name).toString('base64')},filetype ${Buffer.from('video/mp4').toString('base64')}`;
const settings = (body: unknown) => fetch(`${engine.url}/api/settings`, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const create = (name: string, size: number) => fetch(`${engine.url}/api/uploads`, { method: 'POST', headers: { ...TUS, 'Upload-Length': String(size), 'Upload-Metadata': meta(name) } });
const videos = async () => VideosResponse.parse(await (await fetch(`${engine.url}/api/videos`)).json()).videos;

beforeAll(async () => {
  home = tempHome('madi-upload-');
  folder = path.join(home, 'Videos');
  fs.mkdirSync(folder);
  process.env['MADI_QUIET'] = '1';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('폰에서 올리기', () => {
  it('영상 폴더가 없으면 no_folder, 영상이 아니면 not_video', async () => {
    await settings({ watchFolders: [], setupDone: true });
    const r1 = await create('a.mp4', 10);
    expect(r1.status).toBe(400);
    expect(await r1.text()).toBe('no_folder');
    await settings({ watchFolders: [folder], setupDone: true });
    const r2 = await create('notes.txt', 10);
    expect(r2.status).toBe(400);
    expect(await r2.text()).toBe('not_video');
  });

  it('두 조각으로 올리면 폴더에 생기고 갤러리에 등록된다 (이어 올리기 offset 확인)', async () => {
    const data = fs.readFileSync(SAMPLE_5S);
    const created = await create('폰 촬영 햄스트링.mp4', data.length);
    expect(created.status).toBe(201);
    const location = created.headers.get('location')!;
    expect(location).toMatch(/^\/api\/uploads\/[A-Za-z0-9_-]+$/);
    const url = `${engine.url}${location}`;
    const half = Math.floor(data.length / 2);
    const patch = (offset: number, chunk: Buffer) =>
      fetch(url, { method: 'PATCH', headers: { ...TUS, 'Upload-Offset': String(offset), 'Content-Type': 'application/offset+octet-stream' }, body: new Uint8Array(chunk) });
    const p1 = await patch(0, data.subarray(0, half));
    expect(p1.status).toBe(204);
    expect(p1.headers.get('upload-offset')).toBe(String(half));
    // 끊겼다 치고 offset 을 물어본다
    const head = await fetch(url, { method: 'HEAD', headers: TUS });
    expect(head.headers.get('upload-offset')).toBe(String(half));
    const p2 = await patch(half, data.subarray(half));
    expect(p2.status).toBe(204);
    expect(decodeURIComponent(p2.headers.get('x-madi-file') ?? '')).toBe('폰 촬영 햄스트링.mp4');

    const dest = path.join(folder, '폰 촬영 햄스트링.mp4');
    expect(fs.existsSync(dest)).toBe(true);
    expect(fs.statSync(dest).size).toBe(data.length);
    // 조각과 메타는 남지 않는다
    expect(fs.readdirSync(path.join(home, 'uploads'))).toEqual([]);
    await waitFor(async () => (await videos()).some((v) => v.fileName === '폰 촬영 햄스트링.mp4' && v.status === 'ready'), 60_000);
  });

  it('같은 이름을 또 올리면 (2) 가 붙는다', async () => {
    const data = fs.readFileSync(SAMPLE_5S);
    const created = await create('폰 촬영 햄스트링.mp4', data.length);
    const url = `${engine.url}${created.headers.get('location')}`;
    const p = await fetch(url, { method: 'PATCH', headers: { ...TUS, 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream' }, body: new Uint8Array(data) });
    expect(p.status).toBe(204);
    expect(decodeURIComponent(p.headers.get('x-madi-file') ?? '')).toBe('폰 촬영 햄스트링 (2).mp4');
    expect(fs.existsSync(path.join(folder, '폰 촬영 햄스트링 (2).mp4'))).toBe(true);
  });
});
