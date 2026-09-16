import fs from 'node:fs';
import path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { claudeArgs, ClaudeStream, claudeToolName } from '../src/agent/claude.js';
import { codexArgs, CodexStream, toml } from '../src/agent/codex.js';
import { describeMessage } from '../src/agent/runner.js';
import { DEFAULT_STYLE_MD, StyleProfile } from '../src/agent/style.js';
import { serveStdio } from '../src/mcp/server.js';
import { TOOL_NAMES, toolList } from '../src/mcp/tools.js';
import { tempHome } from './helpers.js';

const j = (o: unknown) => JSON.stringify(o);

describe('ClaudeStream', () => {
  it('글자 조각 → 확정 턴 → 도구 → 결과 순으로 텍스트를 모은다', () => {
    const p = new ClaudeStream();
    expect(p.feed(j({ type: 'system', subtype: 'init' }))).toEqual([]);
    expect(p.feed(j({ type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: '세로로 ' } } }))).toEqual([{ type: 'text', text: '세로로 ' }]);
    p.feed(j({ type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: '만들게요.' } } }));
    expect(p.text).toBe('세로로 만들게요.');
    // 확정 메시지는 같은 글 — 중복되지 않는다
    const ev = p.feed(j({ type: 'assistant', message: { content: [{ type: 'text', text: '세로로 만들게요.' }] } }));
    expect(ev).toEqual([{ type: 'text', text: '세로로 만들게요.' }]);
    const tool = p.feed(j({ type: 'assistant', message: { content: [{ type: 'tool_use', name: 'mcp__madi__render', input: {} }] } }));
    expect(tool).toEqual([{ type: 'tool', name: 'render' }]);
    expect(p.toolCalls).toBe(1);
    p.feed(j({ type: 'assistant', message: { content: [{ type: 'text', text: '다 됐어요.' }] } }));
    expect(p.text).toBe('세로로 만들게요.\n\n다 됐어요.');
    expect(p.feed(j({ type: 'result', subtype: 'success', is_error: false, result: '다 됐어요.' }))).toEqual([{ type: 'done', ok: true }]);
    expect(p.done).toBe(true);
  });

  it('is_error 결과는 실패로, 텍스트가 없으면 result 를 쓴다', () => {
    const p = new ClaudeStream();
    expect(p.feed(j({ type: 'result', subtype: 'error_max_turns', is_error: true, result: 'too many turns' }))).toEqual([{ type: 'done', ok: false, error: 'too many turns' }]);
    const q = new ClaudeStream();
    q.feed(j({ type: 'result', subtype: 'success', is_error: false, result: '결과만 왔어요' }));
    expect(q.text).toBe('결과만 왔어요');
    expect(new ClaudeStream().feed('not json')).toEqual([]);
  });

  it('claude 인자: 우리 MCP 만, 파일 도구 금지, 시스템 프롬프트 덧붙임', () => {
    const args = claudeArgs({ mcpConfigPath: '/x/mcp.json', toolNames: ['render'], system: 'SYS' });
    expect(args.slice(0, 3)).toEqual(['-p', '--output-format', 'stream-json']);
    expect(args).toContain('--strict-mcp-config');
    expect(args).toContain('--include-partial-messages');
    expect(args[args.indexOf('--allowedTools') + 1]).toBe(claudeToolName('render'));
    expect(args).toContain('Bash');
    expect(args[args.indexOf('--append-system-prompt') + 1]).toBe('SYS');
  });
});

describe('CodexStream', () => {
  it('agent_message 턴과 mcp_tool_call 을 읽는다', () => {
    const p = new CodexStream();
    expect(p.feed(j({ type: 'thread.started' }))).toEqual([]);
    expect(p.feed(j({ type: 'item.started', item: { id: 'c1', type: 'mcp_tool_call', server: 'madi', tool: 'get_transcript' } }))).toEqual([{ type: 'tool', name: 'get_transcript' }]);
    expect(p.feed(j({ type: 'item.completed', item: { id: 'c1', type: 'mcp_tool_call', server: 'madi', tool: 'get_transcript' } }))).toEqual([]); // 같은 호출
    expect(p.feed(j({ type: 'item.completed', item: { id: 'm1', type: 'agent_message', text: '봤어요.' } }))).toEqual([{ type: 'text', text: '봤어요.' }]);
    expect(p.feed(j({ type: 'turn.completed', usage: {} }))).toEqual([{ type: 'done', ok: true }]);
    expect(p.toolCalls).toBe(1);
    const q = new CodexStream();
    expect(q.feed(j({ type: 'error', message: 'boom' }))).toEqual([{ type: 'done', ok: false, error: 'boom' }]);
  });

  it('TOML 인라인 값과 codex 인자', () => {
    expect(toml('a"b')).toBe('"a\\"b"');
    expect(toml(['x', 'y'])).toBe('["x", "y"]');
    expect(toml({ A: '1', B: 'two' })).toBe('{A = "1", B = "two"}');
    const args = codexArgs({ mcp: { command: 'node', args: ['/m.mjs'], env: { K: 'v' } }, cwd: '/w', prompt: 'P' });
    expect(args[0]).toBe('exec');
    expect(args).toContain('--json');
    expect(args).toContain('mcp_servers.madi.command="node"');
    expect(args).toContain('mcp_servers.madi.env={K = "v"}');
    expect(args[args.length - 1]).toBe('P');
  });
});

