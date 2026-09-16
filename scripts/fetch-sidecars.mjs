#!/usr/bin/env node
/**
 * 사이드카 바이너리·폰트 가져오기.
 *   node scripts/fetch-sidecars.mjs [--platform win32-x64|darwin-arm64|darwin-x64] [--only ffmpeg,cloudflared,fonts]
 *
 * 결과:
 *   resources/bin/<platform-arch>/{ffmpeg,ffprobe,whisper-cli,cloudflared,yt-dlp}[.exe]
 *   resources/fonts/Pretendard-*.otf
 *
 * 출처는 전부 공식 배포본(GitHub Releases 등). git 에는 넣지 않는다 (.gitignore).
 * whisper-cli 의 macOS 빌드는 릴리스 워크플로에서 소스로 만든다 (여기서는 Windows 만).
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BIN = path.join(ROOT, 'resources', 'bin');
const FONTS = path.join(ROOT, 'resources', 'fonts');

const WHISPER_VERSION = 'v1.7.6';
const CLOUDFLARED_VERSION = '2025.8.1';
const PRETENDARD_VERSION = '1.3.9';

/** platform-arch → 받을 것들. url 안의 파일을 dest 이름으로 둔다. zip/tgz 는 안에서 pick 으로 고른다. */
const MANIFEST = {
  'win32-x64': [
    {
      name: 'ffmpeg',
      // BtbN 의 "latest" 릴리스에는 master 빌드만 고정 이름으로 있다 (버전 고정 이름은 404).
      url: 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip',
      pick: [
        { match: /\/bin\/ffmpeg\.exe$/, dest: 'ffmpeg.exe' },
        { match: /\/bin\/ffprobe\.exe$/, dest: 'ffprobe.exe' },
      ],
    },
    {
      name: 'whisper',
      url: `https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/whisper-bin-x64.zip`,
      // whisper-cli.exe 와 같이 들어 있는 dll 들을 전부
      pick: [{ match: /(whisper-cli\.exe|\.dll)$/i, dest: null }],
    },
    {
      name: 'cloudflared',
      url: `https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-windows-amd64.exe`,
      dest: 'cloudflared.exe',
    },
    // 링크로 배우기 (유튜브·틱톡·릴스). 사이트가 자주 바뀌어 빌드 시점의 최신을 쓴다. 단일 실행 파일(파이썬 불필요).
    { name: 'ytdlp', url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe', dest: 'yt-dlp.exe' },
  ],
  'darwin-arm64': [
    { name: 'ffmpeg', url: 'https://www.osxexperts.net/ffmpeg71arm.zip', pick: [{ match: /(^|\/)ffmpeg$/, dest: 'ffmpeg' }] },
    { name: 'ffprobe', url: 'https://www.osxexperts.net/ffprobe71arm.zip', pick: [{ match: /(^|\/)ffprobe$/, dest: 'ffprobe' }] },
    {
      name: 'cloudflared',
      url: `https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-darwin-arm64.tgz`,
      pick: [{ match: /(^|\/)cloudflared$/, dest: 'cloudflared' }],
    },
    // yt-dlp_macos 는 universal2 (arm64 + x64) 한 파일
    { name: 'ytdlp', url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos', dest: 'yt-dlp' },
  ],
  'darwin-x64': [
    { name: 'ffmpeg', url: 'https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip', pick: [{ match: /(^|\/)ffmpeg$/, dest: 'ffmpeg' }] },
    { name: 'ffprobe', url: 'https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip', pick: [{ match: /(^|\/)ffprobe$/, dest: 'ffprobe' }] },
    {
      name: 'cloudflared',
      url: `https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-darwin-amd64.tgz`,
      pick: [{ match: /(^|\/)cloudflared$/, dest: 'cloudflared' }],
    },
    { name: 'ytdlp', url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos', dest: 'yt-dlp' },
  ],
};

const FONT = {
  name: 'fonts',
  url: `https://github.com/orioncactus/pretendard/releases/download/v${PRETENDARD_VERSION}/Pretendard-${PRETENDARD_VERSION}.zip`,
  pick: [{ match: /public\/static\/Pretendard-(Regular|SemiBold|Bold)\.otf$/, dest: null }],
};

function hasBin(name) {
  try {
    execFileSync(process.platform === 'win32' ? 'where' : 'which', [name], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

async function download(url, to) {
  const res = await fetch(url, { redirect: 'follow', headers: { 'user-agent': 'madi-fetch-sidecars' } });
  if (!res.ok) throw new Error(`${url} → ${res.status}`);
  fs.writeFileSync(to, Buffer.from(await res.arrayBuffer()));
}

/**
 * zip/tgz 를 임시 폴더에 풀고 안의 파일 목록을 돌려준다.
 * zip 은 unzip 이 있으면 unzip 으로 (GNU tar 는 zip 을 못 푼다), 없으면 tar 로 (Windows/macOS 의 bsdtar 는 zip 도 푼다).
 */
function extract(archive, into) {
  fs.mkdirSync(into, { recursive: true });
  if (archive.endsWith('.zip') && process.platform !== 'win32' && hasBin('unzip')) {
    execFileSync('unzip', ['-q', '-o', archive, '-d', into], { stdio: 'inherit' });
  } else {
    execFileSync('tar', ['-xf', archive, '-C', into], { stdio: 'inherit' });
  }
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else out.push(p);
    }
  };
  walk(into);
  return out;
}

async function fetchItem(item, destDir, tmp) {
  fs.mkdirSync(destDir, { recursive: true });
  const file = path.join(tmp, path.basename(new URL(item.url).pathname) || `${item.name}.bin`);
  console.log(`↓ ${item.name}: ${item.url}`);
  await download(item.url, file);
  if (!item.pick) {
    const dest = path.join(destDir, item.dest);
    fs.copyFileSync(file, dest);
    fs.chmodSync(dest, 0o755);
    console.log(`  → ${path.relative(ROOT, dest)}`);
    return;
  }
  const files = extract(file, path.join(tmp, `${item.name}-x`));
  for (const rule of item.pick) {
    const hits = files.filter((f) => rule.match.test(f.replace(/\\/g, '/')));
    if (hits.length === 0) throw new Error(`${item.name}: nothing matched ${rule.match}`);
    for (const hit of hits) {
      const dest = path.join(destDir, rule.dest ?? path.basename(hit));
      fs.copyFileSync(hit, dest);
      fs.chmodSync(dest, 0o755);
      console.log(`  → ${path.relative(ROOT, dest)}`);
    }
  }
}

const platform = arg('platform', `${process.platform}-${process.arch}`);
const only = arg('only', '').split(',').filter(Boolean);
const fontsOnly = only.length > 0 && only.every((n) => n === 'fonts');
const items = MANIFEST[platform] ?? [];
if (!MANIFEST[platform] && !fontsOnly) {
  console.error(`unknown platform ${platform}; one of ${Object.keys(MANIFEST).join(', ')}`);
  process.exit(1);
}
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'madi-sidecars-'));
try {
  for (const item of items) {
    if (only.length && !only.includes(item.name)) continue;
    await fetchItem(item, path.join(BIN, platform), tmp);
  }
  if (!only.length || only.includes('fonts')) await fetchItem(FONT, FONTS, tmp);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
console.log('done');
