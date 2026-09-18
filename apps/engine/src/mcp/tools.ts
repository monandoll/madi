import { z } from 'zod';
import { TimeRange } from '@madi/shared';

/**
 * 에이전트에 노출하는 편집 도구. 이름·설명·입력 스키마의 단일 출처.
 * MCP 서버(tools/list)와 엔진(입력 검증)이 같이 쓴다. 설명은 모델이 읽는다.
 */
const Hex = z.string().regex(/^#[0-9a-fA-F]{6}$/);

export const TOOL_DEFS = {
  get_transcript: {
    description:
      '영상의 자막(문장 단위, 초 단위 시각)을 돌려준다. 아직 없으면 지금 만든다(길이에 따라 수 분). 소리가 없는 영상이면 실패한다. 어디를 자를지 판단하기 전에 먼저 부른다.',
    input: z.object({}),
  },
  find_silences: {
    description: '말이 없는 구간(무음) 목록을 돌려준다. 잘라내지는 않는다. moving=true 면 말은 없지만 동작이 이어지는 침묵(시범)이라 자르면 안 된다.',
    input: z.object({
      minSec: z.number().min(0.2).max(10).optional().describe('이 길이(초) 이상 이어져야 무음으로 본다. 기본 0.7'),
    }),
  },
  find_scenes: {
    description: '화면이 크게 바뀌는 시각(장면 전환) 목록을 돌려준다. 카메라 앵글이 바뀌거나 동작이 바뀌는 지점을 찾을 때.',
    input: z.object({
      threshold: z.number().min(0.1).max(0.9).optional().describe('민감도. 낮을수록 더 많이 찾는다. 기본 0.4'),
    }),
  },
  propose_cuts: {
    description: '무음을 기준으로 잘라낼 구간(cuts)을 제안한다. 동작이 이어지는 침묵(시범)은 빼고 kept 로 따로 알려 준다 — 그 구간은 자르지 않는다. 적용하려면 cuts 를 apply_edit 에 그대로 넘긴다.',
    input: z.object({
      minSilenceSec: z.number().min(0.2).max(10).optional().describe('기본 0.7'),
      padSec: z.number().min(0).max(2).optional().describe('말 앞뒤로 남길 숨(초). 기본 0.2'),
    }),
  },
  apply_edit: {
    description:
      '편집 결정을 만들거나(editId 없음) 고친다(editId 있음). keep=이 구간만 쓴다(숏폼), cuts=그 안에서 빼는 구간, crop=vertical 이면 9:16, subtitles=자막 번인. 결과 파일을 만들려면 이어서 render 를 부른다.',
    input: z.object({
      editId: z.string().optional(),
      title: z.string().max(80).optional().describe('결과물 이름. 없으면 영상 제목에서 만든다'),
      keep: TimeRange.nullable().optional(),
      cuts: z.array(TimeRange.extend({ reason: z.enum(['silence', 'manual', 'ai']).optional() })).optional(),
      crop: z.enum(['none', 'vertical']).optional(),
      subtitles: z.boolean().optional(),
    }),
  },
  render: {
    description: '편집 결정으로 결과 파일을 만든다. 끝날 때까지 기다렸다가 결과물 정보를 돌려준다. 결과물 카드는 자동으로 대화에 붙는다.',
    input: z.object({ editId: z.string() }),
  },
  extract_shorts: {
    description: '구간 여러 개를 각각 9:16 숏폼 파일로 만든다(자막 포함 여부 선택). 끝날 때까지 기다린다. 카드는 자동으로 붙는다.',
    input: z.object({
      clips: z.array(z.object({ start: z.number().min(0), end: z.number().min(0), title: z.string().max(80).optional() })).min(1).max(10),
      subtitles: z.boolean().optional().describe('기본 true'),
    }),
  },
  set_subtitle_style: {
    description: '자막 모양(글자 크기·색·박스 색·아래 여백)을 바꾼다. editId 가 있으면 그 편집만, remember=true 면 앞으로의 기본값도 바꾼다.',
    input: z.object({
      editId: z.string().optional(),
      fontSize: z.number().int().min(8).max(200).optional(),
      color: Hex.optional(),
      boxColor: Hex.optional(),
      bottom: z.number().min(0).max(1).optional().describe('화면 아래에서 띄우는 비율'),
      remember: z.boolean().optional(),
    }),
  },
  set_subtitle_text: {
    description:
      '자막 문장을 고친다. 들린 말이 틀렸거나 알아듣기 어려울 때, 또는 사용자가 문장을 직접 알려 줬을 때("○○라고 자막 넣어줘", "이 문장 고쳐줘"). lines 는 시작·끝 시각(초)과 글. 그 시각과 겹치는 기존 문장은 이 줄로 바뀐다. replaceAll=true 면 자막 전체를 이 줄들로 새로 만든다. 자막이 아직 없어도 된다. 고친 뒤 화면에 넣으려면 apply_edit(subtitles=true) → render.',
    input: z.object({
      lines: z
        .array(z.object({ start: z.number().min(0), end: z.number().min(0), text: z.string().trim().min(1).max(200) }))
        .min(1)
        .max(200),
      replaceAll: z.boolean().optional(),
    }),
  },
  get_chapters: {
    description: '긴 영상을 챕터로 나눠 돌려준다(제목·시각·숏폼으로 뽑기 좋은 하이라이트 구간). 없으면 지금 만든다(자막이 없으면 자막부터, 수 분). 숏폼을 여러 개 뽑거나 목차를 만들 때 먼저 부른다.',
    input: z.object({
      refresh: z.boolean().optional().describe('true 면 다시 나눈다'),
    }),
  },
  update_style_rule: {
    description:
      '사용자가 "앞으로도 이렇게" 라고 한 편집 규칙을 한 줄 저장한다. 반드시 사용자가 예라고 한 뒤에만 부른다. scope: all=앞으로 모든 영상(기본), topic=topics 에 적은 주제(부위 · 동작)의 영상만, video=이 영상만. kind: style(방식) · keep(반드시 남김) · avoid(피함) · term(용어 표기 — rule 은 용어 자체).',
    input: z.object({
      rule: z.string().trim().min(2).max(200),
      scope: z.enum(['all', 'topic', 'video']).optional(),
      topics: z.array(z.string().trim().min(1).max(30)).max(8).optional(),
      kind: z.enum(['style', 'keep', 'avoid', 'term']).optional(),
    }),
  },
} as const;

export type ToolName = keyof typeof TOOL_DEFS;
export const TOOL_NAMES = Object.keys(TOOL_DEFS) as ToolName[];

export type ToolInput<N extends ToolName> = z.infer<(typeof TOOL_DEFS)[N]['input']>;

/** MCP tools/list 응답용. */
export function toolList(): { name: string; description: string; inputSchema: Record<string, unknown> }[] {
  return TOOL_NAMES.map((name) => {
    const schema = z.toJSONSchema(TOOL_DEFS[name].input, { target: 'draft-7' }) as Record<string, unknown>;
    delete schema['$schema'];
    return { name, description: TOOL_DEFS[name].description, inputSchema: { ...schema, type: 'object' } };
  });
}
