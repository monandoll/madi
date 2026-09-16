import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

export type SidecarName = 'ffmpeg' | 'ffprobe' | 'whisper' | 'cloudflared' | 'ytdlp';

/**
 * 사이드카 바이너리 경로. 우선순위:
 * 1. 환경변수 MADI_FFMPEG / MADI_FFPROBE / MADI_WHISPER / MADI_CLOUDFLARED / MADI_YTDLP
 * 2. resources/bin/<platform>-<arch>/<name>[.exe]  (배포 경로, git-lfs)
 * 3. (개발 폴백) @ffmpeg-installer / @ffprobe-installer 패키지
 * 4. PATH
 */
export function resolveSidecar(name: SidecarName, binDir: string): string {
  const fromEnv = process.env[`MADI_${name.toUpperCase()}`];
  if (fromEnv) return fromEnv;

  // whisper.cpp 의 실행 파일 이름은 whisper-cli, yt-dlp 는 하이픈
  const base = name === 'whisper' ? 'whisper-cli' : name === 'ytdlp' ? 'yt-dlp' : name;
  const exe = process.platform === 'win32' ? `${base}.exe` : base;
  const bundled = path.join(binDir, `${process.platform}-${process.arch}`, exe);
  if (fs.existsSync(bundled)) return bundled;

  const installer = fromInstaller(name);
  if (installer) return installer;

  return exe;
}

/** whisper 모델 파일. MADI_WHISPER_MODEL(경로) > ~/.madi/models/ggml-<name>.bin */
export function resolveWhisperModel(modelsDir: string): { path: string; name: string } {
  const fromEnv = process.env['MADI_WHISPER_MODEL'];
  if (fromEnv) return { path: fromEnv, name: path.basename(fromEnv).replace(/^ggml-|\.bin$/g, '') };
  const name = process.env['MADI_WHISPER_MODEL_NAME'] ?? 'base';
  return { path: path.join(modelsDir, `ggml-${name}.bin`), name };
}

/** 없으면 huggingface 에서 받아 둔다. 진행률은 0..1. */
export async function ensureWhisperModel(model: { path: string; name: string }, onProgress?: (r: number) => void): Promise<string> {
  if (fs.existsSync(model.path)) return model.path;
  fs.mkdirSync(path.dirname(model.path), { recursive: true });
  const url = `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model.name}.bin`;
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok || !res.body) throw new Error(`model download failed: ${res.status}`);
  const total = Number(res.headers.get('content-length') ?? 0);
  const tmp = `${model.path}.part`;
  const out = fs.createWriteStream(tmp);
  let got = 0;
  for await (const chunk of res.body as unknown as AsyncIterable<Uint8Array>) {
    out.write(chunk);
    got += chunk.length;
    if (total) onProgress?.(got / total);
  }
  await new Promise<void>((resolve, reject) => out.end((err?: Error | null) => (err ? reject(err) : resolve())));
  fs.renameSync(tmp, model.path);
  return model.path;
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
