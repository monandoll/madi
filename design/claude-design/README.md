# Claude Design 시안 (참고용)

2026-09-25, Claude Design 프로젝트 "1단계 갤러리 화면 디자인" 에서 내보냈다.
이후 디자인은 Claude Design 이 아니라 **AI(Claude Code)가 SwiftUI 로 직접** 한다 (`docs/prompts/design.md`).
이 폴더는 그 AI 가 출발점으로 쓰는 **참고 자료**다. 픽셀 정답이 아니다.

| 파일 | 상태 |
|---|---|
| `01-Gallery-v2.dc.html` | macOS 네이티브 방향으로 다시 만든 갤러리. **이게 방향이다** |
| `02-Editor-v2.dc.html` | 편집안 상세 네이티브판. 마지막 작업이 "문제 발견 → 고치는 중" 에 끊겨 **검토 안 됨** |
| `03-Results.dc.html` | 결과물 · 만드는 중 · 실패. **아직 웹 스타일** |
| `04-Onboarding-Settings.dc.html` | 첫 실행 · 설정. **아직 웹 스타일** |
| `MacSidebar.dc.html` | 공용 사이드바 (네이티브). 1·2 화면엔 아직 안 붙음 |
| `01-Gallery.dc.html` `02-Editor.dc.html` `Sidebar.dc.html` `Onboarding.dc.html` `Settings.dc.html` | v1. 웹 같다는 이유로 버린 버전. 비교용 |

브라우저로 열면 캔버스가 보인다. `support.js` 가 같은 폴더에 있어야 한다.

## 여기서 가져갈 것

- 화면 구조와 흐름: 갤러리(사진 앱식 그리드 + 오른쪽 정보 패널 + 아래 상태줄) → 편집안(QuickTime식 재생 막대, Keynote식 장면 목록, 메시지식 채팅)
- **문구.** 전문 용어 없이 잘 써져 있다. "말소리 잘 들려요", "자막 만들기 → 화면 잡는 중 → 영상 만들기",
  "아이폰으로 찍으면 여기 자동으로 들어와요", 실패는 채팅 안에서 다음 행동 버튼과 함께
- 상태 설계: 빈 상태 · 가져오는 중 · 만드는 중 · 멈춤 · 실패

## 가져가지 말 것

- HTML/CSS 치수를 그대로 옮기지 않는다. SwiftUI 표준 컨트롤과 여백을 쓴다
- 3·4 화면의 웹 스타일
- 1100×700 최소 크기는 Claude Design 이 한 번도 확인하지 않았다
