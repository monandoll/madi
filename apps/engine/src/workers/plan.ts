import fs from 'node:fs';
import path from 'node:path';
import type { AiProvider, Video } from '@madi/shared';
import { parseScenes, parseSilences, sceneDetectArgs, silenceDetectArgs } from '@madi/ffmpeg-presets';
import type { AgentProvider } from '../agent/provider.js';
import { formatOf } from '../agent/playbook.js';
import type { StyleProfile } from '../agent/style.js';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { PlanStore } from '../plan/store.js';
import { parsePlan, planPrompt } from '../plan/prompt.js';
import type { JobQueue } from '../queue/index.js';
import type { SettingsStore } from '../settings.js';
import type { VideoStore } from '../videos.js';
import { splitByMotion } from './edit.js';
import { run } from './spawn.js';

export interface PlanWorkerDeps {
  cfg: EngineConfig;
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  plans: PlanStore;
  style: StyleProfile;
  settings: SettingsStore;
  providers: Record<Exclude<AiProvider, 'none'>, AgentProvider>;
  /** 이 영상에 붙일 "# 기억" 블록 */
  recall: (video: Video) => string;
  ffmpegBin: string;
  events: EventLog;
  log: Logger;
}

/**
 * plan 잡: 촬영본 하나를 AI 가 읽고 편집안(EditPlan)을 남긴다 (기획안 §4 · §13).
 * 자막이 없고 소리가 있으면 먼저 만들고(기다림), 무음을 가만히/동작 중으로 나누고, 장면 전환을 재서 한 턴에 넘긴다.
 * 파일은 만들지 않는다. 카드가 붙고 사용자가 고른다.
 */
export function registerPlanWorker(d: PlanWorkerDeps): void {
  d.queue.register('plan', async ({ job, signal, setProgress }) => {
    const video = d.videos.mustGet(job.videoId!);
    const started = Date.now();
    const m = d.library.messageForJob(job.id);
    const providerId = d.settings.get().ai.provider;
    try {
      if (providerId === 'none') throw new Error('ai_off');
      const provider = d.providers[providerId];
      const duration = video.durationSec ?? 0;
      let transcript = d.library.transcriptOf(video.id);
      if (!transcript && video.hasAudio !== false) {
        const t = d.queue.enqueue({ type: 'transcribe', videoId: video.id });
        await waitJob(d.queue, t.id, signal);
        transcript = d.library.transcriptOf(video.id);
      }
      setProgress(0.3);
      let silences: { start: number; end: number }[] = [];
      let moving: { start: number; end: number }[] = [];
      if (video.hasAudio !== false) {
        const { stderr } = await run(d.ffmpegBin, silenceDetectArgs(video.path, { minSec: Math.max(0.7, d.style.params().silenceMinSec) }), { signal });
        const all = parseSilences(stderr, duration);
        const split = await splitByMotion(d, video.path, all, duration, signal);
        silences = split.cut;
        moving = split.kept;
      }
      setProgress(0.5);
      const scenes = parseScenes((await run(d.ffmpegBin, sceneDetectArgs(video.path, 0.4), { signal })).stderr);
      setProgress(0.6);
      const segments = transcript?.segments ?? null;
      const { system, prompt } = planPrompt({ video, segments, silences, movingSilences: moving, scenes, format: formatOf(video), memory: d.recall(video) });
      const cwd = path.join(d.cfg.workDir, 'plan', video.id);
      fs.mkdirSync(cwd, { recursive: true });
      try {
        const res = await provider.analyze({ system, prompt, cwd, bin: provider.bin(d.settings.get().ai.paths?.[providerId] ?? null), signal });
        if (!res.ok) throw new Error(res.error === 'not_installed' ? 'ai_missing' : (res.error ?? 'analyze failed'));
        const plan = parsePlan(res.text, { videoId: video.id, provider: providerId, durationSec: duration, fromTranscript: !!segments?.length });
        if (!plan) throw new Error('no plan in answer');
        d.plans.set(plan);
        if (m) {
          d.library.updateMessage(m.id, {
            kind: 'plan',
            code: 'plan.ready',
            params: { ...m.params, sections: plan.sections.length, shorts: plan.shortCandidates.length, cuts: plan.cutCandidates.length, keeps: plan.keepRanges.length },
          });
        }
        d.events.record('plan.made', { provider: providerId, sections: plan.sections.length, shorts: plan.shortCandidates.length, cuts: plan.cutCandidates.length, fromTranscript: plan.fromTranscript, durationSec: duration }, Date.now() - started);
      } finally {
        fs.rmSync(cwd, { recursive: true, force: true });
      }
    } catch (err) {
      if (signal.aborted) return;
      const msg = err instanceof Error ? err.message : String(err);
      d.log.warn({ video: video.id, err: msg }, 'plan failed');
      d.events.record('plan.failed', { provider: providerId }, Date.now() - started);
      if (m) d.library.updateMessage(m.id, { kind: 'error', code: msg === 'ai_missing' ? 'ai_missing' : msg === 'ai_off' ? 'ai_off' : 'plan_failed', params: { ...m.params, detail: msg.slice(0, 200) } });
      // 잡은 성공으로 끝낸다 — 다시 누르면 다시 읽는다 (큐 재시도로 토큰을 더 쓰지 않는다)
    }
  });
}

async function waitJob(queue: JobQueue, jobId: string, signal: AbortSignal): Promise<void> {
  const until = Date.now() + 30 * 60_000;
  while (Date.now() < until) {
    if (signal.aborted) throw new Error('aborted');
    const j = queue.get(jobId);
    if (!j) throw new Error('job vanished');
    if (j.status === 'done') return;
    // 자막을 못 만들어도(whisper 없음) 장면 · 침묵으로 편집안을 쓴다
    if (j.status === 'failed' || j.status === 'canceled') return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('timeout');
}
