import type { Aspect, PairDiff, ReferenceStats, Segment, StyleLearned } from '@madi/shared';

/** 순수 함수 모음: 완성본 통계 → 배운 값 → 규칙 문장. 파일·DB 를 모른다. */

export function aspectOf(width: number, height: number): Aspect {
  if (width <= 0 || height <= 0) return 'other';
  if (height / width >= 1.5) return '9:16';
  if (width / height >= 1.5) return '16:9';
  return 'other';
}

export function median(nums: number[]): number {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

export function percentile(nums: number[], p: number): number {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  const idx = Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1));
  return s[idx]!;
}

const r1 = (n: number) => Math.round(n * 10) / 10;

/**
 * 완성본 통계를 합친다.
 * - aspect: 70% 이상이 같은 비율이면 그것, 아니면 mixed
 * - silenceMinSec: 완성본에 "남아 있는" 가장 긴 무음의 90분위 + 0.1 → 그보다 긴 무음은 잘라내는 걸로 본다 (0.4~3초)
 * - cutsPerMin: 중앙값
 * - keptRatio / introTrimSec: 짝을 맞춘 원본이 있을 때 중앙값
 */
export function aggregate(stats: ReferenceStats[], now = Date.now()): StyleLearned | null {
  if (stats.length === 0) return null;
  const count = stats.length;
  const byAspect = new Map<Aspect, number>();
  for (const s of stats) byAspect.set(s.aspect, (byAspect.get(s.aspect) ?? 0) + 1);
  const top = [...byAspect.entries()].sort((a, b) => b[1] - a[1])[0]!;
  const aspect: StyleLearned['aspect'] = top[1] / count >= 0.7 && top[0] !== 'other' ? top[0] : 'mixed';
  const withAudio = stats.filter((s) => s.hasAudio);
  const silenceMinSec = withAudio.length ? Math.min(3, Math.max(0.4, r1(percentile(withAudio.map((s) => s.maxSilenceSec), 90) + 0.1))) : 0.7;
  const pairs = stats.map((s) => s.pair).filter((p): p is PairDiff => !!p);
  return {
    count,
    aspect,
    medianDurationSec: r1(median(stats.map((s) => s.durationSec))),
    silenceMinSec,
    cutsPerMin: r1(median(stats.map((s) => s.cutsPerMin))),
    keptRatio: pairs.length ? Math.round(median(pairs.map((p) => p.keptRatio)) * 100) / 100 : null,
    introTrimSec: pairs.length ? r1(median(pairs.map((p) => p.introTrimSec))) : null,
    learnedAt: now,
  };
}

function fmtSec(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  if (m === 0) return `${s}초`;
  return s ? `${m}분 ${s}초` : `${m}분`;
}

/** 배운 값 → style.md 에 들어갈 문장들. 에이전트가 읽으므로 짧고 구체적으로. */
export function learnedRuleLines(l: StyleLearned): string[] {
  const shape = l.aspect === 'mixed' ? '가로·세로 섞어서' : l.aspect === '9:16' ? '세로 9:16' : '가로 16:9';
  const lines = [`(배움) 완성본 ${l.count}개 기준: ${shape}, 보통 ${fmtSec(l.medianDurationSec)} 길이.`, `(배움) 무음은 ${l.silenceMinSec}초를 넘으면 잘라낸다.`];
  if (l.cutsPerMin > 0) lines.push(`(배움) 컷은 1분에 ${Math.round(l.cutsPerMin)}번쯤.`);
  if (l.keptRatio !== null) {
    const intro = l.introTrimSec && l.introTrimSec >= 1 ? ` 앞부분은 ${fmtSec(l.introTrimSec)}쯤 잘라낸다.` : '';
    lines.push(`(배움) 원본의 ${Math.round(l.keptRatio * 100)}% 정도만 남긴다.${intro}`);
  }
  return lines;
}

/** 파일 제목에서 "완성본" 표시(완성, final, 편집, v2, 숏폼1 …)를 떼고 비교용으로 정규화. */
export function normalizeTitle(title: string): string {
  // \b 는 한글에 안 통한다 → 글자·숫자 앞뒤가 아닌 자리로 경계를 잡는다
  const token = /(?<![\p{L}\p{N}])(완성본?|최종|편집본?|final|edit(?:ed)?|export|render(?:ed)?|v\d+|숏폼\s*\d*|short\s*\d*|\d{1,2})(?![\p{L}\p{N}])/gu;
  return title
    .toLowerCase()
    .replace(/\.[a-z0-9]+$/, '')
    .replace(/[\s_\-.()[\]]+/g, ' ')
    .replace(token, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** 완성본 제목이 원본 제목과 같은 영상인지 (정규화 후 같거나 한쪽이 다른 쪽으로 시작). */
export function looksLikeSameVideo(referenceTitle: string, sourceTitle: string): boolean {
  const a = normalizeTitle(referenceTitle);
  const b = normalizeTitle(sourceTitle);
  if (!a || !b || a.length < 2 || b.length < 2) return false;
  return a === b || a.startsWith(b) || b.startsWith(a);
}

const norm = (s: string) => s.toLowerCase().replace(/[\s\p{P}]/gu, '');

/**
 * 원본 자막과 완성본 자막을 문장 단위 LCS 로 맞춰서, 원본의 어디가 살아남았는지 본다.
 * - keptRatio: 살아남은 문장 길이 / 원본 문장 길이 (말한 부분 기준)
 * - introTrimSec / outroTrimSec: 살아남은 첫 문장 앞, 마지막 문장 뒤의 원본 길이
 * - cutCount: 살아남은 문장 사이의 빈 구간 수
 */
export function pairDiff(original: Segment[], finished: Segment[], originalDurationSec: number, videoId: string): PairDiff | null {
  if (original.length === 0 || finished.length === 0) return null;
  const a = original.map((s) => norm(s.text));
  const b = finished.map((s) => norm(s.text));
  // LCS 테이블
  const n = a.length;
  const m = b.length;
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i]![j] = a[i] && a[i] === b[j] ? dp[i + 1]![j + 1]! + 1 : Math.max(dp[i + 1]![j]!, dp[i]![j + 1]!);
    }
  }
  const kept: number[] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] && a[i] === b[j]) {
      kept.push(i);
      i++;
      j++;
    } else if (dp[i + 1]![j]! >= dp[i]![j + 1]!) i++;
    else j++;
  }
  if (kept.length === 0) return null;
  const total = original.reduce((acc, s) => acc + Math.max(0, s.end - s.start), 0);
  const keptSec = kept.reduce((acc, k) => acc + Math.max(0, original[k]!.end - original[k]!.start), 0);
  let cutCount = 0;
  for (let k = 1; k < kept.length; k++) if (kept[k]! - kept[k - 1]! > 1) cutCount++;
  const first = original[kept[0]!]!;
  const last = original[kept[kept.length - 1]!]!;
  return {
    videoId,
    keptRatio: total > 0 ? Math.min(1, Math.round((keptSec / total) * 100) / 100) : 1,
    introTrimSec: r1(Math.max(0, first.start)),
    outroTrimSec: r1(Math.max(0, originalDurationSec - last.end)),
    cutCount,
  };
}
