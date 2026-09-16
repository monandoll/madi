import { z } from 'zod';

/**
 * 영상별 대화. AI 미연결 상태에서도 엔진이 정해진 문구 코드로 말한다.
 * 문구 자체는 UI(copy.ts)가 코드 → 문장으로 바꾼다. 오류도 코드.
 * - text: 코드 + params 로 문장
 * - progress: jobId 의 진행을 보여주는 카드 (끝나면 output / error 로 바뀐다)
 * - output: outputId 결과물 카드
 * - error: 오류 코드 (AI 말투 문구)
 *
 * AI 연결 뒤의 자유 문장은 코드 두 개로 흐른다:
 * - 'user.text'  params.text — 사용자가 친 말 그대로
 * - 'ai.text'    params.text — 에이전트 답. params.streaming 이 true 면 아직 쓰는 중,
 *                params.status 가 'working' 이면 도구를 돌리는 중(내용은 안 보여준다).
 */
export const ChatKind = z.enum(['text', 'progress', 'output', 'error']);
export type ChatKind = z.infer<typeof ChatKind>;

export const ChatRole = z.enum(['assistant', 'user']);
export type ChatRole = z.infer<typeof ChatRole>;

export const ChatParams = z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()]));
export type ChatParams = z.infer<typeof ChatParams>;

export const ChatMessage = z.object({
  id: z.string(),
  videoId: z.string(),
  role: ChatRole,
  kind: ChatKind,
  code: z.string(),
  params: ChatParams,
  jobId: z.string().nullable(),
  outputId: z.string().nullable(),
  createdAt: z.number().int(),
  updatedAt: z.number().int(),
});
export type ChatMessage = z.infer<typeof ChatMessage>;

/** 에이전트 답 메시지가 아직 진행 중인지. */
export function isStreaming(m: Pick<ChatMessage, 'code' | 'params'>): boolean {
  return m.code === 'ai.text' && m.params['streaming'] === true;
}
