import fs from 'node:fs';
import path from 'node:path';
import { nanoid } from 'nanoid';
import { type AiProvider, type ChatMessage, type ChatParams, type Video } from '@madi/shared';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { SettingsStore } from '../settings.js';
import type { VideoStore } from '../videos.js';
import { TOOL_NAMES } from '../mcp/tools.js';
import { detectCli, resetCliCache } from './detect.js';
import type { AgentProvider, AgentRunOptions } from './provider.js';
import type { StyleProfile } from './style.js';
import { formatLine, formatOf, playbook } from './playbook.js';

export interface RunnerDeps {
  cfg: EngineConfig;
  settings: SettingsStore;
  library: Library;
  videos: VideoStore;
  events: EventLog;
  log: Logger;
  style: StyleProfile;
  providers: Record<Exclude<AiProvider, 'none'>, AgentProvider>;
  /** 우리 MCP 서버를 띄우는 명령. env 는 러너가 채운다. */
  mcpCommand: () => { command: string; args: string[]; env: Record<string, string> };
  /** 엔진 URL (MCP 서버가 도구 호출을 보낼 곳) */
  engineUrl: () => string;
}

export class AgentError extends Error {
  constructor(readonly code: 'ai_off' | 'ai_busy') {
    super(code);
  }
}

interface ActiveRun {
  id: string;
  videoId: string;
  messageId: string;
  controller: AbortController;
}

/**
 * 채팅 한 마디 → 에이전트 실행. 영상당 동시 1.
 * 사용자 말풍선 + (쓰는 중인) 답 말풍선을 먼저 만들고, 답은 message.updated 로 채운다.
 * 도구 호출 내용은 사용자에게 보이지 않는다 — 진행 카드와 결과 카드만 워커가 붙인다.
 */
export class AgentRunner {
  /** MCP 서버 → 엔진 도구 API 인증. 엔진이 뜰 때마다 새로 만든다. */
  readonly token = nanoid(32);
  private runs = new Map<string, ActiveRun>();

  constructor(private readonly d: RunnerDeps) {}

  get style(): StyleProfile {
    return this.d.style;
  }

  isBusy(videoId: string): boolean {
    return this.runs.has(videoId);
  }

  signalFor(runId: string): AbortSignal | undefined {
    for (const r of this.runs.values()) if (r.id === runId) return r.controller.signal;
    return undefined;
  }

  /** 사용자가 이 PC 에서 직접 골라 준 실행 파일 (없으면 null). */
  private customPath(provider: Exclude<AiProvider, 'none'>): string | null {
    return this.d.settings.get().ai.paths?.[provider] ?? null;
  }

  /** 지금 고른 프로바이더가 이 PC 에 있는지. fresh 면 캐시를 버리고 다시 찾는다 (다시 찾기 버튼). */
  async status(opts: { fresh?: boolean } = {}): Promise<{ provider: AiProvider; installed: boolean; connected: boolean }> {
    const provider = this.d.settings.get().ai.provider;
    if (provider === 'none') return { provider, installed: false, connected: false };
    const info = await detectCli(provider, { fresh: opts.fresh ?? false, custom: this.customPath(provider) });
    return { provider, installed: info.installed, connected: info.installed };
  }

