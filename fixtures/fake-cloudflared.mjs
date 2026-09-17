#!/usr/bin/env node
/**
 * 테스트용 가짜 `cloudflared`. 진짜 빠른 터널처럼 주소 한 줄과 연결 로그를 stderr 에 찍고 계속 살아 있는다.
 *   tunnel --no-autoupdate --url <로컬>   → https://<이름>.trycloudflare.com 을 알려 준다
 *   tunnel --no-autoupdate run --token …  → 주소 없이 연결만 된다
 * 주소의 앞부분은 MADI_FAKE_TUNNEL_HOST 로 바꿀 수 있다. MADI_CLOUDFLARED=fixtures/fake-cloudflared.mjs 로 끼운다.
 */
const args = process.argv.slice(2);

if (args.includes('--version')) {
  process.stdout.write('cloudflared version 2099.1.1 (fake)\n');
  process.exit(0);
}

const quick = args.includes('--url');
if (quick) {
  const host = process.env['MADI_FAKE_TUNNEL_HOST'] ?? 'madi-test-tunnel';
  process.stderr.write('INF +--------------------------------------------------------+\n');
  process.stderr.write(`INF |  https://${host}.trycloudflare.com                      |\n`);
  process.stderr.write('INF +--------------------------------------------------------+\n');
}
process.stderr.write('INF Registered tunnel connection connIndex=0 location=icn01\n');

// 끝날 때까지 살아 있는다 (엔진이 kill 한다)
setInterval(() => {}, 1 << 30);
process.on('SIGTERM', () => process.exit(0));
