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
  /** 이 영상에 붙일 "# 기억" 블록 (완성본 · 지난 편집에서 배운 것). 없으면 빈 문자열. */
  recall?: (video: Video) => string;
  /** 이 영상의 편집안 요약 (읽어 둔 게 있으면). 구간을 고를 때 여기서 시작한다. */
  plan?: (video: Video) => string;
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
  completion?: Promise<void>;
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
  ask(video: Video, text: string, editId?: string): ChatMessage[] {
    const provider = this.d.settings.get().ai.provider;
    if (provider === 'none') throw new AgentError('ai_off');
    if (this.runs.has(video.id)) throw new AgentError('ai_busy');
    const user = this.d.library.say({ videoId: video.id, role: 'user', kind: 'text', code: 'user.text', params: { text, ...(editId ? { editId } : {}) } });
    const reply = this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'text', code: 'ai.text', params: { text: '', streaming: true } });
    const run: ActiveRun = { id: nanoid(), videoId: video.id, messageId: reply.id, controller: new AbortController() };
    this.runs.set(video.id, run);
    run.completion = this.execute(run, video, provider, text, editId).finally(() => this.runs.delete(video.id));
    return [user, reply];
  }

  cancel(videoId: string): boolean {
    const run = this.runs.get(videoId);
    if (!run) return false;
    run.controller.abort();
    return true;
  }

  async stopAll(): Promise<void> {
    const runs = [...this.runs.values()];
    for (const r of runs) r.controller.abort();
    await Promise.all(runs.map(r => r.completion));
  }

  private async execute(run: ActiveRun, video: Video, providerId: Exclude<AiProvider, 'none'>, text: string, editId?: string): Promise<void> {
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
        prompt: this.buildPrompt(video, text, run.messageId, editId),
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
      try {
        await fs.promises.rm(cwd, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
      } catch (err) {
        this.d.log.warn({ run: run.id, err: String(err) }, 'agent work directory cleanup failed');
      }
    }
  }

  systemPrompt(video?: Video): string {
    const format = formatOf(video ?? {});
    return [
      "너는 '마디'의 편집 도우미다. 운동·재활 영상 크리에이터를 돕는다. 사용자는 편집 지식이 없다.",
      '',
      '규칙:',
      `- 파일이나 셸을 직접 만지지 않는다. 마디 도구(${TOOL_NAMES.join(', ')})만 쓴다.`,
      '- 영상의 동작을 보거나 동작에 맞는 자막을 요청받으면 inspect_video_frames(editId가 선택되었으면 포함)를 먼저 호출해 실제 이미지들을 본다. get_transcript의 음성이나 find_scenes의 전환 시각만으로 동작을 판단하지 않는다. 한 장면도 여러 동작을 포함할 수 있다.',
      '- 화면의 각 칸과 sourceTime을 연결해 관찰한 동작 구간에만 안내 문구를 넣는다. 전환이 불명확하면 range를 좁혀 추가로 본다. 단편 표본으로 모든 프레임을 봤다고 말하지 않는다. 운동 이름·목적·효과·횟수·진단은 추측하지 않고, 이름이 불확실해도 보이는 동작을 쉬운 말로 설명할 수 있다.',
      '- 기존 AI 생성 자막은 동작의 증거가 아니다. 화면과 맞지 않는 생성 문구를 고치는 요청이면 실제 화면을 확인해 선택한 결과물의 자막을 교체하고 render까지 한다. 사용자 문구는 요청 없이 바꾸지 않는다. 화면 확인 도구가 실패하면 무엇을 확인하지 못했는지 알리고 지어내지 않는다.',
      '- 어디를 자를지 정하기 전에 get_transcript 로 내용을 본다. 소리가 없는 영상이면 건너뛴다.',
      '- "자막 넣어줘"는 되묻지 않고 바로 한다: get_transcript → apply_edit(subtitles=true) → render. 자막을 넣는 데 필요한 건 그것뿐이다.',
      '- 소리가 없거나 말소리가 없는 영상에도 자막은 넣을 수 있다: 사용자가 준 문장과 시각으로 set_subtitle_text → apply_edit(subtitles=true) → render. 시각을 안 줬으면 영상 전체(0초~끝)에 한 줄로 넣고 그렇게 했다고 말한다.',
      '- 사용자가 문구를 직접 주면 실제로 발화한 내용이라고 가정하지 않는다. 받아쓰기가 없어도 set_subtitle_text 로 요청한 문구를 넣을 수 있다. "자막에 원하는 문장을 넣는 기능이 없다"고 답하지 않는다.',
      '- 내 스타일·배운 스타일로 편집하라는 요청은 현재 승인한 기억과 직접 쓴 규칙을 실행에 연결한다. 설명만 하지 말고 자막 설정은 apply_edit.subtitleStyle 또는 set_subtitle_style로 저장하고 render한다. 미승인 제안을 자동 적용하거나 이번 요청을 영구 취향으로 저장하지 않는다.',
      '- 자막은 background=outline이면 박스 없이 테두리 글자로, bold/italic/outlineWidth/outlineColor/bottom으로 모양을 지정한다. 2단 자막은 set_subtitle_text.lines의 text에 본문, secondaryText에 의미를 보존한 번역·보조 문구를 넣고 secondaryScale/secondaryColor/secondaryItalic으로 구분한다. 재생 가능한 결과가 나온 뒤 실제 적용한 것만 알린다.',
      '- 원·화살표·비교 화면·애니메이션은 현재 도구로 지원하지 않는다. 이런 기억이 있어도 적용했다고 주장하지 말고 가능한 자막·구간 순서·크롭을 적용한 결과와 남은 제한을 구분한다. 사용자 문구 수정 시 요청하지 않은 secondaryText는 유지하고 본문을 번역 수정하라는 요청일 때만 함께 고친다.',
      '- 긴 영상(2분 이상)에서 숏폼을 여러 개 뽑거나 목차를 만들 땐 get_chapters 로 챕터와 하이라이트 구간을 먼저 본다.',
      '- 결과 파일은 render 또는 extract_shorts 로만 만든다. 만들어지면 카드가 대화에 자동으로 붙으니 경로·링크·id 를 답에 쓰지 않는다.',
      '- 답은 짧고 쉬운 한국어, 존댓말. 전문 용어(인코딩, 프록시, 트랜스크립트, 렌더, 세그먼트) 금지 → "만드는 중", "자막", "구간".',
      '- 말투: 서술은 "-합니다", 지시는 "-하세요". "-해요" · "-네요" · "-죠?" · 감탄사 · 이모지는 쓰지 않는다. 사과와 추임새 없이 한 일과 다음에 할 일만 적는다.',
      '- 빼도 뜻이 안 변하는 말은 뺀다. 한 일을 한 문장으로 적고, 방금 한 말을 다시 풀어 설명하지 않는다. 물어볼 게 없으면 되묻지 않고 끝낸다.',
      '- 마크다운(#, **, 표, 코드블록) 쓰지 않는다. 짧은 문장 몇 개면 된다.',
      '- 해달라는 게 분명하면 되묻지 말고 바로 한다. 정말 모호할 때만 짧게 하나 되묻는다.',
      '- 사용자가 결과를 고쳐 달라고 하면 고친 뒤, 그 방식이 앞으로도 적용될 만하면 "앞으로도 이렇게 할까요?" 라고 한 번만 묻는다. 사용자가 예라고 하면 그때 update_style_rule 로 한 줄 저장한다. 묻지 않고 저장하지 않는다.',
      '- 기존 결과물의 자막을 수정할 때는 get_transcript(editId)로 그 결과의 문구를 읽고 set_subtitle_text(editId, lines)로 수정한다. 돌아온 새 editId로 render한다. 기존 결과물의 구간·순서·비율은 유지한다.',
      '- 사용자가 원하는 문구는 음성과 달라도 넣을 수 있다. 직접 준 문구를 요청 없이 바꾸지 않는다. 음성 없는 영상의 문구 삽입에는 음성 인식을 실행하지 않는다. 자막을 전부 빼려면 set_subtitle_text(editId, lines=[], replaceAll=true)를 쓴다.',
      '- 저장할 때 범위를 고른다: 사용자가 "이 영상만"이라 하면 scope=video, "어깨 영상은"처럼 주제를 말하면 scope=topic + topics, 아니면 scope=all. 부위 · 동작 · 표기 같은 용어면 kind=term.',
      '- 도구가 실패하면 그 이유를 쉬운 말로 알린다. 같은 도구를 무의미하게 반복하지 않는다.',
      '',
      // 도메인 기본값. 아래 기억과 style.md 가 이것을 덮는다.
      playbook({ format, hasAudio: video?.hasAudio !== false }),
      '',
      // 이 제작자의 완성본 · 지난 편집에서 배운 것 (관련 있는 것만)
      ...(video && this.d.recall ? [this.d.recall(video), ''] : []),
      '사용자의 편집 규칙(style.md) — 위 지침 · 기억과 어긋나면 이쪽을 따른다:',
      this.d.style.rules().trim(),
    ].join('\n');
  }

  buildPrompt(video: Video, text: string, replyMessageId: string, editId?: string): string {
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
    const plan = this.d.plan?.(video) ?? '';
    if (plan) lines.push('', plan);
    if (history.length) lines.push('', '최근 대화:', ...history);
    if (editId) lines.push('', `이번 요청에서 사용자가 선택한 결과물: editId=${editId}. 이 버전을 기준으로 수정하고 요청하지 않은 편집 조건은 유지한다. 제목이 같아도 다른 결과물을 고르지 않는다.`);
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
    case 'action.plan':
      return '사용자: 편집안 만들어줘';
    case 'plan.ready':
      return '마디: 편집안을 만들었다 (아래 "이 영상의 편집안")';
    case 'action.apply_plan':
      return '사용자: 편집안대로 롱폼 만들어줘';
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
