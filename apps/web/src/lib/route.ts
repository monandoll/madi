import { useEffect, useState } from 'react';

export type Route = { screen: 'gallery' } | { screen: 'settings' } | { screen: 'video'; id: string } | { screen: 'output'; id: string };

/** 해시 라우팅. 뒤로가기가 그대로 동작하고 라우터 의존성이 없다. */
function read(): Route {
  const h = location.hash;
  if (h === '#/settings') return { screen: 'settings' };
  let m = /^#\/videos\/([A-Za-z0-9_-]+)$/.exec(h);
  if (m) return { screen: 'video', id: m[1]! };
  m = /^#\/outputs\/([A-Za-z0-9_-]+)$/.exec(h);
  if (m) return { screen: 'output', id: m[1]! };
  return { screen: 'gallery' };
}

export function useRoute(): Route {
  const [route, setRoute] = useState<Route>(read);
  useEffect(() => {
    const on = () => setRoute(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return route;
}

export function hrefOf(r: Route): string {
  switch (r.screen) {
    case 'gallery':
      return '#/';
    case 'settings':
      return '#/settings';
    case 'video':
      return `#/videos/${r.id}`;
    case 'output':
      return `#/outputs/${r.id}`;
  }
}

export function go(r: Route): void {
  location.hash = hrefOf(r);
}

/** 뒤로가기. 이전 화면이 없으면 갤러리로. */
export function back(fallback: Route = { screen: 'gallery' }): void {
  if (history.length > 1) history.back();
  else go(fallback);
}
