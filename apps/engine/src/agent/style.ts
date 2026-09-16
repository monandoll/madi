import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_SUBTITLE_STYLE, type StyleLearned, type StyleRule, type SubtitleStyle } from '@madi/shared';

/**
 * StyleProfile — 사용자의 편집 취향.
 * - style.md    자연어 규칙. 에이전트 컨텍스트에 항상 들어간다.
 *               사용자가 쓴 줄 + 맨 아래 학습 블록(완성본에서 배운 줄, 자동 갱신).
 * - params.json 숫자: 자막 스타일, 무음 기준, 배운 값.
 * - examples/   few-shot (나중).
 */
export const DEFAULT_STYLE_MD = `# 편집 규칙

- 자막은 문장 단위로 짧게. 한 줄에 20자 안팎.
- 쉬는 구간(무음)은 잘라내되 말 앞뒤 숨은 남긴다.
- 숏폼은 9:16 세로, 한 동작 = 한 클립. 20~60초.
- 운동 이름, 횟수, 주의사항이 나오는 문장은 자르지 않는다.
`;

const LEARNED_START = '<!-- learned:start -->';
const LEARNED_END = '<!-- learned:end -->';
export const DEFAULT_SILENCE_MIN_SEC = 0.7;

export interface StyleParams {
  subtitleStyle: SubtitleStyle;
  /** 이 길이(초) 넘는 무음을 잘라낸다. 완성본에서 배우면 바뀐다. */
  silenceMinSec: number;
  learned: StyleLearned | null;
}

export class StyleProfile {
  readonly mdPath: string;
  readonly paramsPath: string;

  constructor(readonly dir: string) {
    this.mdPath = path.join(dir, 'style.md');
    this.paramsPath = path.join(dir, 'params.json');
  }

  ensure(): void {
    fs.mkdirSync(path.join(this.dir, 'examples'), { recursive: true });
    if (!fs.existsSync(this.mdPath)) fs.writeFileSync(this.mdPath, DEFAULT_STYLE_MD, 'utf8');
    if (!fs.existsSync(this.paramsPath)) this.writeParams({ subtitleStyle: DEFAULT_SUBTITLE_STYLE, silenceMinSec: DEFAULT_SILENCE_MIN_SEC, learned: null });
  }

  /** 전체 텍스트 (에이전트에 그대로 들어간다). */
  rules(): string {
    this.ensure();
    return fs.readFileSync(this.mdPath, 'utf8');
  }

  /** 규칙 줄 목록. 학습 블록 안의 줄은 learned. */
  rulesList(): StyleRule[] {
    const { head, learned } = this.split(this.rules());
    const pick = (text: string, isLearned: boolean) =>
      text
        .split('\n')
        .filter((l) => /^\s*[-*]\s+\S/.test(l))
        .map((l) => ({ text: l.replace(/^\s*[-*]\s+/, '').trim(), learned: isLearned }));
    return [...pick(head, false), ...pick(learned, true)];
  }

  /** 규칙 한 줄 추가(학습 블록 앞에). 이미 있으면 그대로. 사용자 규칙 수를 돌려준다. */
  appendRule(rule: string): number {
    const line = `- ${rule.trim().replace(/^[-*]\s*/, '')}`;
    const { head, learned } = this.split(this.rules());
    if (!head.split('\n').some((l) => l.trim() === line)) {
      this.write(`${head.replace(/\s+$/, '')}\n${line}\n`, learned);
    }
    return this.rulesList().filter((r) => !r.learned).length;
  }

  /** 사용자 규칙 하나 지우기. index 는 rulesList 기준. 학습 줄이면 false. */
  removeRule(index: number): boolean {
    const list = this.rulesList();
    const target = list[index];
    if (!target || target.learned) return false;
    const { head, learned } = this.split(this.rules());
    const lines = head.split('\n');
    let seen = 0;
    const next = lines.filter((l) => {
      if (!/^\s*[-*]\s+\S/.test(l)) return true;
      const keep = seen !== index;
      seen++;
      return keep;
    });
    this.write(`${next.join('\n').replace(/\s+$/, '')}\n`, learned);
    return true;
  }

  /** 학습 블록과 params.learned 를 통째로 바꾼다. lines 가 비면 블록을 없앤다. */
  setLearned(learned: StyleLearned | null, lines: string[]): void {
    const { head } = this.split(this.rules());
    const block = lines.length ? lines.map((l) => `- ${l}`).join('\n') : '';
    this.write(`${head.replace(/\s+$/, '')}\n`, block);
    const p = this.params();
    this.writeParams({ ...p, learned, silenceMinSec: learned ? learned.silenceMinSec : DEFAULT_SILENCE_MIN_SEC });
  }

  params(): StyleParams {
    this.ensure();
    try {
      const raw = JSON.parse(fs.readFileSync(this.paramsPath, 'utf8')) as Partial<StyleParams>;
      return {
        subtitleStyle: { ...DEFAULT_SUBTITLE_STYLE, ...(raw.subtitleStyle ?? {}) },
        silenceMinSec: typeof raw.silenceMinSec === 'number' && raw.silenceMinSec > 0 ? raw.silenceMinSec : DEFAULT_SILENCE_MIN_SEC,
        learned: raw.learned ?? null,
      };
    } catch {
      return { subtitleStyle: DEFAULT_SUBTITLE_STYLE, silenceMinSec: DEFAULT_SILENCE_MIN_SEC, learned: null };
    }
  }

  writeParams(p: StyleParams): void {
    fs.mkdirSync(this.dir, { recursive: true });
    fs.writeFileSync(this.paramsPath, JSON.stringify(p, null, 2), 'utf8');
  }

  private split(text: string): { head: string; learned: string } {
    const s = text.indexOf(LEARNED_START);
    const e = text.indexOf(LEARNED_END);
    if (s < 0 || e < s) return { head: text, learned: '' };
    return { head: text.slice(0, s), learned: text.slice(s + LEARNED_START.length, e).trim() };
  }

  private write(head: string, learnedBlock: string): void {
    const body = learnedBlock ? `${head}\n${LEARNED_START}\n${learnedBlock}\n${LEARNED_END}\n` : head;
    fs.writeFileSync(this.mdPath, body, 'utf8');
  }
}
