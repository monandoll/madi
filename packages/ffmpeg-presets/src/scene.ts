/** 장면 전환 감지. 프레임 차이가 threshold(0..1) 를 넘는 시각을 stderr(showinfo) 로 낸다. */
export function sceneDetectArgs(input: string, threshold = 0.4): string[] {
  return ['-hide_banner', '-nostdin', '-i', input, '-an', '-vf', `select='gt(scene,${threshold})',showinfo`, '-vsync', 'vfr', '-f', 'null', '-'];
}

/** showinfo 출력의 pts_time → 장면이 바뀌는 시각 목록(초, 오름차순, 중복 없음). */
export function parseScenes(stderr: string): number[] {
  const out: number[] = [];
  for (const line of stderr.split('\n')) {
    if (!/Parsed_showinfo/.test(line)) continue;
    const m = /pts_time:\s*(-?[\d.]+)/.exec(line);
    if (!m) continue;
    const t = Number(m[1]);
    if (Number.isFinite(t) && t >= 0 && (out.length === 0 || t - out[out.length - 1]! > 0.05)) out.push(t);
  }
  return out;
}

/** 장면 시각 → 구간 목록. 너무 짧은 구간(minSec 미만)은 다음 경계까지 이어 붙인다(맨 끝이면 앞 구간에). */
export function scenesToRanges(scenes: number[], durationSec: number, minSec = 1): { start: number; end: number }[] {
  const bounds = [0, ...scenes.filter((t) => t > 0 && t < durationSec), durationSec];
  const ranges: { start: number; end: number }[] = [];
  let start = 0;
  for (let i = 1; i < bounds.length; i++) {
    const end = bounds[i]!;
    const isLast = i === bounds.length - 1;
    if (end - start < minSec) {
      if (isLast) {
        const last = ranges[ranges.length - 1];
        if (last) last.end = end;
        else if (end > start) ranges.push({ start, end });
      }
      continue;
    }
    ranges.push({ start, end });
    start = end;
  }
  return ranges.filter((r) => r.end - r.start > 0.01);
}
