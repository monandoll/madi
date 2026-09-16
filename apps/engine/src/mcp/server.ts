import type { Readable, Writable } from 'node:stream';
import { toolList, TOOL_NAMES } from './tools.js';

export const MCP_PROTOCOL_VERSION = '2025-06-18';

export interface StdioOptions {
  engineUrl: string;
  token: string;
  videoId: string;
  runId: string;
  stdin: Readable;
  stdout: Writable;
  /** 테스트용: HTTP 대신 직접 부른다 */
  call?: (name: string, input: unknown) => Promise<ToolOutcome>;
}

export interface ToolOutcome {
  ok: boolean;
  /** ok=true 면 결과(JSON 직렬화), false 면 사람이 읽을 오류 */
  result?: unknown;
  error?: string;
}

interface Rpc {
  jsonrpc: '2.0';
  id?: number | string | null;
  method?: string;
  params?: Record<string, unknown>;
}

/** 엔진의 도구 API 로 넘긴다. */
export async function callEngineTool(o: Pick<StdioOptions, 'engineUrl' | 'token' | 'videoId' | 'runId'>, name: string, input: unknown): Promise<ToolOutcome> {
  const res = await fetch(`${o.engineUrl}/api/agent/tools/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-madi-agent': o.token },
    body: JSON.stringify({ videoId: o.videoId, runId: o.runId, input: input ?? {} }),
  });
  const body = (await res.json().catch(() => null)) as ToolOutcome | { error?: { message?: string } } | null;
  if (!res.ok || !body || !('ok' in body)) {
    const msg = (body as { error?: { message?: string } } | null)?.error?.message ?? `engine ${res.status}`;
    return { ok: false, error: msg };
  }
  return body;
}

/** stdin 의 JSON-RPC 요청을 처리해 stdout 으로 답한다. 한 줄 = 한 메시지. */
export function serveStdio(o: StdioOptions): { close(): void } {
  const call = o.call ?? ((name, input) => callEngineTool(o, name, input));
  const write = (msg: unknown) => o.stdout.write(`${JSON.stringify(msg)}\n`);
  const reply = (id: Rpc['id'], result: unknown) => write({ jsonrpc: '2.0', id, result });
  const fail = (id: Rpc['id'], code: number, message: string) => write({ jsonrpc: '2.0', id, error: { code, message } });

  const handle = async (req: Rpc) => {
    const id = req.id ?? null;
    const isNotification = req.id === undefined;
    switch (req.method) {
      case 'initialize':
        reply(id, {
          protocolVersion: MCP_PROTOCOL_VERSION,
          capabilities: { tools: {} },
          serverInfo: { name: 'madi', version: '1' },
        });
        return;
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return;
      case 'ping':
        reply(id, {});
        return;
      case 'tools/list':
        reply(id, { tools: toolList() });
        return;
      case 'tools/call': {
        const name = String(req.params?.['name'] ?? '');
        const input = req.params?.['arguments'] ?? {};
        if (!(TOOL_NAMES as string[]).includes(name)) {
          fail(id, -32602, `unknown tool: ${name}`);
          return;
        }
        let outcome: ToolOutcome;
        try {
          outcome = await call(name, input);
        } catch (err) {
          outcome = { ok: false, error: err instanceof Error ? err.message : String(err) };
        }
        reply(id, {
          content: [{ type: 'text', text: outcome.ok ? JSON.stringify(outcome.result ?? {}) : (outcome.error ?? 'error') }],
          isError: !outcome.ok,
        });
        return;
      }
      default:
        if (!isNotification) fail(id, -32601, `method not found: ${req.method}`);
    }
  };

  let buf = '';
  const onData = (chunk: Buffer | string) => {
    buf += chunk.toString();
    let i: number;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let req: Rpc;
      try {
        req = JSON.parse(line) as Rpc;
      } catch {
        fail(null, -32700, 'parse error');
        continue;
      }
      void handle(req);
    }
  };
  o.stdin.on('data', onData);
  o.stdin.on('end', () => process.exitCode ?? undefined);
  return {
    close() {
      o.stdin.off('data', onData);
    },
  };
}
