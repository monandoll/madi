#!/usr/bin/env node
/**
 * 테스트용 가짜 `claude` CLI. 진짜처럼 --mcp-config 의 MCP 서버를 자식으로 띄워 도구를 부르고,
 * `--output-format stream-json --include-partial-messages` 형식으로 stdout 에 쓴다.
 * 시나리오는 프롬프트 마지막 줄("사용자 요청: …")의 낱말로 고른다.
 *   세로   → apply_edit(vertical) + render
 *   조각   → extract_shorts(parts: 뒤 조각 먼저, focus=left)
 *   강조   → apply_edit(subtitles, emphasis: 단어를 0–2초에서만) + render
 *   고쳐줘: <editId> → apply_edit(editId, cuts 0–1) + render (결과물이 있으면 새 편집 · changes)
 *   규칙   → update_style_rule
 *   문장   → set_subtitle_text (사용자 문장을 0–2초 자막으로)
 *   자막   → get_transcript (whisper 없으면 도구 오류를 그대로 전한다)
 *   실패   → result is_error
 *   느리게 → 8초 기다린다 (취소 테스트)
 *   그 외  → 요청을 되풀이하는 답 한 마디
 * MADI_CLAUDE_BIN=fixtures/fake-claude.mjs 로 끼운다.
 */
import fs from 'node:fs';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
// `claude setup-token`: 진짜처럼 주소를 찍고 코드를 기다리는 척한다 (화면 안 터미널 테스트용)
if (args[0] === 'setup-token') {
  process.stdout.write('Claude Code 로그인\n');
  process.stdout.write('브라우저에서 열기: https://example.invalid/oauth?code=FAKE\n');
  process.stdout.write('로그인이 끝났어요.\n');
  process.exit(0);
}
if (args.includes('--version')) {
  process.stdout.write('9.9.9 (fake Claude Code)\n');
  process.exit(0);
}
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const mcpConfigPath = flag('--mcp-config');
const system = flag('--append-system-prompt-file') ? fs.readFileSync(flag('--append-system-prompt-file'), 'utf8') : flag('--append-system-prompt') ?? '';
const prompt = await new Promise((resolve) => {
  let s = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (d) => (s += d));
  process.stdin.on('end', () => resolve(s));
});
const request = /사용자 요청: (.*)$/m.exec(prompt)?.[1] ?? '';
const emit = (o) => process.stdout.write(`${JSON.stringify(o)}\n`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- 분석 모드 (MCP 없이 한 턴): 완성본 읽기 · 기억 정리 ----
// 진짜 답처럼 코드펜스와 앞말을 붙여서 준다 (파서가 그걸 벗겨야 한다).
if (mcpConfigPath === '{"mcpServers":{}}') {
  // 화면 시트: 프롬프트가 ./sheets/… 를 열어 보라 하고, 그 폴더가 Read 로 열려 있고, 파일이 실제로 있으면 "봤다"
  const sheetFiles = [...prompt.matchAll(/^- (\.\/sheets\/[^:]+):/gm)].map((m) => m[1]);
  const canRead = args.includes('--allowedTools') && args[args.indexOf('--allowedTools') + 1] === 'Read(./sheets/**)' && !args.slice(args.indexOf('--disallowedTools') + 1).includes('Read');
  const sawFrames = canRead && sheetFiles.length > 0 && sheetFiles.every((f) => fs.existsSync(f));
  if (sheetFiles.length && !canRead) {
    process.stderr.write('fake-claude: sheets in prompt but Read not allowed\n');
    process.exit(2);
  }
  const answer = (obj) => {
    const text = `정리했습니다.\n\`\`\`json\n${JSON.stringify(obj, null, 2)}\n\`\`\``;
    emit({ type: 'system', subtype: 'init', tools: [], mcp_servers: [] });
    emit({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text }] } });
    emit({ type: 'result', subtype: 'success', is_error: false, result: text, num_turns: 1 });
    process.exit(0);
  };
  if (prompt.includes('## 완성본 분석')) {
    const title = /^제목: (.*)$/m.exec(prompt)?.[1] ?? '';
    const times = [...prompt.matchAll(/^\[(\d+):(\d+)–(\d+):(\d+)\]/gm)].map((m) => [Number(m[1]) * 60 + Number(m[2]), Number(m[3]) * 60 + Number(m[4])]);
    const end = times.length ? times[times.length - 1][1] : 5;
    const part = /어깨|shoulder/i.test(title) ? '어깨' : /햄스트링|hamstring/i.test(title) ? '햄스트링' : '몸';
    answer({
      purpose: `${part} 불편한 사람을 위한 ${title}`,
      audience: '운동 초보',
      hook: '불편함을 먼저 말하고 동작으로 넘어간다',
      tone: '존댓말 설명조',
      sections: [
        { title: '도입', start: 0, end: Math.min(1, end), kind: 'intro' },
        { title: '시범', start: Math.min(1, end), end, kind: 'demo' },
      ],
      keyPoints: ['천천히 호흡하면서'],
      keepRanges: [{ start: Math.min(1, end), end, why: '동작 시범 — 말이 없어도 남긴다' }],
      cutCandidates: [],
      shortCandidates: [{ start: 0, end, title: `${part} 한 동작`, why: '설명과 시범이 한 번에 완결된다' }],
      terms: ['견갑골', '외회전'],
      subtitleNotes: '한 줄 12자 안팎',
      visual: sawFrames ? '사람이 가운데 크게, 자막은 아래' : '',
      tags: [part, '스트레칭'],
    });
  }
  if (prompt.includes('## 편집안')) {
    // 촬영본 편집안: 길이 안에서 구성 · 남길 곳 · 잘라낼 후보 · 숏폼 후보. 자막이 있으면 첫 문장을 제목에.
    const dur = Number(/^길이\(초\): (\d+)/m.exec(prompt)?.[1] ?? 8);
    const title = /^제목: (.*)$/m.exec(prompt)?.[1] ?? '';
    const hasText = !prompt.includes('자막: 없음');
    const first = /^\[\d+:\d+–\d+:\d+\] (.*)$/m.exec(prompt)?.[1] ?? '';
    const cutEnd = Math.min(1, dur / 4);
    answer({
      purpose: `${title} — 동작 하나를 설명하고 보여 준다`,
      audience: '운동 초보',
      hook: '인사를 빼고 동작 설명부터',
      sections: [
        { title: hasText && first ? first.slice(0, 20) : '도입', start: 0, end: Math.min(2, dur / 2), kind: 'intro', note: '인사는 빼고 핵심 문장부터' },
        { title: '시범', start: Math.min(2, dur / 2), end: dur, kind: 'demo', note: '시범 속도 그대로' },
      ],
      keepRanges: [{ start: Math.min(2, dur / 2), end: dur, why: '동작 시범 — 말이 없어도 남긴다' }],
      cutCandidates: [{ start: 0, end: cutEnd, why: '인사 · 촬영 세팅 멘트', kind: 'aside' }],
      shortCandidates: [{ start: Math.min(1, dur / 4), end: dur, title: `${title} 한 동작`, why: '설명과 시범이 한 번에 완결된다', channel: 'reels' }],
      terms: ['견갑골'],
      tags: ['어깨', '스트레칭'],
      framing: sawFrames ? { side: 'right', note: '사람이 오른쪽에 서 있다' } : null,
    });
  }
  if (prompt.includes('## 기억 정리')) {
    // 기억은 완성본 두 편 이상이 근거여야 남는다 (parseMemory) — 주제 기억도 두 편을 근거로 단다
    const ids = [...prompt.matchAll(/\(id: ([^)]+)\)/g)].map((m) => m[1]);
    answer({
      items: [
        { text: '도입은 시청자의 불편함을 먼저 말하고 동작으로 넘어간다', kind: 'style', scope: 'all', topics: [], evidence: ids },
        { text: '동작 시범 중 말이 없는 구간은 잘라내지 않는다', kind: 'keep', scope: 'all', topics: [], evidence: ids },
        { text: '어깨는 견갑골 움직임이 보이게 잡는다', kind: 'style', scope: 'topic', topics: ['어깨'], evidence: ids.slice(0, 2) },
        { text: '견갑골', kind: 'term', scope: 'all', topics: [], evidence: ids },
      ],
    });
  }
  answer({});
}

