/**
 * 폰 브라우저(특히 iOS Safari) 대응. 두 가지:
 *
 * 1. 확대 — iOS 는 글자가 16px 보다 작은 입력창을 누르면 화면을 확대한다. 시안의 입력창은 13~15px 이다.
 *    viewport 에 maximum-scale=1 을 주면 그 확대만 안 하고, 손가락 확대는 그대로 된다 (iOS 10+ 는 이 값을 손가락 확대에 안 쓴다).
 *    안드로이드 크롬은 이 값이 손가락 확대까지 막으므로 iOS 에서만 붙인다.
 * 2. 키보드 — iOS 는 키보드가 올라와도 레이아웃 높이(100%)를 안 줄이고 페이지를 밀어 올려, 위 제목과 아래 탭이 화면 밖으로 나간다.
 *    실제 보이는 높이(visualViewport)를 재서 #root 높이로 주고(--app-height), 밀린 만큼 되돌린다.
 *    손가락 확대 중(scale ≠ 1)에는 손대지 않는다.
 */
export function isIos(nav: Pick<Navigator, 'userAgent' | 'platform' | 'maxTouchPoints'> = navigator): boolean {
  return /iP(hone|ad|od)/.test(nav.userAgent) || (nav.platform === 'MacIntel' && nav.maxTouchPoints > 1);
}

/** 보이는 높이가 창 높이보다 이만큼 작으면 키보드가 올라온 것으로 본다 (주소창 접힘은 이보다 작다) */
const KEYBOARD_MIN_PX = 150;

export function setupViewport(win: Window = window): () => void {
  const doc = win.document;
  if (isIos(win.navigator)) {
    const meta = doc.querySelector('meta[name="viewport"]');
    const content = meta?.getAttribute('content') ?? '';
    if (meta && !/maximum-scale/.test(content)) meta.setAttribute('content', `${content}, maximum-scale=1`);
  }
  const vv = win.visualViewport;
  if (!vv) return () => undefined;
  const apply = () => {
    if (vv.scale !== 1) return;
    doc.documentElement.style.setProperty('--app-height', `${Math.round(vv.height)}px`);
    const keyboard = win.innerHeight - vv.height > KEYBOARD_MIN_PX;
    if (keyboard && (win.scrollY > 0 || vv.offsetTop > 0)) win.scrollTo(0, 0);
  };
  vv.addEventListener('resize', apply);
  vv.addEventListener('scroll', apply);
  apply();
  return () => {
    vv.removeEventListener('resize', apply);
    vv.removeEventListener('scroll', apply);
  };
}
