import { and, desc, eq } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import type { Segment, TermCorrection } from '@madi/shared';
import type { Db } from '../db/index.js';
import { termCorrections } from '../db/schema.js';

/**
 * 용어 교정 기록 (기획안 §5.2 · §11 `terms`).
 *
 * 사용자가 자막을 고칠 때(직접 쓰기 · set_subtitle_text) 전후 문장을 맞춰 "틀린 말 → 바른 말" 쌍을 남긴다.
 * 바른 말은 다음 자막부터 whisper 에 용어로 알려 주고, 같은 교정이 두 번 이상 쌓이면 whisper 결과에서 바로 바꿔 쓴다
 * (한 번은 오타일 수 있으니). 사용자는 설정에서 목록을 보고 뺄 수 있다.
 */

export interface CorrectionPair {
  wrong: string;
  right: string;
}

/** 이 횟수 이상 쌓인 교정만 자막에 자동으로 적용한다 */
export const AUTO_APPLY_AT = 2;

const PARTICLES = ['으로', '에서', '까지', '부터', '이나', '한테', '을', '를', '이', '가', '은', '는', '의', '에', '도', '로', '과', '와', '만', '요'];

function tokens(text: string): string[] {
  return text.replace(/[.,!?~…"'()\[\]{}:;]/g, ' ').split(/\s+/).filter(Boolean);
}

/** 조사를 뗀다 ("겹갑골을" → "겹갑골"). 남는 게 두 글자 미만이면 그대로. */
function stripParticle(w: string): string {
  for (const p of PARTICLES) if (w.endsWith(p) && w.length - p.length >= 2) return w.slice(0, -p.length);
  return w;
}

/** 두 낱말에서 조사를 뗀다 — 같은 조사면 같이, 다른 조사("겹갑골을" · "견갑골이")여도 각각. */
function stripSharedParticle(a: string, b: string): [string, string] {
  for (const p of PARTICLES) {
    if (a.endsWith(p) && b.endsWith(p) && a.length - p.length >= 2 && b.length - p.length >= 2) return [a.slice(0, -p.length), b.slice(0, -p.length)];
  }
  return [stripParticle(a), stripParticle(b)];
}

function isTermLike(s: string): boolean {
  return s.length >= 2 && s.length <= 12 && !/^\d+$/.test(s);
}

/** 두 낱말의 편집 거리 (글자 단위). */
function editDistance(a: string, b: string): number {
  const prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let diag = prev[0]!;
    prev[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const tmp = prev[j]!;
      prev[j] = Math.min(prev[j]! + 1, prev[j - 1]! + 1, diag + (a[i - 1] === b[j - 1] ? 0 : 1));
      diag = tmp;
    }
  }
  return prev[b.length]!;
}

/** "잘못 들은 말"은 바른 말과 닮았다 (겹갑골 · 견갑골). 완전히 다른 낱말로 바꾼 건 교정이 아니라 다시 쓴 것이다. */
function looksLikeCorrection(wrong: string, right: string): boolean {
  const len = Math.max(wrong.length, right.length);
  return editDistance(wrong, right) <= Math.max(1, Math.floor(len / 2));
}

/** 문장 하나 안에서 낱말이 바뀐 자리 (LCS 로 맞추고, 1:1 로 바뀐 것만). */
export function pairsInLine(before: string, after: string): CorrectionPair[] {
  const a = tokens(before);
  const b = tokens(after);
  if (!a.length || !b.length || a.join(' ') === b.join(' ')) return [];

  // LCS 표
  const n = a.length;
  const m = b.length;
  const L: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) L[i]![j] = a[i] === b[j] ? L[i + 1]![j + 1]! + 1 : Math.max(L[i + 1]![j]!, L[i]![j + 1]!);
  const out: CorrectionPair[] = [];
  // 닮지 않은 낱말로 바뀌거나 낱말이 더해지고 빠진 자리. 절반 넘으면 문장을 다시 쓴 것 — 교정으로 치지 않는다.
  let hard = 0;
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      i++;
      j++;
      continue;
    }
    const dropA = L[i + 1]![j]!;
    const dropB = L[i]![j + 1]!;
    if (dropA === dropB) {
      // 양쪽에서 하나씩 빠진다 = 낱말 하나가 다른 낱말로 바뀐 자리
      const [w, r] = stripSharedParticle(a[i]!, b[j]!);
      if (w !== r && isTermLike(w) && isTermLike(r) && looksLikeCorrection(w, r)) out.push({ wrong: w, right: r });
      else hard++;
      i++;
      j++;
    } else {
      hard++;
      if (dropA > dropB) i++;
      else j++;
    }
  }
  hard += n - i + (m - j);
  return hard * 2 > Math.max(n, m) ? [] : out;
}

