import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, expect, it, vi } from 'vitest';
import { Reference } from '@madi/shared';
import { StyleService, type StyleServiceDeps } from '../src/style/service.js';
import { run } from '../src/workers/spawn.js';
import { makeFrameSheets } from '../src/workers/frames.js';

vi.mock('../src/workers/spawn.js', () => ({ run: vi.fn(), runAnalysis: vi.fn(), SpawnError: class extends Error {} }));
vi.mock('../src/workers/frames.js', () => ({ makeFrameSheets: vi.fn() }));
const homes: string[] = [];
afterEach(() => { for (const h of homes.splice(0)) fs.rmSync(h, { recursive: true, force: true }); vi.clearAllMocks(); });

it('다운로더를 나중에 준비해도 경로를 재탐색하고 링크 등록을 복구한다', async () => {
  let bin = 'missing';
  vi.mocked(run).mockRejectedValueOnce(new Error('ENOENT')).mockResolvedValueOnce({ stdout: '2026.08.19', stderr: '' });
  const enqueue = vi.fn();
  const d = { ytdlpBin: bin, resolveYtdlp: () => bin, cfg: { referencesDir: 'refs' }, log: { debug: vi.fn() }, queue: { enqueue }, refs: { upsertFromLink: () => ({ ref: { id: 'r' }, changed: true }) }, events: { record: vi.fn() } } as unknown as StyleServiceDeps;
  const s = new StyleService(d);
  expect(await s.detectDownloader()).toBe(false);
  expect(() => s.addLink('https://youtu.be/example')).toThrow('no_downloader');
  bin = 'resources/yt-dlp.exe';
  expect(await s.detectDownloader()).toBe(true);
  s.addLink('https://youtu.be/example');
  expect(run).toHaveBeenLastCalledWith(bin, ['--version'], { signal: expect.any(AbortSignal) });
  expect(enqueue).toHaveBeenCalledWith({ type: 'download', referenceId: 'r' });
});

it('무음 완성본도 화면을 AI에 전달하며, 화면을 끄면 호출하지 않는다', async () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'madi-style-visual-')); homes.push(home);
  const file = path.join(home, 'silent.mp4'); fs.writeFileSync(file, 'fixture');
  const ref = Reference.parse({ id: 'r', path: file, fileName: 'silent.mp4', title: '무음 시범', sizeBytes: 7, status: 'done', source: 'folder', url: null, stats: { durationSec: 10, width: 1080, height: 1920, hasAudio: false, aspect: '9:16', silenceCount: 0, maxSilenceSec: 0, sceneCount: 0, cutsPerMin: 0, pair: null }, error: null, createdAt: 1, updatedAt: 1 });
  let frames = true;
  const analyze = vi.fn().mockResolvedValue({ ok: true, text: '{"purpose":"화면에서 본 시범"}' });
  const update = vi.fn();
  let worker: (ctx: unknown) => Promise<void> = async () => {};
  const d = { ytdlpBin: 'missing', cfg: { workDir: home }, settings: { get: () => ({ ai: { provider: 'claude', frames } }) }, refs: { get: () => ref, segmentsOf: () => [], update }, queue: { register: (_: string, fn: typeof worker) => { worker = fn; } }, providers: { claude: { analyze, bin: () => 'claude' } }, log: { warn: vi.fn() }, events: { record: vi.fn() } } as unknown as StyleServiceDeps;
  vi.mocked(makeFrameSheets).mockResolvedValue([{ file: path.join(home, 'frame.jpg'), rel: './sheets/frame.jpg', times: [0.5, 8] }]);
  const s = new StyleService(d); vi.spyOn(s, 'scheduleRememory').mockImplementation(() => {});
  s.registerInsightWorker();
  const ctx = { job: { payload: { referenceId: 'r' } }, signal: new AbortController().signal };
  await worker(ctx);
  expect(analyze).toHaveBeenCalledWith(expect.objectContaining({ images: [path.join(home, 'frame.jpg')], prompt: expect.stringContaining('화면 시트에서 보이는 편집 방식') }));
  expect(update).toHaveBeenCalledWith('r', { insight: expect.objectContaining({ frameTimes: [0.5, 8] }) });
  frames = false; await worker(ctx); expect(analyze).toHaveBeenCalledTimes(1);
  frames = true; vi.mocked(makeFrameSheets).mockResolvedValue([]); await worker(ctx); expect(analyze).toHaveBeenCalledTimes(1);
});
