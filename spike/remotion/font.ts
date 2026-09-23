import { continueRender, delayRender, staticFile } from 'remotion';

/**
 * Pretendard Variable 자체 호스팅. 시스템 폰트 폴백을 허용하지 않는다.
 * 폰트가 다르면 글자 폭이 달라지고 줄바꿈 지점이 원본과 어긋난다.
 */
let loaded: Promise<void> | null = null;

export function loadPretendard(): void {
  if (loaded) return;
  const handle = delayRender('Pretendard 로딩');
  const font = new FontFace(
    'Pretendard Variable',
    `url(${staticFile('fonts/PretendardVariable.woff2')}) format('woff2-variations')`,
    { weight: '45 920' },
  );
  loaded = font
    .load()
    .then((f) => {
      document.fonts.add(f);
      continueRender(handle);
    })
    .catch((e) => {
      continueRender(handle);
      throw e;
    });
}
