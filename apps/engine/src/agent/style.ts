import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_SUBTITLE_STYLE, type SubtitleStyle } from '@madi/shared';

/**
 * StyleProfile — 사용자의 편집 취향.
 * - style.md    자연어 규칙. 에이전트 컨텍스트에 항상 들어간다. update_style_rule 이 한 줄씩 붙인다.
 * - params.json 숫자 기본값 (자막 스타일 등). set_subtitle_style(remember) 가 바꾼다.
 * - examples/   few-shot (5단계에서 채운다)
 */
export const DEFAULT_STYLE_MD = `# 편집 규칙

- 자막은 문장 단위로 짧게. 한 줄에 20자 안팎.
- 쉬는 구간(무음)은 잘라내되 말 앞뒤 숨은 남긴다.
- 숏폼은 9:16 세로, 한 동작 = 한 클립. 20~60초.
- 운동 이름, 횟수, 주의사항이 나오는 문장은 자르지 않는다.
`;

export interface StyleParams {
  subtitleStyle: SubtitleStyle;
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
    if (!fs.existsSync(this.paramsPath)) this.writeParams({ subtitleStyle: DEFAULT_SUBTITLE_STYLE });
  }

  rules(): string {
    this.ensure();
    return fs.readFileSync(this.mdPath, 'utf8');
  }

  /** 규칙 한 줄 추가. 이미 있으면 그대로. 규칙 수를 돌려준다. */
  appendRule(rule: string): number {
    const text = this.rules();
    const line = `- ${rule.trim().replace(/^[-*]\s*/, '')}`;
    const lines = text.split('\n');
    if (!lines.some((l) => l.trim() === line)) {
      const next = `${text.replace(/\s+$/, '')}\n${line}\n`;
      fs.writeFileSync(this.mdPath, next, 'utf8');
    }
    return this.rules()
      .split('\n')
      .filter((l) => /^\s*[-*]\s+/.test(l)).length;
  }

  params(): StyleParams {
    this.ensure();
    try {
      const raw = JSON.parse(fs.readFileSync(this.paramsPath, 'utf8')) as Partial<StyleParams>;
      return { subtitleStyle: { ...DEFAULT_SUBTITLE_STYLE, ...(raw.subtitleStyle ?? {}) } };
    } catch {
      return { subtitleStyle: DEFAULT_SUBTITLE_STYLE };
    }
  }

  writeParams(p: StyleParams): void {
    fs.mkdirSync(this.dir, { recursive: true });
    fs.writeFileSync(this.paramsPath, JSON.stringify(p, null, 2), 'utf8');
  }
}
