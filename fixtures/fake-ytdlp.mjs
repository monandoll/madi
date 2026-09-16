#!/usr/bin/env node
/**
 * 테스트용 가짜 `yt-dlp`. 진짜처럼 `-o <base>.%(ext)s` 자리에 파일을 만들고 `--print after_move:…` 줄을 stdout 에 찍는다.
 * 어떤 영상이 되는지는 URL 로 고른다:
 *   …/gaps     → fixtures/sample-gaps-8s.mp4 (16:9, 무음 두 번)
 *   …/silent   → fixtures/sample-silent-3s.mp4 (소리 없음)
 *   …/private  → 로그인 필요 오류 (exit 1)
 *   …/nothing  → Unsupported URL 오류 (exit 1)
 *   그 외      → fixtures/sample-5s.mp4
 * 제목은 URL 마지막 조각. MADI_YTDLP=fixtures/fake-ytdlp.mjs 로 끼운다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const FIXTURES = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);

if (args.includes('--version')) {
  process.stdout.write('2099.01.01 (fake yt-dlp)\n');
  process.exit(0);
}

const url = args[args.length - 1] ?? '';
const outTemplate = args[args.indexOf('-o') + 1] ?? '';
const prints = args.flatMap((a, i) => (a === '--print' ? [args[i + 1]] : []));
const slug = url.replace(/[?#].*$/, '').replace(/\/+$/, '').split('/').pop() ?? '';

if (slug === 'private') {
  process.stderr.write('ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.\n');
  process.exit(1);
}
if (slug === 'nothing') {
  process.stderr.write(`ERROR: Unsupported URL: ${url}\n`);
  process.exit(1);
}

const sample = slug === 'gaps' ? 'sample-gaps-8s.mp4' : slug === 'silent' ? 'sample-silent-3s.mp4' : 'sample-5s.mp4';
const filepath = outTemplate.replace('%(ext)s', 'mp4');
fs.mkdirSync(path.dirname(filepath), { recursive: true });
fs.copyFileSync(path.join(FIXTURES, sample), filepath);

const title = decodeURIComponent(slug) || '제목 없음';
for (const p of prints) {
  const tpl = p.replace(/^after_move:/, '');
  process.stdout.write(`${tpl.replace('%(filepath)s', filepath).replace('%(title)s', title)}\n`);
}
