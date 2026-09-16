#!/usr/bin/env node
/**
 * 테스트용 가짜 `codex` CLI. `codex exec --json …` 의 JSONL 출력을 흉내 낸다 (도구는 부르지 않는다).
 * MADI_FAKE_CODEX=login 이면 로그인 안 된 것처럼 stderr 에 적고 1 로 끝난다 (실제 codex 의 문구).
 * MADI_CODEX_BIN=fixtures/fake-codex.mjs 로 끼운다.
 */
const args = process.argv.slice(2);
if (args.includes('--version')) {
  process.stdout.write('codex-cli 0.0.0 (fake)\n');
  process.exit(0);
}
if (process.env['MADI_FAKE_CODEX'] === 'login') {
  process.stderr.write('Error: Not logged in. Run `codex login` to authenticate.\n');
  process.exit(1);
}
const prompt = args[args.length - 1] ?? '';
const request = /사용자 요청: (.*)$/m.exec(prompt)?.[1] ?? '';
const emit = (o) => process.stdout.write(`${JSON.stringify(o)}\n`);
emit({ type: 'thread.started', thread_id: 'fake-thread' });
emit({ type: 'turn.started' });
emit({ type: 'item.completed', item: { id: 'item_0', type: 'reasoning', text: '생각 중' } });
emit({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: `코덱스가 "${request}" 라고 들었어요.` } });
emit({ type: 'turn.completed', usage: { input_tokens: 1, output_tokens: 1 } });
