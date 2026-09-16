import { describe, expect, it } from 'vitest';
// @ts-expect-error 릴리스 워크플로용 스크립트 (타입 없음)
import { mergeLatestYml, parseLatestYml } from '../scripts/merge-latest-mac.mjs';

const arm = `version: 0.1.0
files:
  - url: madi-engine-0.1.0-mac-arm64.zip
    sha512: AAA
    size: 111
    blockMapSize: 11
  - url: madi-engine-0.1.0-mac-arm64.pkg
    sha512: BBB
    size: 222
path: madi-engine-0.1.0-mac-arm64.zip
sha512: AAA
releaseDate: '2026-09-16T00:00:00.000Z'
`;
const x64 = `version: 0.1.0
files:
  - url: madi-engine-0.1.0-mac-x64.zip
    sha512: CCC
    size: 333
  - url: madi-engine-0.1.0-mac-x64.pkg
    sha512: DDD
    size: 444
path: madi-engine-0.1.0-mac-x64.zip
sha512: CCC
releaseDate: '2026-09-16T00:01:00.000Z'
`;

describe('merge-latest-mac', () => {
  it('files 블록을 나눠 읽는다', () => {
    const p = parseLatestYml(x64) as { head: string[]; files: string[][]; tail: string[] };
    expect(p.head).toEqual(['version: 0.1.0']);
    expect(p.files).toHaveLength(2);
    expect(p.files[1]).toEqual(['  - url: madi-engine-0.1.0-mac-x64.pkg', '    sha512: DDD', '    size: 444']);
    expect(p.tail).toEqual(['path: madi-engine-0.1.0-mac-x64.zip', 'sha512: CCC', "releaseDate: '2026-09-16T00:01:00.000Z'"]);
  });

  it('두 아키텍처 files 를 합치고(arm64 먼저), 머리·꼬리는 첫 파일 것을 쓴다', () => {
    const merged = mergeLatestYml([x64, arm]) as string;
    expect(merged).toBe(`version: 0.1.0
files:
  - url: madi-engine-0.1.0-mac-arm64.zip
    sha512: AAA
    size: 111
    blockMapSize: 11
  - url: madi-engine-0.1.0-mac-arm64.pkg
    sha512: BBB
    size: 222
  - url: madi-engine-0.1.0-mac-x64.zip
    sha512: CCC
    size: 333
  - url: madi-engine-0.1.0-mac-x64.pkg
    sha512: DDD
    size: 444
path: madi-engine-0.1.0-mac-x64.zip
sha512: CCC
releaseDate: '2026-09-16T00:01:00.000Z'
`);
    // 같은 파일을 두 번 넣어도 한 번만
    expect(mergeLatestYml([arm, arm]) as string).toBe(arm);
  });
});
