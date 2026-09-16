# design/

Claude Design 내보내기. **참조용, 수정 금지.** UI 구현 전에 반드시 해당 화면의 마크업을 열어 구조·간격·문구를 확인한다.

**현재 시안은 `v2/`** (2차, 푸른 회색 계열). 바로 아래 파일들은 1차 시안이라 참고용.

| 파일 | 내용 |
|---|---|
| `v2/Mobile.dc.html` | 모바일(375) 프로토타입: 갤러리 · 영상 상세(채팅, 결과물·챕터 카드) · 결과물 · 설정 · AI 미연결 빈 상태. 아래 탭 3개. |
| `v2/Desktop.dc.html` | PC(1280) 프로토타입: 첫 실행 · 사이드바(영상/결과물/진행 중) · 갤러리 · 영상 채팅 · 결과물 패널 · 설정. |
| `v2/Install.dc.html` | 설치 페이지 (`apps/site`). |
| `Mobile.dc.html` | (1차) 모바일 3화면: 갤러리 · 영상 상세 · 결과물. |
| `support.js` | Design Components 런타임(`<x-dc>`, `<sc-for>`, `<sc-if>`, `{{ }}`). `Mobile.dc.html`이 브라우저에서 렌더되게 한다. |
| `madi-mobile.bundle.html` | 위 둘 + React + Pretendard 폰트가 전부 인라인된 단일 파일. 브라우저에서 바로 열면 시안이 보인다. |

폰트는 `apps/web/public/fonts/PretendardVariable.woff2`(self-host)와 같은 파일이다.

원본 프로젝트: https://claude.ai/design/p/499b2e20-8086-473c-be84-d41a1b315d29
