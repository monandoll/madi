#!/usr/bin/env node
/**
 * macOS arm64 / x64 를 서로 다른 러너에서 만들면 둘 다 latest-mac.yml 을 올려 나중 것이 앞 것을 덮는다.
 * 그러면 electron-updater 가 한쪽 아키텍처 zip 만 보게 된다. 두 파일의 files 목록을 합쳐 하나로 만든다.
 *
 *   node scripts/merge-latest-mac.mjs a/latest-mac.yml b/latest-mac.yml > latest-mac.yml
 *
 * electron-builder 가 내는 yml 은 모양이 고정이라(version / files[] / path / sha512 / releaseDate) 파서 없이 줄로 다룬다.
 */
import fs from 'node:fs';

/** yml 문자열 → { head: files 앞 줄들, files: 항목별 줄 묶음, tail: files 뒤 최상위 줄들 } */
export function parseLatestYml(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const start = lines.findIndex((l) => /^files:\s*$/.test(l));
  if (start < 0) throw new Error('latest-mac.yml: no files: block');
  let end = start + 1;
  while (end < lines.length && /^\s+/.test(lines[end]) ) end++;
  const files = [];
  for (const l of lines.slice(start + 1, end)) {
    if (/^\s*-\s/.test(l)) files.push([l]);
    else if (files.length) files[files.length - 1].push(l);
    else throw new Error(`latest-mac.yml: unexpected line in files: ${l}`);
  }
  return { head: lines.slice(0, start), files, tail: lines.slice(end).filter((l, i, a) => !(i === a.length - 1 && l === '')) };
}

const urlOf = (entry) => entry.map((l) => l.match(/^\s*-?\s*url:\s*(.+?)\s*$/)?.[1]).find(Boolean) ?? '';

/** 첫 파일의 머리·꼬리를 쓰고, files 는 전부 합친다 (같은 url 은 한 번). arm64 항목이 앞에 오게 정렬한다. */
export function mergeLatestYml(texts) {
  if (texts.length === 0) throw new Error('nothing to merge');
  const parsed = texts.map(parseLatestYml);
  const seen = new Set();
  const files = [];
  for (const p of parsed) {
    for (const f of p.files) {
      const url = urlOf(f);
      if (!url || seen.has(url)) continue;
      seen.add(url);
      files.push(f);
    }
  }
  files.sort((a, b) => Number(/-x64\./.test(urlOf(a))) - Number(/-x64\./.test(urlOf(b))));
  const first = parsed[0];
  return [...first.head, 'files:', ...files.flat(), ...first.tail].join('\n') + '\n';
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const paths = process.argv.slice(2);
  if (paths.length === 0) {
    console.error('usage: merge-latest-mac.mjs <latest-mac.yml>...');
    process.exit(2);
  }
  process.stdout.write(mergeLatestYml(paths.map((p) => fs.readFileSync(p, 'utf8'))));
}
