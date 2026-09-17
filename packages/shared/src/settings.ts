import { z } from 'zod';

export const AiProvider = z.enum(['none', 'claude', 'codex']);
export type AiProvider = z.infer<typeof AiProvider>;

export const RemoteMode = z.enum(['off', 'quick', 'token']);
export type RemoteMode = z.infer<typeof RemoteMode>;

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
  /**
   * 밖에서 접속하기.
   * - off: 이 PC 안에서만.
   * - quick: 계정·토큰 없이 임시 주소를 받는다 (cloudflared --url). 껐다 켜면 주소가 바뀐다.
   * - token: 고정 주소 (Cloudflare Tunnel 토큰이 필요한 고급 방식).
   */
  remoteMode: RemoteMode.default('off'),
  /** remoteMode='token' 일 때 쓰는 Cloudflare Tunnel 토큰. */
  tunnelToken: z.string().nullable().default(null),
  /** 완성본(예전에 만든 결과물) 폴더. 여기 영상을 분석해 편집 스타일을 배운다. 갤러리엔 안 뜬다. */
  referenceFolders: z.array(z.string()).default([]),
});
export type Settings = z.infer<typeof Settings>;

export const DEFAULT_SETTINGS: Settings = {
  workspaceName: '내 스튜디오',
  watchFolders: [],
  ai: { provider: 'none' },
  setupDone: false,
  remoteMode: 'off',
  tunnelToken: null,
  referenceFolders: [],
};

export const SettingsPatch = Settings.partial();
export type SettingsPatch = z.infer<typeof SettingsPatch>;
