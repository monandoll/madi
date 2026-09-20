import fs from 'node:fs';
import path from 'node:path';
import { findCli } from './detect.js';
import { type AgentProvider, type AgentResult, type AgentRunOptions, type AnalyzeOptions, runCli, type StreamEvent, type StreamParser } from './provider.js';

export const MCP_SERVER_NAME = 'madi';

/**
 * `claude -p --output-format stream-json --include-partial-messages` 출력 파서.
 * - stream_event/content_block_delta(text_delta): 지금 턴의 글자를 이어 붙인다
 * - assistant: 턴 확정 (같은 글이 다시 오므로 partial 을 이걸로 바꾼다), tool_use 는 도구 호출
 * - result: 끝. is_error 또는 subtype!=='success' 면 실패
 */
export class ClaudeStream implements StreamParser {
  private turns: string[] = [];
  private partial = '';
  toolCalls = 0;
  done = false;
  error: string | null = null;

  get text(): string {
    return [...this.turns, this.partial].filter((t) => t.trim()).join('\n\n');
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
    switch (msg['type']) {
      case 'stream_event': {
        const ev = msg['event'] as { type?: string; delta?: { type?: string; text?: string } } | undefined;
        if (ev?.type === 'content_block_delta' && ev.delta?.type === 'text_delta' && ev.delta.text) {
          this.partial += ev.delta.text;
          out.push({ type: 'text', text: this.text });
        }
        break;
      }
      case 'assistant': {
        const content = ((msg['message'] as { content?: unknown[] } | undefined)?.content ?? []) as {
          type: string;
          text?: string;
          name?: string;
        }[];
        const text = content
          .filter((b) => b.type === 'text' && b.text)
          .map((b) => b.text!)
          .join('');
        for (const b of content) {
          if (b.type === 'tool_use') {
            this.toolCalls++;
            out.push({ type: 'tool', name: (b.name ?? '').replace(new RegExp(`^mcp__${MCP_SERVER_NAME}__`), '') });
          }
        }
        // 확정 턴: partial(스트리밍으로 모은 것)을 버리고 전체 글로 바꾼다
        if (text.trim()) this.turns.push(text);
        this.partial = '';
        if (text.trim()) out.push({ type: 'text', text: this.text });
        break;
      }
      case 'result': {
        this.done = true;
        const isError = msg['is_error'] === true || (typeof msg['subtype'] === 'string' && msg['subtype'] !== 'success');
        if (isError) {
          const r = msg['result'];
          this.error = typeof r === 'string' && r.trim() ? r.trim().slice(0, 400) : String(msg['subtype'] ?? 'error');
        } else if (this.turns.length === 0 && typeof msg['result'] === 'string' && (msg['result'] as string).trim()) {
          // 텍스트 턴을 못 받았으면 result 의 최종 답이라도 쓴다
          this.turns.push(msg['result'] as string);
          out.push({ type: 'text', text: this.text });
        }
        out.push({ type: 'done', ok: !isError, ...(isError ? { error: this.error! } : {}) });
        break;
      }
      default:
        break;
    }
    return out;
  }
}

/** 마디 MCP 도구 이름 → claude 의 도구 이름. */
export function claudeToolName(tool: string): string {
  return `mcp__${MCP_SERVER_NAME}__${tool}`;
}

/** 에이전트가 파일·셸을 못 만지게 막는 내장 도구들. */
export const CLAUDE_DISALLOWED = ['Bash', 'Edit', 'Write', 'Read', 'Glob', 'Grep', 'WebFetch', 'WebSearch', 'Task', 'NotebookEdit', 'MultiEdit', 'TodoWrite', 'KillShell', 'BashOutput'];

export function claudeArgs(opts: { mcpConfigPath: string; toolNames: string[]; systemPath: string; maxTurns?: number }): string[] {
  return [
    '-p',
    '--output-format',
    'stream-json',
    '--verbose',
    '--include-partial-messages',
    '--mcp-config',
    opts.mcpConfigPath,
    '--strict-mcp-config',
    '--allowedTools',
    ...opts.toolNames.map(claudeToolName),
    '--disallowedTools',
    ...CLAUDE_DISALLOWED,
    '--append-system-prompt-file',
    opts.systemPath,
    '--max-turns',
    String(opts.maxTurns ?? 40),
  ];
}

/** 사용자 본인의 Claude Code 구독으로 돈다. */
export class ClaudeProvider implements AgentProvider {
  readonly id = 'claude' as const;
  readonly label = 'Claude Code';

  constructor(private readonly writeMcpConfig: (mcp: AgentRunOptions['mcp'], cwd: string) => string) {}

  bin(custom?: string | null): string | null {
    return findCli('claude', custom);
  }

  async run(opts: AgentRunOptions): Promise<AgentResult> {
    const bin = opts.bin ?? this.bin();
    if (!bin) return { text: '', toolCalls: 0, ok: false, error: 'not_installed' };
    const mcpConfigPath = this.writeMcpConfig(opts.mcp, opts.cwd);
    const args = claudeArgs({ mcpConfigPath, toolNames: opts.toolNames, systemPath: writeSystemPrompt(opts) });
    return runCli(bin, args, opts.prompt, new ClaudeStream(), opts);
  }

  /** 도구 없이 한 턴. --strict-mcp-config 에 빈 설정을 줘서 사용자 PC 의 MCP 서버가 끼어들지 않게 한다. */
  async analyze(opts: AnalyzeOptions): Promise<AgentResult> {
    const bin = opts.bin ?? this.bin();
    if (!bin) return { text: '', toolCalls: 0, ok: false, error: 'not_installed' };
    return runCli(bin, claudeAnalyzeArgs({ systemPath: writeSystemPrompt(opts), images: opts.images ?? [] }), opts.prompt, new ClaudeStream(), { cwd: opts.cwd, onText: () => undefined, onTool: () => undefined, ...(opts.signal ? { signal: opts.signal } : {}), ...(opts.onLog ? { onLog: opts.onLog } : {}) });
  }
}

/** 시트 파일을 두는 곳 (분석 cwd 아래). Claude 는 이 폴더만 Read 로 열 수 있다. */
export const SHEETS_DIR = 'sheets';

/**
 * 분석 모드 인자: MCP 없음, 내장 도구 전부 막음, 한 턴.
 * 그림(대표 프레임 시트)이 있으면 Read 를 cwd 의 sheets/ 아래에서만 열어 주고, 읽고 답할 만큼 턴을 준다.
 */
export function claudeAnalyzeArgs(opts: { systemPath: string; images?: string[] }): string[] {
  const withImages = (opts.images?.length ?? 0) > 0;
  return [
    '-p',
    '--output-format',
    'stream-json',
    '--verbose',
    '--include-partial-messages',
    '--mcp-config',
    '{"mcpServers":{}}',
    '--strict-mcp-config',
    ...(withImages ? ['--allowedTools', `Read(./${SHEETS_DIR}/**)`] : []),
    '--disallowedTools',
    ...CLAUDE_DISALLOWED.filter((t) => !(withImages && t === 'Read')),
    '--append-system-prompt-file',
    opts.systemPath,
    '--max-turns',
    withImages ? '4' : '1',
  ];
}

/** 긴 다중행 지침을 Windows 명령줄에 싣지 않는다. https://code.claude.com/docs/en/cli-reference */
function writeSystemPrompt(opts: { cwd: string; system: string }): string {
  const file = path.join(opts.cwd, 'system-prompt.txt');
  fs.writeFileSync(file, opts.system, 'utf8');
  return file;
}
