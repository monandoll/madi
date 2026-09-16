// esbuild로 Electron 메인을 번들하고, 웹 빌드·마이그레이션을 dist 옆에 둔다.
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const dist = path.join(root, 'dist');
fs.rmSync(dist, { recursive: true, force: true });

await build({
  entryPoints: [path.join(root, 'src/main/index.ts')],
  outfile: path.join(dist, 'main.mjs'),
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node22',
  external: ['electron', 'better-sqlite3', 'electron-updater', '@ffmpeg-installer/ffmpeg', '@ffprobe-installer/ffprobe'],
  banner: { js: "import { createRequire as __cr } from 'node:module'; const require = __cr(import.meta.url);" },
  sourcemap: true,
});

// 트레이·앱 아이콘
await import('./tray-icon.mjs');

const webDist = path.resolve(root, '../web/dist');
const resources = path.join(root, 'resources');
fs.rmSync(path.join(resources, 'web'), { recursive: true, force: true });
if (fs.existsSync(webDist)) fs.cpSync(webDist, path.join(resources, 'web'), { recursive: true });
fs.rmSync(path.join(resources, 'drizzle'), { recursive: true, force: true });
fs.cpSync(path.join(root, 'drizzle'), path.join(resources, 'drizzle'), { recursive: true });
console.log('engine built → dist/main.mjs, resources/{web,drizzle}');
