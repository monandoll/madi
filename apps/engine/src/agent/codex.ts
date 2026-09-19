import { findCli } from './detect.js';
import { MCP_SERVER_NAME } from './claude.js';
import { type AgentProvider, type AgentResult, type AgentRunOptions, type AnalyzeOptions, runCli, type StreamEvent, type StreamParser } from './provider.js';

/**
 * `codex exec --json` 출력 파서 (JSONL).
 * - item.completed / item.type=agent_message: 답 한 턴
 * - item.started|completed / item.type=mcp_tool_call: 도구 호출
 * - turn.completed: 끝. turn.failed / error: 실패
 */
export class CodexStream implements StreamParser {
  private turns: string[] = [];
  private seenTools = new Set<string>();
  toolCalls = 0;
  done = false;
  error: string | null = null;

  get text(): string {
    return this.turns.filter((t) => t.trim()).join('\n\n');
  }

  feed(line: string): StreamEvent[] {
    if (!line.startsWith('{')) return [];
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(line) as Record<string, unknown>;
    } catch {
      return [];
    }
    const out: StreamEvent[] = [];
    const type = msg['type'];
    const item = msg['item'] as { id?: string; type?: string; text?: string; tool?: string; server?: string; name?: string } | undefined;
    if ((type === 'item.completed' || type === 'item.updated') && item?.type === 'agent_message' && item.text?.trim()) {
      if (type === 'item.completed') this.turns.push(item.text);
      out.push({ type: 'text', text: type === 'item.completed' ? this.text : [...this.turns, item.text].join('\n\n') });
    } else if ((type === 'item.started' || type === 'item.completed') && item?.type === 'mcp_tool_call') {
      const key = item.id ?? `${this.toolCalls}`;
      if (!this.seenTools.has(key)) {
        this.seenTools.add(key);
        this.toolCalls++;
        out.push({ type: 'tool', name: (item.tool ?? item.name ?? '').replace(new RegExp(`^${MCP_SERVER_NAME}__`), '') });
      }
    } else if (type === 'turn.completed') {
      this.done = true;
      out.push({ type: 'done', ok: true });
    } else if (type === 'turn.failed' || type === 'error') {
      this.done = true;
      const err = (msg['error'] as { message?: string } | undefined)?.message ?? (msg['message'] as string | undefined) ?? 'error';
      this.error = String(err).slice(0, 400);
      out.push({ type: 'done', ok: false, error: this.error });
    }
    return out;
  }
}

/** TOML 인라인 값. `-c key=value` 로 넘긴다. */
export function toml(v: string | string[] | Record<string, string>): string {
  const str = (s: string) => `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  if (typeof v === 'string') return str(v);
  if (Array.isArray(v)) return `[${v.map(str).join(', ')}]`;
  return `{${Object.entries(v)
    .map(([k, val]) => `${k} = ${str(val)}`)
    .join(', ')}}`;
}

export function codexArgs(opts: { mcp: AgentRunOptions['mcp']; cwd: string; prompt: string }): string[] {
  return [
    'exec',
    '--json',
    '--skip-git-repo-check',
    '-C',
    opts.cwd,
    '-s',
    'read-only',
    '-c',
    `mcp_servers.${MCP_SERVER_NAME}.command=${toml(opts.mcp.command)}`,
    '-c',
    `mcp_servers.${MCP_SERVER_NAME}.args=${toml(opts.mcp.args)}`,
    '-c',
    `mcp_servers.${MCP_SERVER_NAME}.env=${toml(opts.mcp.env)}`,
    opts.prompt,
  ];
}

/** 사용자 본인의 OpenAI 구독(Codex CLI)으로 돈다. 시스템 프롬프트 옵션이 없어 앞에 붙인다. */
export class CodexProvider implements AgentProvider {
  readonly id = 'codex' as const;
  readonly label = 'Codex';

  bin(custom?: string | null): string | null {
    return findCli('codex', custom);
  }

  async run(opts: AgentRunOptions): Promise<AgentResult> {
    const bin = opts.bin ?? this.bin();
    if (!bin) return { text: '', toolCalls: 0, ok: false, error: 'not_installed' };
    const prompt = `${opts.system}\n\n---\n\n${opts.prompt}`;
    return runCli(bin, codexArgs({ mcp: opts.mcp, cwd: opts.cwd, prompt }), null, new CodexStream(), opts);
  }

  /** 도구 없이 한 턴 (MCP 설정을 안 준다). */
  async analyze(opts: AnalyzeOptions): Promise<AgentResult> {
    const bin = opts.bin ?? this.bin();
    if (!bin) return { text: '', toolCalls: 0, ok: false, error: 'not_installed' };
    const prompt = `${opts.system}\n\n---\n\n${opts.prompt}`;
    return runCli(bin, codexAnalyzeArgs({ cwd: opts.cwd, prompt, images: opts.images ?? [] }), null, new CodexStream(), { cwd: opts.cwd, onText: () => undefined, onTool: () => undefined, ...(opts.signal ? { signal: opts.signal } : {}), ...(opts.onLog ? { onLog: opts.onLog } : {}) });
  }
}

/** 분석 모드: 도구 없이 한 턴. 그림은 `-i 파일` 로 붙인다 (codex exec 의 이미지 첨부). */
export function codexAnalyzeArgs(opts: { cwd: string; prompt: string; images?: string[] }): string[] {
  return ['exec', '--json', '--skip-git-repo-check', '-C', opts.cwd, '-s', 'read-only', ...(opts.images ?? []).flatMap((f) => ['-i', f]), opts.prompt];
}
