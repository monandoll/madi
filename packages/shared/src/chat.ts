import { z } from 'zod';

/**
 * 영상별 대화. AI 미연결 상태에서도 엔진이 정해진 문구 코드로 말한다.
 * 문구 자체는 UI(copy.ts)가 코드 → 문장으로 바꾼다. 오류도 코드.
 * - text: 코드 + params 로 문장
 * - progress: jobId 의 진행을 보여주는 카드 (끝나면 output / error 로 바뀐다)
 * - output: outputId 결과물 카드
 * - error: 오류 코드 (AI 말투 문구)
 */
export const ChatKind = z.enum(['text', 'progress', 'output', 'error']);
export type ChatKind = z.infer<typeof ChatKind>;

export const ChatRole = z.enum(['assistant', 'user']);
export type ChatRole = z.infer<typeof ChatRole>;

export const ChatMessage = z.object({
  id: z.string(),
  videoId: z.string(),
  role: ChatRole,
  kind: ChatKind,
  code: z.string(),
  params: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()])),
  jobId: z.string().nullable(),
  outputId: z.string().nullable(),
  createdAt: z.number().int(),
  updatedAt: z.number().int(),
});
export type ChatMessage = z.infer<typeof ChatMessage>;