  /** 요청을 받아 메시지 두 개를 만들고 실행을 시작한다. 반환은 바로. */
  ask(video: Video, text: string): ChatMessage[] {
    const provider = this.d.settings.get().ai.provider;
    if (provider === 'none') throw new AgentError('ai_off');
    if (this.runs.has(video.id)) throw new AgentError('ai_busy');
    const user = this.d.library.say({ videoId: video.id, role: 'user', kind: 'text', code: 'user.text', params: { text } });
    const reply = this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'text', code: 'ai.text', params: { text: '', streaming: true } });
    const run: ActiveRun = { id: nanoid(), videoId: video.id, messageId: reply.id, controller: new AbortController() };
    this.runs.set(video.id, run);
    void this.execute(run, video, provider, text).finally(() => this.runs.delete(video.id));
    return [user, reply];
  }

  cancel(videoId: string): boolean {
    const run = this.runs.get(videoId);
    if (!run) return false;
    run.controller.abort();
    return true;
  }

  stopAll(): void {
    for (const r of this.runs.values()) r.controller.abort();
  }

  private async execute(run: ActiveRun, video: Video, providerId: Exclude<AiProvider, 'none'>, text: string): Promise<void> {
    const started = Date.now();
    const provider = this.d.providers[providerId];
    const update = (params: ChatParams) => this.d.library.updateMessage(run.messageId, { params });
    const cwd = path.join(this.d.cfg.workDir, 'agent', run.id);
    fs.mkdirSync(cwd, { recursive: true });
    let latest = '';
    let pending: ChatParams | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const flush = () => {
      timer = null;
      if (pending) update(pending);
      pending = null;
    };
    const schedule = (params: ChatParams) => {
      pending = params;
      if (!timer) timer = setTimeout(flush, 150);
    };
    try {
      const base = this.d.mcpCommand();
      const mcp: AgentRunOptions['mcp'] = {
        ...base,
        env: {
          ...base.env,
          MADI_ENGINE_URL: this.d.engineUrl(),
          MADI_AGENT_TOKEN: this.token,
          MADI_VIDEO_ID: video.id,
          MADI_RUN_ID: run.id,
        },
      };
      const result = await provider.run({
        bin: provider.bin(this.customPath(providerId)),
        prompt: this.buildPrompt(video, text, run.messageId),
        system: this.systemPrompt(video),
        mcp,
        toolNames: TOOL_NAMES,
        cwd,
        signal: run.controller.signal,
        onText: (t) => {
          latest = t;
          schedule({ text: t, streaming: true });
        },
        onTool: (name) => {
          this.d.log.debug({ run: run.id, tool: name }, 'agent tool');
          schedule({ text: latest, streaming: true, status: 'working' });
        },
        onLog: (line) => this.d.log.debug({ run: run.id, line: line.slice(0, 300) }, 'agent'),
      });
      if (timer) clearTimeout(timer);
      pending = null;
      const finalText = (result.text || latest).trim();
      if (result.ok) {
        if (finalText) update({ text: finalText, streaming: false });
        else this.d.library.updateMessage(run.messageId, { code: 'ai.done', params: { streaming: false } });
      } else if (result.error === 'aborted') {
        if (finalText) update({ text: finalText, streaming: false });
        else this.d.library.updateMessage(run.messageId, { code: 'ai.stopped', params: { streaming: false } });
      } else if (result.error === 'not_installed') {
        // 찾아 둔 게 사라졌다 — 다음 확인 때 처음부터 다시 찾는다
        resetCliCache();
        this.d.library.updateMessage(run.messageId, { kind: 'error', code: 'ai_missing', params: { streaming: false, provider: providerId } });
      } else {
        this.d.library.updateMessage(run.messageId, { kind: 'error', code: classifyAgentError(result.error ?? ''), params: { streaming: false, detail: (result.error ?? '').slice(0, 300) } });
      }
      this.d.events.record('ai.ask', { provider: providerId, ok: result.ok, toolCalls: result.toolCalls, chars: text.length }, Date.now() - started);
      this.d.log.info({ run: run.id, ok: result.ok, tools: result.toolCalls, ms: Date.now() - started, err: result.error }, 'agent run');
    } catch (err) {
      if (timer) clearTimeout(timer);
      this.d.log.error({ run: run.id, err: String(err) }, 'agent run crashed');
      this.d.library.updateMessage(run.messageId, { kind: 'error', code: 'ai_failed', params: { streaming: false, detail: String(err).slice(0, 300) } });
    } finally {
      fs.rmSync(cwd, { recursive: true, force: true });
    }
  }

  systemPrompt(video?: Video): string {
    const format = formatOf(video ?? {});
    return [
      "너는 '마디'의 편집 도우미다. 운동·재활 영상 크리에이터를 돕는다. 사용자는 편집 지식이 없다.",
      '',
      '규칙:',
      '- 파일이나 셸을 직접 만지지 않는다. 마디 도구(get_transcript, find_silences, find_scenes, propose_cuts, apply_edit, render, extract_shorts, get_chapters, set_subtitle_style, set_subtitle_text, update_style_rule)만 쓴다.',
      '- 어디를 자를지 정하기 전에 get_transcript 로 내용을 본다. 소리가 없는 영상이면 건너뛴다.',
      '- "자막 넣어줘"는 되묻지 않고 바로 한다: get_transcript → apply_edit(subtitles=true) → render. 자막을 넣는 데 필요한 건 그것뿐이다.',
      '- 소리가 없거나 말소리가 없는 영상에도 자막은 넣을 수 있다: 사용자가 준 문장과 시각으로 set_subtitle_text → apply_edit(subtitles=true) → render. 시각을 안 줬으면 영상 전체(0초~끝)에 한 줄로 넣고 그렇게 했다고 말한다.',
      '- 사용자가 문장을 직접 말해 줬으면("안녕하세요 앱 소개합니다 자막을 넣어줘", "이 문장 고쳐줘: …") 그 문장이 영상에서 하는 말이다. 들린 말이 그 문장과 다르거나 뜻이 안 통하면 set_subtitle_text 로 그 구간의 글을 사용자 문장으로 바꾼 뒤 넣는다. "자막에 원하는 문장을 넣는 기능이 없다"고 답하지 않는다.',
      '- 긴 영상(2분 이상)에서 숏폼을 여러 개 뽑거나 목차를 만들 땐 get_chapters 로 챕터와 하이라이트 구간을 먼저 본다.',
      '- 결과 파일은 render 또는 extract_shorts 로만 만든다. 만들어지면 카드가 대화에 자동으로 붙으니 경로·링크·id 를 답에 쓰지 않는다.',
      '- 답은 짧고 쉬운 한국어, 존댓말. 전문 용어(인코딩, 프록시, 트랜스크립트, 렌더, 세그먼트) 금지 → "만드는 중", "자막", "구간".',
      '- 말투: 서술은 "-합니다", 지시는 "-하세요". "-해요" · "-네요" · "-죠?" · 감탄사 · 이모지는 쓰지 않는다. 사과와 추임새 없이 한 일과 다음에 할 일만 적는다.',
      '- 빼도 뜻이 안 변하는 말은 뺀다. 한 일을 한 문장으로 적고, 방금 한 말을 다시 풀어 설명하지 않는다. 물어볼 게 없으면 되묻지 않고 끝낸다.',
      '- 마크다운(#, **, 표, 코드블록) 쓰지 않는다. 짧은 문장 몇 개면 된다.',
      '- 해달라는 게 분명하면 되묻지 말고 바로 한다. 정말 모호할 때만 짧게 하나 되묻는다.',
      '- 사용자가 결과를 고쳐 달라고 하면 고친 뒤, 그 방식이 앞으로도 적용될 만하면 "앞으로도 이렇게 할까요?" 라고 한 번만 묻는다. 사용자가 예라고 하면 그때 update_style_rule 로 한 줄 저장한다. 묻지 않고 저장하지 않는다.',
      '- 도구가 실패하면 그 이유를 쉬운 말로 알린다. 같은 도구를 무의미하게 반복하지 않는다.',
      '',
      // 도메인 기본값. 아래 style.md 가 이것을 덮는다.
      playbook({ format, hasAudio: video?.hasAudio !== false }),
      '',
      '사용자의 편집 규칙(style.md) — 위 지침과 어긋나면 이쪽을 따른다:',
      this.d.style.rules().trim(),
    ].join('\n');
  }

  buildPrompt(video: Video, text: string, replyMessageId: string): string {
    const lib = this.d.library;
    const transcript = lib.transcriptOf(video.id);
    const outputs = lib.outputsOf(video.id);
    const history = lib
      .messagesOf(video.id)
      .filter((m) => m.id !== replyMessageId)
      .slice(-24)
      .map(describeMessage)
      .filter((s): s is string => !!s);
    const lines = [
      `영상: ${video.title}`,
      `길이: ${fmtDuration(video.durationSec ?? 0)} (${Math.round(video.durationSec ?? 0)}초) · ${video.width ?? '?'}x${video.height ?? '?'} · 소리 ${video.hasAudio === false ? '없음' : '있음'}`,
      `자막: ${transcript ? `있음 (${transcript.segments.length}줄)` : '아직 없음 (get_transcript 로 만들 수 있음)'}`,
      `기본 포맷: ${formatLine(formatOf(video))}`,
      outputs.length
        ? `지금까지 만든 결과물:\n${outputs
            .slice(0, 10)
            .map((o) => `- ${o.title} (${fmtDuration(o.durationSec)}, ${o.width < o.height ? '9:16' : '16:9'}, editId=${o.editId})`)
            .join('\n')}`
        : '지금까지 만든 결과물: 없음',
    ];
    if (history.length) lines.push('', '최근 대화:', ...history);
    lines.push('', `사용자 요청: ${text}`);
    return lines.join('\n');
  }
}

