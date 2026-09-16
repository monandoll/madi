import fs from 'node:fs';
import path from 'node:path';
import { isVideoFile } from '@madi/shared';

const DEPTH = 2;
const CAP = 300;

/** 완성본 폴더들 안의 영상 파일 (하위 2단계, 300개 상한). 감시(chokidar)는 안 한다 — 완성본은 자주 안 바뀐다. */
export function scanReferenceFolders(folders: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const walk = (dir: string, left: number) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (out.length >= CAP) return;
      if (e.name.startsWith('.')) continue;
      const p = path.join(dir, e.name);
      if (e.isFile() && isVideoFile(e.name)) {
        const abs = path.resolve(p);
        if (!seen.has(abs)) {
          seen.add(abs);
          out.push(abs);
        }
      } else if (e.isDirectory() && left > 1) walk(p, left - 1);
    }
  };
  for (const f of folders) walk(f, DEPTH);
  return out.sort();
}