/** 자막 전체의 전후를 문장 단위로 맞춰 교정 쌍을 모은다. 시각이 절반 넘게 겹치는 문장끼리 견준다. */
export function diffCorrections(before: Segment[], after: Segment[]): CorrectionPair[] {
  const out: CorrectionPair[] = [];
  const seen = new Set<string>();
  for (const s of after) {
    const prev = before.find((p) => overlapsMostly(p, s));
    if (!prev || prev.text === s.text) continue;
    for (const pair of pairsInLine(prev.text, s.text)) {
      const key = `${pair.wrong}\u0000${pair.right}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(pair);
    }
  }
  return out;
}

function overlapsMostly(a: { start: number; end: number }, b: { start: number; end: number }): boolean {
  const o = Math.min(a.end, b.end) - Math.max(a.start, b.start);
  if (o <= 0) return false;
  return o >= 0.5 * Math.max(0.01, a.end - a.start) || o >= 0.5 * Math.max(0.01, b.end - b.start);
}

/** whisper 결과에 교정을 적용한다 (문장과 단어 둘 다). 바꾼 자리 수를 같이 돌려준다. */
export function applyCorrections(segments: Segment[], corrections: CorrectionPair[]): { segments: Segment[]; replaced: number } {
  const active = corrections.filter((c) => c.wrong && c.right && c.wrong !== c.right).sort((x, y) => y.wrong.length - x.wrong.length);
  if (!active.length) return { segments, replaced: 0 };
  let replaced = 0;
  const fix = (text: string) => {
    let t = text;
    for (const c of active) {
      if (!t.includes(c.wrong)) continue;
      replaced += t.split(c.wrong).length - 1;
      t = t.split(c.wrong).join(c.right);
    }
    return t;
  };
  const out = segments.map((s) => ({ ...s, text: fix(s.text), words: s.words.map((w) => ({ ...w, text: fix(w.text) })) }));
  return { segments: out, replaced };
}

export class CorrectionStore {
  constructor(private readonly db: Db) {}

  list(): TermCorrection[] {
    return this.db.select().from(termCorrections).orderBy(desc(termCorrections.updatedAt)).all();
  }

  /** 자동 적용할 것 (AUTO_APPLY_AT 번 이상). */
  active(): CorrectionPair[] {
    return this.list()
      .filter((c) => c.count >= AUTO_APPLY_AT)
      .map((c) => ({ wrong: c.wrong, right: c.right }));
  }

  /** whisper 에 알려 줄 바른 말들. 한 번이라도 고친 것 전부. */
  rights(): string[] {
    return [...new Set(this.list().map((c) => c.right))];
  }

  /** 쌍마다 한 번씩 센다. 같은 쌍이면 횟수를 올린다. 돌려주는 값은 새로 생기거나 늘어난 줄들. */
  record(pairs: CorrectionPair[], videoId: string | null): TermCorrection[] {
    const now = Date.now();
    const out: TermCorrection[] = [];
    for (const p of pairs) {
      const existing = this.db.select().from(termCorrections).where(and(eq(termCorrections.wrong, p.wrong), eq(termCorrections.right, p.right))).get();
      if (existing) {
        this.db.update(termCorrections).set({ count: existing.count + 1, videoId, updatedAt: now }).where(eq(termCorrections.id, existing.id)).run();
        out.push({ ...existing, count: existing.count + 1, videoId, updatedAt: now });
      } else {
        const row: TermCorrection = { id: nanoid(), wrong: p.wrong, right: p.right, count: 1, videoId, createdAt: now, updatedAt: now };
        this.db.insert(termCorrections).values(row).run();
        out.push(row);
      }
    }
    return out;
  }

  remove(id: string): boolean {
    return this.db.delete(termCorrections).where(eq(termCorrections.id, id)).run().changes > 0;
  }
}
