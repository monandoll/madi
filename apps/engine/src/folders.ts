import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { type FolderSuggestion, isVideoFile } from '@madi/shared';

/** 홈 아래 흔한 영상 폴더. 라벨은 화면용 한국어. */
const WELL_KNOWN: { dir: string; label: string }[] = [
  { dir: 'Videos', label: '동영상' },
  { dir: 'Movies', label: '동영상' },
  { dir: 'Desktop', label: '바탕화면' },
  { dir: 'Downloads', label: '다운로드' },
];

const COUNT_DEPTH = 2;
const COUNT_CAP = 500;

/** 폴더 안 영상 파일 수 (하위 2단계까지, 500개에서 멈춤). */
export function countVideos(dir: string, depth = COUNT_DEPTH): number {
  let n = 0;
  const walk = (d: string, left: number) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (n >= COUNT_CAP) return;
      if (e.name.startsWith('.')) continue;
      if (e.isFile() && isVideoFile(e.name)) n++;
      else if (e.isDirectory() && left > 0) walk(path.join(d, e.name), left - 1);
    }
  };
  walk(dir, depth);
  return n;
}

export function describeFolder(p: string, watching: string[], label?: string): FolderSuggestion {
  const abs = path.resolve(p);
  return {
    path: abs,
    label: label ?? path.basename(abs) ?? abs,
    videoCount: countVideos(abs),
    selected: watching.some((w) => path.resolve(w) === abs),
  };
}

/**
 * 후보 목록: 지금 감시 중인 폴더 + 홈의 흔한 폴더 중 존재하는 것.
 * 테스트·개발에선 MADI_SUGGEST_ROOT 로 홈을 바꿀 수 있다.
 */
export function suggestFolders(watching: string[]): FolderSuggestion[] {
  const home = process.env['MADI_SUGGEST_ROOT'] ?? os.homedir();
  const seen = new Set<string>();
  const out: FolderSuggestion[] = [];
  for (const w of watching) {
    const abs = path.resolve(w);
    if (seen.has(abs) || !fs.existsSync(abs)) continue;
    seen.add(abs);
    out.push(describeFolder(abs, watching, WELL_KNOWN.find((k) => path.join(home, k.dir) === abs)?.label));
  }
  for (const k of WELL_KNOWN) {
    const abs = path.join(home, k.dir);
    if (seen.has(abs) || !fs.existsSync(abs)) continue;
    seen.add(abs);
    out.push(describeFolder(abs, watching, k.label));
  }
  return out;
}
