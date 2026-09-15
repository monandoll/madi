import { z } from 'zod';

export const AiProvider = z.enum(['none', 'claude', 'codex']);
export type AiProvider = z.infer<typeof AiProvider>;

/** 개인화는 전부 설정값. 이름을 코드에 박지 않는다. */
export const Settings = z.object({
  workspaceName: z.string().min(1).max(40),
  /** 감시할 원본 폴더 절대경로. 비어 있으면 갤러리가 비어 있다. */
  watchFolders: z.array(z.string()),
  ai: z.object({
    provider: AiProvider,
  }),
});
export type Settings = z.infer<typeof Settings>;

export const DEFAULT_SETTINGS: Settings = {
  workspaceName: '내 스튜디오',
  watchFolders: [],
  ai: { provider: 'none' },
};

export const SettingsPatch = Settings.partial();
export type SettingsPatch = z.infer<typeof SettingsPatch>;
