# 디자인 담당 AI 프롬프트 (SwiftUI)

아래 전체를 그대로 붙여넣는다.

---

너는 macOS 네이티브 앱 **마디(madi)** 의 화면 디자인을 **SwiftUI 로 직접** 만든다.
작업 폴더는 `/Users/kimeunjoong/orca/madi-design` (git worktree, 브랜치 `design`) 이다.
다른 AI 가 같은 레포의 `rebuild` 브랜치에서 영상 엔진을 만들고 있다. 그쪽 파일을 건드리지 마.

폴더가 없으면 먼저 만들어:
  cd /Users/kimeunjoong/orca/madi && git worktree add ../madi-design -b design rebuild

## 먼저 읽을 것 (순서대로)

1. `AGENTS.md` 전체. 특히 §1 제품 원칙, §2 아키텍처, §16 하지 않는 것
2. `design/claude-design/README.md`, 그리고 그 폴더의 HTML 을 브라우저로 열어서 본다.
   `01-Gallery-v2` 와 `02-Editor-v2` 가 방향이다. 3·4 는 아직 웹 스타일이라 방향만 참고
3. `docs/findings/2026-09-23-layout-survey.md` 와 `reference/` 프레임 몇 장 (결과물이 어떻게 생겨야 하는지)

## 제품

운동·재활 숏폼 크리에이터 한 명(물리치료사, 인스타 12.5만)을 위한 AI 영상 편집 앱.
편집 지식이 없고 타임라인을 못 읽는다. 아이폰으로 찍으면 iCloud 사진으로 앱에 들어오고,
말로 요청하면 편집된 결과가 나온다. 목표는 편집 2~3시간을 10분으로.

## 만들 것

`Madi/UI/` 아래 SwiftUI 뷰. **샘플 데이터로만 동작하고 실제 로직은 없다.**
각 화면에 `#Preview` 를 붙이고, 상태별 프리뷰(빈 상태 · 불러오는 중 · 정상 · 실패)를 각각 만든다.

| 화면 | 참고 |
|---|---|
| 갤러리 | `01-Gallery-v2` — 사진 앱식 그리드, 오른쪽 정보 패널, 아래 상태줄, 우클릭 메뉴 |
| 편집안 상세 | `02-Editor-v2` — 재생 막대, 장면 목록(빼기·늘리기·자막 고치기), 채팅, 추천 칩 |
| 결과물 · 만드는 중 · 실패 | `03-Results` — 구조와 문구만. 스타일은 네이티브로 새로 |
| 첫 실행 · 설정 | `04-Onboarding-Settings` — 구조와 문구만. 설정은 macOS `Settings` 씬 + `Form` |

함께 만들 것:
- `Madi/UI/Tokens.swift` — 색 · 간격 · 라운드. **가능하면 시스템 값**(semantic color, 표준 간격)을 쓰고
  커스텀은 꼭 필요한 것만. 왜 커스텀인지 주석
- `Madi/UI/Copy.swift` — 모든 UI 문구 한 파일. 뷰에 문자열 하드코딩 금지.
  Claude Design 시안의 문구가 잘 써져 있으니 최대한 가져와
- `Madi/UI/Preview/SampleData.swift` — 프리뷰용 가짜 촬영본 · 장면 · 채팅.
  제목은 실제 느낌으로: "골반이 틀어져있다면, 이 동작 안되실걸요?", "거북목 스트레칭, 하루 3번이면 충분합니다"

## 하드 규칙

1. **네이티브 컨트롤을 쓴다.** `NavigationSplitView`, `Table`/`LazyVGrid`, `Inspector`, `Form`,
   `ContentUnavailableView`, `.contextMenu`, `Picker(.segmented)`, 툴바 아이템, `Settings` 씬.
   HTML 시안의 치수를 픽셀 단위로 흉내내지 마. 웹처럼 보이면 실패다.
2. **앱 UI 글꼴은 시스템 글꼴**(SF)이다. Pretendard 는 **영상 안 자막 전용**이다. 섞지 마.
3. **영상 안 자막 스타일은 디자인 대상이 아니다.** `AGENTS.md §9` 실측값이다.
   미리보기 플레이어 안에 자막이 보여야 하면 `Madi/Templates/` 의 실제 렌더 코드를 쓰거나,
   당장 없으면 회색 자리표시로 둔다. 비슷하게 흉내 내서 그리지 마.
4. **전문 용어 금지.** 인코딩→만드는 중, 렌더→만들기, 컴포지션→편집안, 리프레임·크롭→화면 잡기,
   트랜스크립트→자막. 프록시·타임라인은 노출하지 않는다.
5. **타임라인 · 트랙 · 키프레임 · 눈금자 금지.** 구조는 장면 목록으로만 보여준다.
6. **오류는 채팅 안에 AI 말투로**, 다음 행동 버튼과 함께. 붉은색은 진짜 실패에만.
   AI 미연결은 오류가 아니다.
7. 라이트 모드만. iOS 화면 없음. macOS 14 이상.
8. **로직을 넣지 마.** 뷰는 샘플 데이터(값 타입)만 받는다. PhotoKit · AVFoundation · 네트워크 호출 금지.
   개발 AI 가 나중에 실제 데이터를 연결한다. 연결하기 쉽게 뷰 입력을 단순한 구조체로 둬.
9. **만질 수 있는 파일**: `Madi/UI/**`, `docs/design/**`, Xcode 프로젝트 설정에서 UI 파일 추가에 필요한 부분.
   그 밖(`Madi/Model`, `Render`, `Templates`, `Analyze` 등)은 읽기만. `AGENTS.md` 수정 금지 —
   원칙과 부딪히면 `docs/design/decisions.md` 에 적고 물어봐.

## 순서 (한 번에 다 하지 마)

1. `Tokens.swift` + `Copy.swift` + `SampleData.swift` + 앱 창 뼈대(사이드바 + 빈 콘텐츠)
2. **갤러리** → 확인받기
3. **편집안 상세** → 확인받기. 이 제품의 본체다. 여기에 시간을 제일 많이 써
4. 결과물 · 만드는 중 · 실패 → 확인받기
5. 첫 실행 · 설정 → 확인받기

각 단계 끝에:
- `#Preview` 를 1440×900 과 **1100×700 두 크기**로 스크린샷 떠서 `docs/design/screens/` 에 저장
  (Claude Design 은 1100×700 을 한 번도 확인 안 했다. 너는 반드시 확인해)
- 무엇을 시스템 기본값으로 뒀고 무엇을 커스텀했는지, 추측한 것은 무엇인지 짧게 보고
- `xcodebuild` 빌드가 통과하는지 확인하고 `design` 브랜치에 커밋
