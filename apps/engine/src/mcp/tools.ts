import { z } from 'zod';
import { TimeRange, VideoFramesRequest, SubtitleStylePatch, CaptionLine } from '@madi/shared';

/**
 * 에이전트에 노출하는 편집 도구. 이름·설명·입력 스키마의 단일 출처.
 * MCP 서버(tools/list)와 엔진(입력 검증)이 같이 쓴다. 설명은 모델이 읽는다.
 */
/** 세로로 자를 때 잡을 쪽. auto 는 렌더할 때 움직이는 쪽을 고른다. */
const Focus = z.enum(['auto', 'left', 'center', 'right']).describe('세로(9:16)로 자를 때 어느 쪽을 잡을지. 기본 auto = 화면에서 움직이는 쪽');

export const TOOL_DEFS = {
  inspect_video_frames: {
    description: '영상의 실제 화면을 시각 순서의 이미지로 본다. 동작·자세 변화·화면 자막을 확인하거나 동작에 맞는 안내 자막을 요청받으면 반드시 먼저 사용한다. editId가 있으면 그 결과에 남는 원본 장면만 결과 순서로 본다. 반환 이미지의 각 칸은 왼쪽→오른쪽, 위→아래 순서이며 sourceTime은 자막 도구에 쓰는 원본 초, outputTime은 선택한 결과물 초다. 표본만 본 것이므로 동작 전환이 불명확하면 range를 좁혀 다시 본다. 장면 전환/음성/기존 생성 자막만으로 동작을 추측하지 않는다.',
    input: VideoFramesRequest,
  },
  get_transcript: {
    description:
      '영상의 자막(문장 단위, 초 단위 시각)을 돌려준다. 아직 없으면 지금 만든다(길이에 따라 수 분). 소리가 없는 영상이면 실패한다. 어디를 자를지 판단하기 전에 먼저 부른다.',
    input: z.object({ editId: z.string().optional().describe('기존 결과물 자막을 읽을 때 그 editId. 음성 인식을 다시 하지 않는다.') }),
  },
  find_silences: {
    description: '말이 없는 구간(무음) 목록을 돌려준다. 잘라내지는 않는다. moving=true 면 말은 없지만 동작이 이어지는 침묵(시범)이라 자르면 안 된다.',
    input: z.object({
      minSec: z.number().min(0.2).max(10).optional().describe('이 길이(초) 이상 이어져야 무음으로 본다. 기본 0.7'),
    }),
  },
  find_scenes: {
    description: '화면이 크게 바뀌는 시각(장면 전환) 목록을 돌려준다. 동작의 의미를 보거나 이름을 식별하는 도구가 아니다. 한 장면에서도 동작은 여러 번 바뀔 수 있으며 실제 동작 확인은 inspect_video_frames를 쓴다.',
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
      '편집 결정을 만들거나(editId 없음) 고친다(editId 있음 — 결과물이 이미 있으면 새 편집이 되고 changes 에 달라진 점이 온다). keep=이 구간만 쓴다(숏폼), parts=여러 조각을 이 순서대로 이어 붙인다(시범을 먼저, 설명을 뒤에 — keep 대신), cuts=그 안에서 빼는 구간, crop=vertical 이면 9:16, focus=세로로 자를 때 어느 쪽을 잡을지(기본 auto: 움직이는 쪽), subtitles=자막 번인, emphasis=자막에서 강조할 단어(구간을 주면 거기서만). 결과 파일을 만들려면 이어서 render 를 부른다.',
    input: z.object({
      editId: z.string().optional(),
      title: z.string().max(80).optional().describe('결과물 이름. 없으면 영상 제목에서 만든다'),
      keep: TimeRange.nullable().optional(),
      parts: z.array(TimeRange).max(12).optional().describe('이어 붙일 조각들, 결과물에 나올 순서대로. 빈 배열이면 keep 으로 돌아간다'),
      cuts: z.array(TimeRange.extend({ reason: z.enum(['silence', 'manual', 'ai']).optional() })).optional(),
      crop: z.enum(['none', 'vertical']).optional(),
      focus: Focus.optional(),
      subtitles: z.boolean().optional(),
      subtitleStyle: SubtitleStylePatch.optional().describe('이 편집에 실제 적용할 자막 설정. 기억·편집안의 모양을 여기에 전달한다. bottom 지정 시 자동 위치 변경을 끈다.'),
      emphasis: z
        .array(z.object({ term: z.string().trim().min(1).max(40), start: z.number().min(0).optional(), end: z.number().min(0).optional() }))
        .max(20)
        .optional()
        .describe('자막에서 굵게 · 다른 색으로 띄울 단어들. start/end(초)를 주면 그 구간에서만 ("견갑골 설명에만"). 주면 목록 전체를 바꾼다, 빈 배열이면 강조를 다 지운다. subtitles=true 여야 보인다'),
    }),
  },
  render: {
    description: '편집 결정으로 결과 파일을 만든다. 끝날 때까지 기다렸다가 결과물 정보를 돌려준다. 결과물 카드는 자동으로 대화에 붙는다.',
    input: z.object({ editId: z.string() }),
  },
  extract_shorts: {
    description:
      '구간 여러 개를 각각 9:16 숏폼 파일로 만든다(자막 포함 여부 선택). 한 숏폼을 여러 조각으로 구성하려면(시범 먼저, 설명 뒤에) clip 에 parts 를 준다. 끝날 때까지 기다린다. 카드는 자동으로 붙는다.',
    input: z.object({
      clips: z
        .array(
          z.object({
            start: z.number().min(0),
            end: z.number().min(0),
            title: z.string().max(80).optional(),
            parts: z.array(TimeRange).max(12).optional().describe('이 숏폼을 이루는 조각들, 나올 순서대로. 있으면 start/end 는 무시한다'),
            focus: Focus.optional(),
          }),
        )
        .min(1)
        .max(10),
      subtitles: z.boolean().optional().describe('기본 true'),
    }),
  },
  set_subtitle_style: {
    description: '자막 모양을 실제로 바꾼다. background=outline은 박스 없는 테두리 글자, box는 배경 박스. 본문 크기·색·굵기·기울임·테두리·아래 여백과 보조 문구의 secondaryScale/secondaryColor/secondaryItalic을 지정한다. editId가 있으면 그 편집만(이미 출력했으면 새 editId 반환), remember=true는 사용자가 앞으로도 적용하라고 했을 때만 쓴다. bottom 지정 시 자동 위치를 끈다.',
    input: SubtitleStylePatch.extend({
      editId: z.string().optional(),
      remember: z.boolean().optional(),
    }),
  },
  set_subtitle_text: {
    description:
      '사용자가 원하는 자막 문구를 넣거나 고친다. text는 본문, secondaryText는 그 아래에 표시할 번역·보조 문구(없으면 생략). 음성·음성 인식 없이도 된다. 기존 결과물 수정에는 editId를 지정하고 반환된 editId로 render한다. 시각은 원본 초. replaceAll=true는 전체 교체, 빈 lines는 전체 삭제. editId가 없으면 원본 자막 버전을 만들고 apply_edit(subtitles=true) → render로 출력한다.',
    input: z.object({
      editId: z.string().optional(),
      lines: z
        .array(CaptionLine)
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