/** 대화 기록을 에이전트가 읽을 한 줄로. UI 문구(copy.ts)와는 별개의 최소 요약. */
export function describeMessage(m: ChatMessage): string | null {
  const p = m.params;
  const who = m.role === 'user' ? '사용자' : '마디';
  switch (m.code) {
    case 'user.text':
    case 'ai.text':
      return p['text'] ? `${who}: ${String(p['text']).slice(0, 600)}` : null;
    case 'greeting':
      return null;
    case 'action.subtitle':
      return '사용자: 자막 넣어줘';
    case 'action.silence':
      return '사용자: 쉬는 구간 잘라줘';
    case 'action.vertical':
      return '사용자: 세로로 바꿔줘';
    case 'action.short':
      return `사용자: ${p['start']}초부터 ${p['end']}초까지 숏폼으로 잘라줘`;
    case 'output.ready':
      return `마디: (결과물 "${p['title'] ?? ''}" 만들어짐)`;
    case 'transcript.ready':
      return '마디: (자막 만들어짐)';
    case 'silence.none':
      return '마디: 쉬는 구간이 없어 그대로 두었습니다.';
    case 'ai.done':
      return '마디: 끝났습니다.';
    case 'ai.stopped':
      return '마디: (멈춤)';
    default:
      if (m.kind === 'error') return `마디: (문제: ${m.code})`;
      if (m.kind === 'progress') return null;
      return null;
  }
}

function fmtDuration(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return m ? `${m}분 ${s}초` : `${s}초`;
}

/** CLI 가 죽은 이유를 사용자 말로 고를 수 있게 분류한다. ai_login = 로그인 안 됨, ai_node_missing = node 를 못 찾음(npm 설치본), 나머지 ai_failed. */
export function classifyAgentError(err: string): 'ai_login' | 'ai_node_missing' | 'ai_failed' {
  if (/not logged in|log ?in|unauthori[sz]ed|authenticat|invalid api key|api key/i.test(err)) return 'ai_login';
  if (/env: node|node: (command )?not found|node.*No such file|exit 127/i.test(err)) return 'ai_node_missing';
  return 'ai_failed';
}
