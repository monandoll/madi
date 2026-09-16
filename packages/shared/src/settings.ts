import { z } from 'zod';

export const AiProvider = z.enum(['none', 'claude', 'codex']);
export type AiProvider = z.infer<typeof AiProvider>;

/** 개인화는 전부 설정값. 이름을 코드에 박지 않는다. */
export const Settings = z.object({
  /** 화면 헤더에 보이는 스튜디오 이름. 사용자가 정한다. */
  workspaceName: z.string().trim().min(1).max(40),
  /** 감시할 원본 폴더 절대경로. 비어 있으면 갤러리가 비어 있다. */
  watchFolders: z.array(z.string()),
  ai: z.object({
    provider: AiProvider,
  }),
  /** 처음 켰을 때 설정 카드를 끝냈는지. false 면 갤러리 위에 카드가 뜬다. */
  setupDone: z.boolean().default(false),
  /** Cloudflare Tunnel 토큰. 있으면 엔진이 cloudflared 를 띄워 밖에서 접속하게 한다. */
  tunnelToken: z.string().nullable().default(null),
});
export type Settings = z.infer<typeof Settings>;

export const DEFAULT_SETTINGS: Settings = {
  workspaceName: '내 스튜디오',
  watchFolders: [],
  ai: { provider: 'none' },
  setupDone: false,
  tunnelToken: null,
};

export const SettingsPatch = Settings.partial();
export type SettingsPatch = z.infer<typeof SettingsPatch>;