// ---- MCP 클라이언트 (stdio JSON-RPC) ----
const cfg = JSON.parse(fs.readFileSync(mcpConfigPath, 'utf8'));
const srv = cfg.mcpServers.madi;
const child = spawn(srv.command, srv.args, { env: { ...process.env, ...srv.env }, stdio: ['pipe', 'pipe', 'inherit'] });
let nextId = 1;
const waiting = new Map();
let buf = '';
child.stdout.setEncoding('utf8');
child.stdout.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    const w = waiting.get(msg.id);
    if (w) {
      waiting.delete(msg.id);
      msg.error ? w.reject(new Error(msg.error.message)) : w.resolve(msg.result);
    }
  }
});
const rpc = (method, params) =>
  new Promise((resolve, reject) => {
    const id = nextId++;
    waiting.set(id, { resolve, reject });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  });
const notify = (method) => child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method })}\n`);

await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'fake-claude', version: '0' } });
notify('notifications/initialized');
const { tools } = await rpc('tools/list');
emit({ type: 'system', subtype: 'init', tools: tools.map((t) => `mcp__madi__${t.name}`), mcp_servers: [{ name: 'madi', status: 'connected' }] });

let last = '';
function say(text) {
  // 글자 스트리밍처럼 두 조각으로, 그 다음 확정 assistant 메시지
  const half = Math.ceil(text.length / 2);
  emit({ type: 'stream_event', event: { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: text.slice(0, half) } } });
  emit({ type: 'stream_event', event: { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: text.slice(half) } } });
  emit({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text }] } });
  last = text;
}
async function call(name, input) {
  emit({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', id: `tu_${nextId}`, name: `mcp__madi__${name}`, input }] } });
  const res = await rpc('tools/call', { name, arguments: input });
  const text = res.content?.[0]?.text ?? '';
  emit({ type: 'user', message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: `tu_${nextId}`, content: text, is_error: !!res.isError }] } });
  if (res.isError) throw new Error(text);
  return JSON.parse(text);
}
function finish(ok, resultText) {
  emit(ok ? { type: 'result', subtype: 'success', is_error: false, result: resultText, num_turns: nextId } : { type: 'result', subtype: 'error_during_execution', is_error: true, result: resultText });
  child.stdin.end();
  child.kill();
  process.exit(ok ? 0 : 1);
}

try {
  if (request.includes('세로')) {
    say('세로로 만들게요.');
    const e = await call('apply_edit', { crop: 'vertical', title: 'AI 세로' });
    const r = await call('render', { editId: e.editId });
    say(`「${r.title}」 만들었어요. ${r.aspect} 이에요.`);
  } else if (request.includes('조각')) {
    // 시범(뒤)을 먼저, 설명(앞)을 뒤에 — 조각 순서대로 이어 붙인 숏폼. 사람이 왼쪽에 있다고 치고 focus=left.
    say('시범을 먼저 보여 주고 설명을 뒤에 붙일게요.');
    const r = await call('extract_shorts', { clips: [{ start: 0, end: 5, title: 'AI 조각', parts: [{ start: 3, end: 5 }, { start: 0, end: 2 }], focus: 'left' }], subtitles: false });
    say(`「${r.outputs[0].title}」 만들었어요. ${r.outputs[0].durationSec}초예요.`);
  } else if (request.includes('강조')) {
    // "○○ 강조해줘": 그 단어를 자막 첫 2초에서만 강조한 결과물
    const term = (request.split(':')[1] ?? '앱').trim();
    say(`"${term}" 를 처음 나올 때만 띄울게요.`);
    const e = await call('apply_edit', { subtitles: true, title: 'AI 강조', emphasis: [{ term, start: 0, end: 2 }] });
    const r = await call('render', { editId: e.editId });
    say(`「${r.title}」 만들었어요. ${e.emphasis?.length ?? 0}개 단어를 띄웠어요.`);
  } else if (!request.includes('문장') && /고쳐줘:\s*\S{10,}/.test(request)) {
    // "고쳐줘: <editId>" → 그 편집을 고친다 (앞 1초를 더 잘라냄). 결과물이 있는 편집이면 새 편집이 되고 changes 가 온다.
    const editId = request.split(':')[1].trim();
    say('앞부분을 조금 더 잘라낼게요.');
    const e = await call('apply_edit', { editId, cuts: [{ start: 0, end: 1 }] });
    const r = await call('render', { editId: e.editId });
    say(`「${r.title}」 다시 만들었어요. ${e.changes?.cuts?.added?.length ?? 0}곳을 더 잘라냈어요.${e.revisionOf ? ' 이전 것과 비교할 수 있어요.' : ''}`);
  } else if (request.includes('규칙')) {
    await call('update_style_rule', { rule: '숏폼은 30초 안쪽으로' });
    say('앞으로 그렇게 할게요.');
  } else if (request.includes('문장')) {
    // "이 문장 고쳐줘: …" / "○○라고 자막 넣어줘" → 사용자 문장을 그 구간에 넣는다
    const text = (request.split(':')[1] ?? '안녕하세요 앱 소개합니다').trim();
    const r = await call('set_subtitle_text', { lines: [{ start: 0, end: 2, text }] });
    say(`자막 ${r.segments.length}줄 중 첫 줄을 "${text}" 로 바꿨어요.`);
  } else if (request.includes('자막')) {
    try {
      const t = await call('get_transcript', {});
      say(`자막 ${t.segments.length}줄을 봤어요.`);
    } catch (err) {
      say(`자막을 못 봤어요. ${err.message}`);
    }
  } else if (request.includes('실패')) {
    finish(false, 'fake failure');
  } else if (request.includes('느리게')) {
    say('천천히 할게요.');
    await sleep(8000);
    say('다 했어요.');
  } else {
    say(`"${request}" 라고 하셨네요. 규칙 ${system.includes('편집 규칙') ? '읽었어요' : '못 읽었어요'}. 지침 ${system.includes('제작 지침') ? '있어요' : '없어요'}. 기억 ${system.includes('# 기억') ? '있어요' : '없어요'}. 편집안 ${prompt.includes('# 이 영상의 편집안') ? '있어요' : '없어요'}. 뺀 후보 ${prompt.includes('사용자가 뺀 후보') ? '있어요' : '없어요'}.`);
  }
  finish(true, last);
} catch (err) {
  say(`문제가 생겼어요: ${err.message}`);
  finish(true, last);
}
