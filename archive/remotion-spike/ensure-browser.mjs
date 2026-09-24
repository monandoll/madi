/**
 * macOS Gatekeeper 대응.
 *
 * Remotion 이 처음 렌더할 때 Chrome Headless Shell(약 94MB)을 내려받는데,
 * 인터넷에서 받은 서명 없는 Mach-O 라 `com.apple.quarantine` 이 붙는다.
 * 그 상태로는 프로세스가 즉시 죽고 Remotion 은 "Failed to launch the browser process!"
 * 만 보여줘서 원인을 알기 어렵다.
 *
 * 렌더 진입점마다 이 함수를 먼저 부른다.
 */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const CACHE = 'node_modules/.remotion';

export function ensureBrowserRunnable() {
  if (process.platform !== 'darwin') return;
  if (!existsSync(CACHE)) return; // 아직 안 받음. 받은 뒤 다음 실행에서 풀린다
  try {
    execFileSync('xattr', ['-dr', 'com.apple.quarantine', CACHE], { stdio: 'ignore' });
  } catch {
    // xattr 이 없거나 실패해도 렌더 자체는 시도한다
  }
}
