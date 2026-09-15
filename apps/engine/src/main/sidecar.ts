import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

export type SidecarName = 'ffmpeg' | 'ffprobe' | 'whisper' | 'cloudflared';

/**
 * 사이드카 바이너리 경로. 우선순위:
 * 1. 환경변수 MADI_FFMPEG / MADI_FFPROBE / MADI_WHISPER / MADI_CLOUDFLARED
 * 2. resources/bin/<platform>-<arch>/<name>[.exe]  (배포 경로, git-lfs)
 * 3. (개발 폴백) @ffmpeg-installer / @ffprobe-installer 패키지
 * 4. PATH
 */
export function resolveSidecar(name: SidecarName, binDir: string): string {
  const fromEnv = process.env[`MADI_${name.toUpperCase()}`];
  if (fromEnv) return fromEnv;

  const exe = process.platform === 'win32' ? `${name}.exe` : name;
  const bundled = path.join(binDir, `${process.platform}-${process.arch}`, exe);
  if (fs.existsSync(bundled)) return bundled;

  const installer = fromInstaller(name);
  if (installer) return installer;

  return exe;
}

function fromInstaller(name: SidecarName): string | null {
  const pkg = name === 'ffmpeg' ? '@ffmpeg-installer/ffmpeg' : name === 'ffprobe' ? '@ffprobe-installer/ffprobe' : null;
  if (!pkg) return null;
  try {
    const require = createRequire(import.meta.url);
    const mod = require(pkg) as { path?: string };
    return mod.path && fs.existsSync(mod.path) ? mod.path : null;
  } catch {
    return null;
  }
}
