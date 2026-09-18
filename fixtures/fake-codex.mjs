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
// `codex login`: 진짜처럼 주소를 한 줄 찍고 끝낸다 (화면 안 터미널 테스트용)
if (args[0] === 'login') {
  process.stdout.write('Codex 로그인\n');
  process.stdout.write('브라우저에서 열기: https://example.invalid/device?code=FAKE-1234\n');
  process.stdout.write('로그인이 끝났어요.\n');
  process.exit(0);
}
if (process.env['MADI_FAKE_CODEX'] === 'login') {
  process.stderr.write('Error: Not logged in. Run `codex login` to authenticate.\n');
  process.exit(1);
}
const prompt = args[args.length - 1] ?? '';
const request = /사용자 요청: (.*)$/m.exec(prompt)?.[1] ?? '';
const emit = (o) => process.stdout.write(`${JSON.stringify(o)}\n`);
// 분석 모드: 완성본 읽기 · 기억 정리 (도구 없이 한 턴)
if (prompt.includes('## 완성본 분석') || prompt.includes('## 기억 정리')) {
  const obj = prompt.includes('## 완성본 분석')
    ? { purpose: '코덱스가 읽은 완성본', tags: ['몸'], shortCandidates: [{ start: 0, end: 3, title: '한 동작', why: '완결' }] }
    : { items: [{ text: '코덱스 기억 한 줄', kind: 'style', scope: 'all', topics: [], evidence: [] }] };
  emit({ type: 'thread.started', thread_id: 'fake-thread' });
  emit({ type: 'turn.started' });
  emit({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: JSON.stringify(obj) } });
  emit({ type: 'turn.completed', usage: { input_tokens: 1, output_tokens: 1 } });
  process.exit(0);
}
emit({ type: 'thread.started', thread_id: 'fake-thread' });
emit({ type: 'turn.started' });
emit({ type: 'item.completed', item: { id: 'item_0', type: 'reasoning', text: '생각 중' } });
emit({ type: 'item.completed', item: { id: 'item_1', type: 'agent_message', text: `코덱스가 "${request}" 라고 들었어요.` } });
emit({ type: 'turn.completed', usage: { input_tokens: 1, output_tokens: 1 } });
