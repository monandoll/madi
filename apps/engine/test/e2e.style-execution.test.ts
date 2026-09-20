import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { type Engine, startEngine } from '../src/engine.js';
import { parsePlan } from '../src/plan/prompt.js';
import { SAMPLE_SILENT, freePort, tempHome, waitFor } from './helpers.js';

let engine: Engine, home: string, id: string;
const api = async (url: string, body?: unknown, method = 'POST') => {
  const r = await fetch(`${engine.url}${url}`, { method, headers: { 'content-type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  return { status: r.status, body: await r.json() };
};
const act = async (data: unknown) => {
  const result = await api(`/api/videos/${id}/actions`, data); expect(result.status).toBe(200);
  const jobId = result.body.job.id;
  await waitFor(() => ['done', 'failed'].includes(engine.queue.get(jobId)!.status), 60000);
  expect(engine.queue.get(jobId)!.status).toBe('done');
  return (await api(`/api/outputs/${engine.library.messageForJob(jobId)!.outputId}`, undefined, 'GET')).body;
};
beforeAll(async () => {
  home = tempHome('madi-style-execution-'); process.env['MADI_QUIET'] = '1';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'test.db'), port: await freePort() });
  const v = engine.videos.register({ path: SAMPLE_SILENT, fileName: 'style.mp4', sizeBytes: fs.statSync(SAMPLE_SILENT).size, recordedAt: 1 }).video;
  id = v.id; engine.videos.update(id, { status: 'ready', durationSec: 3, width: 320, height: 180, hasAudio: false });
});
afterAll(async () => { await engine?.stop(); if (home) fs.rmSync(home, { recursive: true, force: true }); });

it('승인한 지침만 컨텍스트에 들어가고 삭제·승인 변경은 과거 실행안 적용을 막는다', async () => {
  const video = engine.videos.mustGet(id);
  const before = engine.styleService.contextKey(video);
  // 자막이 생기는 것만으로는 지문이 안 바뀐다 — 사용자가 규칙 · 자막 설정 · 승인 기억을 바꿨을 때만
  engine.library.setTranscript(id, { language: 'ko', model: 'manual', segments: [{ id: 'k', start: 0, end: 1, text: '어깨 견갑골 QA', words: [] }] });
  expect(engine.styleService.contextKey(video)).toBe(before);
  const memory = engine.memory.add({ text: 'QA 두 언어 자막', kind: 'style', scope: 'all', source: 'reference', status: 'proposed', evidence: ['a', 'b'] });
  expect(engine.styleService.recall(video)).not.toContain('QA 두 언어');
  expect(engine.styleService.contextKey(video)).toBe(before);
  await api(`/api/style/memory/${memory.id}`, { status: 'approved' }, 'PATCH');
  expect(engine.styleService.recall(video)).toContain('QA 두 언어');
  expect(engine.styleService.contextKey(video)).not.toBe(before);
  const plan = parsePlan('{"purpose":"x","recipe":{}}', { videoId: id, provider: 'claude', durationSec: 3, fromTranscript: false, styleContextKey: before })!;
  engine.plans.set(plan);
  const stale = await api(`/api/videos/${id}/actions`, { type: 'apply_plan' });
  expect(stale.body.error.code).toBe('plan_outdated');
  expect(engine.queue.list().filter((j) => j.type === 'render')).toEqual([]);
});

it('편집안의 순서·스타일·2단 문구를 실제 MP4에 적용하고 숏폼·후속 수정에도 보존한다', async () => {
  const video = engine.videos.mustGet(id);
  const source = engine.library.setTranscript(id, { language: 'ko', model: 'manual', segments: [{ id: 's', start: 0, end: 3, text: '원본 문구', words: [] }] });
  const recipe = { summary: '시범을 먼저, 2단 자막', parts: [{ start: 1.5, end: 3 }, { start: 0, end: 1.5 }], subtitleStyle: { background: 'outline', fontSize: 16, color: '#FFFFFF', outlineColor: '#000000', outlineWidth: 1, bottom: 0.4, secondaryColor: '#FFFF88', secondaryScale: 0.5, secondaryItalic: true }, captions: [{ start: 0, end: 1.5, text: '팔을 당깁니다', secondaryText: 'Pull your arms.' }, { start: 1.5, end: 3, text: '천천히 돌아옵니다', secondaryText: 'Return slowly.' }] };
  engine.plans.set(parsePlan(JSON.stringify({ purpose: '시범 안내', recipe, shortCandidates: [{ start: 0, end: 1.5, title: '한 동작', why: '완결' }] }), { videoId: id, provider: 'claude', durationSec: 3, fromTranscript: false, styleContextKey: engine.styleService.contextKey(video) })!);
  const full = await act({ type: 'apply_plan' });
  expect(full.edit).toMatchObject({ parts: recipe.parts, subtitleAuto: false, subtitleStyle: recipe.subtitleStyle });
  expect(full.transcript.segments[0].secondaryText).toBe('Pull your arms.');
  expect(engine.library.transcriptOf(id)!.id).toBe(source.id);
  expect(fs.statSync(engine.library.output(full.output.id)!.path).size).toBeGreaterThan(1000);
  expect(Math.abs(full.output.durationSec - 3)).toBeLessThan(0.2);
  const short = await act({ type: 'short', range: { start: 0, end: 1.5 }, subtitles: true, from: 'plan' });
  expect(short.edit.parts).toEqual([]);
  expect(short.edit.subtitleStyle).toMatchObject(recipe.subtitleStyle);
  expect(short.transcript.segments).toHaveLength(1);
  const tool = await (await fetch(`${engine.url}/api/agent/tools/set_subtitle_style`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-madi-agent': engine.agent.token }, body: JSON.stringify({ videoId: id, input: { editId: full.edit.id, secondaryColor: '#00FF00', italic: true } }) })).json();
  expect(tool.ok).toBe(true);
  const revisedId = (tool.result as { editId: string }).editId;
  expect(revisedId).not.toBe(full.edit.id);
  expect(engine.library.edit(full.edit.id)!.subtitleStyle.secondaryColor).toBe('#FFFF88');
  expect(engine.library.edit(revisedId)!.subtitleStyle).toMatchObject({ secondaryColor: '#00FF00', background: 'outline', bottom: 0.4 });
  expect(engine.queue.list().some((j) => j.type === 'transcribe')).toBe(false);
});
