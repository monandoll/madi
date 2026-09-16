import { useEffect, useState } from 'react';

export type Screen = 'gallery' | 'settings';

/** 해시 라우팅. 뒤로가기가 그대로 동작하고 라우터 의존성이 없다. */
function read(): Screen {
  return location.hash === '#/settings' ? 'settings' : 'gallery';
}

export function useScreen(): Screen {
  const [screen, setScreen] = useState<Screen>(read);
  useEffect(() => {
    const on = () => setScreen(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return screen;
}

export function go(screen: Screen): void {
  location.hash = screen === 'gallery' ? '' : '#/settings';
}