describe('StyleProfile', () => {
  it('기본 규칙을 만들고, 규칙을 한 줄씩 붙이되 중복은 안 붙인다', () => {
    const home = tempHome('madi-style-');
    const s = new StyleProfile(path.join(home, 'style'));
    expect(s.rules()).toBe(DEFAULT_STYLE_MD);
    const before = DEFAULT_STYLE_MD.split('\n').filter((l) => l.startsWith('- ')).length;
    expect(s.appendRule('숏폼은 30초 안쪽으로')).toBe(before + 1);
    expect(s.appendRule('- 숏폼은 30초 안쪽으로')).toBe(before + 1);
    expect(fs.readFileSync(s.mdPath, 'utf8')).toContain('- 숏폼은 30초 안쪽으로');
    expect(s.params().subtitleStyle.fontFamily).toBe('Pretendard');
    s.writeParams({ ...s.params(), subtitleStyle: { ...s.params().subtitleStyle, fontSize: 70 } });
    expect(s.params().subtitleStyle.fontSize).toBe(70);
    fs.rmSync(home, { recursive: true, force: true });
  });
});

describe('MCP stdio 서버', () => {
  it('initialize → tools/list(9개) → tools/call → 모르는 도구는 오류', async () => {
    const stdin = new PassThrough();
    const stdout = new PassThrough();
    const lines: Record<string, unknown>[] = [];
    stdout.on('data', (d: Buffer) => d.toString().split('\n').filter(Boolean).forEach((l) => lines.push(JSON.parse(l) as Record<string, unknown>)));
    const calls: [string, unknown][] = [];
    serveStdio({
      engineUrl: '',
      token: '',
      videoId: 'v',
      runId: 'r',
      stdin,
      stdout,
      call: async (name, input) => {
        calls.push([name, input]);
        return name === 'render' ? { ok: false, error: '못 만들었어요' } : { ok: true, result: { editId: 'e1' } };
      },
    });
    const send = (o: unknown) => stdin.write(`${JSON.stringify(o)}\n`);
    send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    send({ jsonrpc: '2.0', method: 'notifications/initialized' });
    send({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
    send({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'apply_edit', arguments: { crop: 'vertical' } } });
    send({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'render', arguments: { editId: 'e1' } } });
    send({ jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'nope' } });
    send({ jsonrpc: '2.0', id: 6, method: 'ping' });
    await new Promise((r) => setTimeout(r, 50));
    const byId = (id: number) => lines.find((l) => l['id'] === id) as { result?: Record<string, unknown>; error?: { code: number } };
    expect((byId(1).result as { protocolVersion: string }).protocolVersion).toBe('2025-06-18');
    const tools = (byId(2).result as { tools: { name: string; inputSchema: { type: string } }[] }).tools;
    expect(tools.map((t) => t.name)).toEqual(TOOL_NAMES);
    expect(tools.every((t) => t.inputSchema.type === 'object')).toBe(true);
    expect(byId(3).result).toEqual({ content: [{ type: 'text', text: '{"editId":"e1"}' }], isError: false });
    expect(byId(4).result).toEqual({ content: [{ type: 'text', text: '못 만들었어요' }], isError: true });
    expect(byId(5).error?.code).toBe(-32602);
    expect(byId(6).result).toEqual({});
    expect(calls).toEqual([
      ['apply_edit', { crop: 'vertical' }],
      ['render', { editId: 'e1' }],
    ]);
  });

  it('도구 목록의 JSON 스키마에 설명과 필드가 있다', () => {
    const list = toolList();
    const shorts = list.find((t) => t.name === 'extract_shorts')!;
    expect(shorts.description).toContain('9:16');
    const props = (shorts.inputSchema as { properties: Record<string, unknown> }).properties;
    expect(Object.keys(props)).toEqual(['clips', 'subtitles']);
  });
});

describe('describeMessage', () => {
  it('대화 기록을 에이전트가 읽을 한 줄로', () => {
    const base = { id: 'm', videoId: 'v', kind: 'text' as const, jobId: null, outputId: null, createdAt: 0, updatedAt: 0 };
    expect(describeMessage({ ...base, role: 'user', code: 'user.text', params: { text: '안녕' } })).toBe('사용자: 안녕');
    expect(describeMessage({ ...base, role: 'assistant', code: 'greeting', params: {} })).toBeNull();
    expect(describeMessage({ ...base, role: 'user', code: 'action.vertical', params: {} })).toBe('사용자: 세로로 바꿔줘');
    expect(describeMessage({ ...base, role: 'assistant', kind: 'output', code: 'output.ready', params: { title: 'T' } })).toBe('마디: (결과물 "T" 만들어짐)');
    expect(describeMessage({ ...base, role: 'assistant', kind: 'error', code: 'no_audio', params: {} })).toBe('마디: (문제: no_audio)');
  });
});
