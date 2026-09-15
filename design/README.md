# design/

Claude Design 내보내기. **참조용, 수정 금지.** UI 구현 전에 반드시 해당 화면의 마크업을 열어 구조·간격·문구를 확인한다.

| 파일 | 내용 |
|---|---|
| `Mobile.dc.html` | 모바일(375) 3화면: 갤러리 · 영상 상세(채팅) · 결과물 자세히. 읽기 좋은 원본 마크업. |
| `support.js` | Design Components 런타임(`<x-dc>`, `<sc-for>`, `<sc-if>`, `{{ }}`). `Mobile.dc.html`이 브라우저에서 렌더되게 한다. |
| `madi-mobile.bundle.html` | 위 둘 + React + Pretendard 폰트가 전부 인라인된 단일 파일. 브라우저에서 바로 열면 시안이 보인다. |

폰트는 `apps/web/public/fonts/PretendardVariable.woff2`(self-host)와 같은 파일이다.

원본 프로젝트: https://claude.ai/design/p/499b2e20-8086-473c-be84-d41a1b315d29
