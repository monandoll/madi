import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { StyleResponse } from '@madi/shared';
import { startEngine, type Engine } from '../src/engine.js';
import { resolveSidecar } from '../src/main/sidecar.js';
import { fakeCli, freePort, REPO_ROOT, SAMPLE_SILENT, tempHome, waitFor } from './helpers.js';

let engine: Engine;
let home: string;
let media: http.Server;
let mediaUrl: string;
const previous = { ytdlp: process.env['MADI_YTDLP'], claude: process.env['MADI_CLAUDE_BIN'] };
const api = async (url: string, data?: unknown) => {
  const res = await fetch(`${engine.url}${url}`, data === undefined ? {} : { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
  expect(res.ok).toBe(true); return res.json();
};

beforeAll(async () => {
  home = tempHome('madi-style-visual-e2e-');
  process.env['MADI_QUIET'] = '1';
  process.env['MADI_YTDLP'] = path.join(home, 'missing-downloader');
  process.env['MADI_CLAUDE_BIN'] = fakeCli('claude');
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'test.db'), port: await freePort() });
  await engine.styleService.detectDownloader();
  media = http.createServer((_req, res) => { res.writeHead(200, { 'content-type': 'video/mp4', 'content-length': fs.statSync(SAMPLE_SILENT).size }); fs.createReadStream(SAMPLE_SILENT).pipe(res); });
  await new Promise<void>((resolve) => media.listen(0, '127.0.0.1', resolve));
  mediaUrl = `http://127.0.0.1:${(media.address() as { port: number }).port}/silent.mp4`;
});
afterAll(async () => {
  await engine?.stop();
  if (media) await new Promise<void>((resolve) => media.close(() => resolve()));
  for (const [name, value] of [['MADI_YTDLP', previous.ytdlp], ['MADI_CLAUDE_BIN', previous.claude]]) {
    if (value === undefined) delete process.env[name!]; else process.env[name!] = value;
  }
  if (home) fs.rmSync(home, { recursive: true, force: true });
});

it('재시작 없이 다시 확인 API로 다운로더 연결을 복구한다', async () => {
  expect(StyleResponse.parse(await api('/api/style')).linkImport).toBe(false);
  // --version 을 지원하는 실제 실행 파일로 재탐색 API를 검증한다.
  process.env['MADI_YTDLP'] = process.execPath;
  expect(StyleResponse.parse(await api('/api/style/relearn', {})).linkImport).toBe(true);
});

it('실제 yt-dlp → 무음 MP4 → 실제 ffmpeg 화면 → AI CLI 분석 → 저장까지 연결한다', async (ctx) => {
  delete process.env['MADI_YTDLP'];
  const downloader = resolveSidecar('ytdlp', path.join(REPO_ROOT, 'resources', 'bin'));
  if (!fs.existsSync(downloader)) { ctx.skip(); return; }
  process.env['MADI_YTDLP'] = downloader;
  await api('/api/style/relearn', {});
  engine.settings.patch({ ai: { ...engine.settings.get().ai, provider: 'claude', frames: true } });
  await api('/api/style/links', { url: mediaUrl });
  await waitFor(() => !!engine.refs.list()[0]?.insight, 90_000);
  const ref = StyleResponse.parse(await api('/api/style')).references[0]!;
  expect(ref).toMatchObject({ source: 'link', status: 'done', error: null, stats: { hasAudio: false } });
  expect(fs.existsSync(ref.path)).toBe(true);
  expect(engine.refs.segmentsOf(ref.id) ?? []).toEqual([]);
  expect(ref.insight!.frameTimes.length).toBeGreaterThan(0);
  expect(ref.insight!.visual).not.toBe('');
  expect(engine.queue.list().some((j) => j.type === 'transcribe')).toBe(false);
  expect(engine.memory.list()).toEqual([]); // 한 편만으로 고정 취향을 제안하지 않는다.
});
