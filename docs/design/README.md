# 화면 디자인

확정된 화면은 `Madi/UI/` 의 SwiftUI 뷰 자체다 (`AGENTS.md §1-10`).
이 폴더에는 **그 뷰를 찍은 그림**과 **사람에게 물어볼 것**만 둔다.

| | |
|---|---|
| `screens/` | 화면별 스크린샷. `<화면>-<상태>-<가로>x<세로>.png` |
| `decisions.md` | 무엇을 시스템 기본값으로 뒀는지 · 추측한 것 · 물어볼 것 |

## 화면 목록

57장. 창 화면은 **1440×900 · 1100×700** 두 크기로 있고(파일명 끝), 첫 실행 창은 720×540,
설정은 520×520, 내보내기 시트는 460×360 한 장씩이다.

읽는 순서는 사람이 쓰는 순서와 같다 — 첫 실행 → 갤러리 → 편집안 → 결과물 → 만드는 중.

### 첫 실행 (720×540)

| 그림 | 무엇 |
|---|---|
| `onboarding-photos` | 1/3 사진. 권한 창이 뜨기 전에 무엇을 읽고 안 건드리는지 먼저 말한다 |
| `onboarding-photos-denied` | 허용 안 함. **막히지 않는다** — Mac에서 직접 넣는 길을 준다 |
| `onboarding-ai` | 2/3 AI 고르기. 연결 전에는 `계속` 이 잠긴다 (`§10`) |
| `onboarding-ai-waiting` | 브라우저에서 로그인하는 중 |
| `onboarding-ai-connected` | 연결됨 · 계정 표시 |
| `onboarding-studio` | 3/3 이름. 어디에 쓰이는지 바로 보여준다 |
| `onboarding-ready` | 준비됐어요 |

### 갤러리

| 그림 | 무엇 |
|---|---|
| `gallery-loaded` | 정상. 하나 골라 정보 패널이 열린 상태 |
| `gallery-empty` | 빈 상태. "아이폰으로 찍으면 여기 자동으로 들어와요" |
| `gallery-importing` | iCloud에서 가져오는 중 (아래 상태줄에 진행) |
| `gallery-loading` | 불러오는 중 |
| `gallery-no-access` | 사진 접근 없음. **오류가 아니다** — 다음 행동을 준다 |
| `gallery-hidden` | 목록에서 숨긴 뒤 상태줄 알림 + 되돌리기 |

### 편집안 (이 제품의 본체)

| 그림 | 무엇 |
|---|---|
| `plan-ready` | 편집안 나옴. 장면 4번 고른 상태 (고른 줄만 펼쳐진다) |
| `plan-editing-caption` | 줄 안에서 자막 고치는 중 (본문 + 영문 보조) |
| `plan-preparing` | AI 가 짜는 중. 단계 목록 · 멈추기 · 칩 잠김 |
| `plan-making` | 영상 만드는 중. **화면을 떠나지 않는다** — 목록은 읽기 전용 |
| `plan-made` | 다 만듦. 결과물이 대화에 카드로 붙는다 |
| `plan-stuck` | 소리가 없어 자막을 못 만든 경우. 다음 행동 3개 |
| `plan-unsure-reframe` | 화면 잡기를 **확인 못 한** 경우 (`§8` 판정 불가) |
| `plan-not-sent` | 말을 못 보낸 경우. 쓴 말은 그대로 두고 다시 보내기 |
| `plan-no-ai` | AI 연결 안 됨. 한 줄만 |

### 결과물

| 그림 | 무엇 |
|---|---|
| `results-compare` | 이전 버전과 나란히 + 달라진 점 |
| `results-single` | 첫 결과물 (견줄 것이 없음) |
| `results-export-sheet` | 내보내기 — "어디로 보낼까요?" (460×360) |
| `results-export-failed` | 내보내다 막힘. 붉은색 없이 다음 행동 두 개 |
| `results-trash` | 휴지통으로 옮길까요 + "사진 앱으로 내보낸 건 그대로 있어요" |
| `results-empty` · `results-loading` | 빈 상태 · 불러오는 중 |

### 만드는 중

| 그림 | 무엇 |
|---|---|
| `making-busy` | 도는 것 · 기다리는 것 · 멈춘 것 · 오늘 다 만든 것 |
| `making-empty` | 만드는 게 없을 때 |

### 설정 (520×520)

| 그림 | 무엇 |
|---|---|
| `settings-connected` | AI 연결 · 스튜디오 · 촬영본 보관 |
| `settings-disconnected` | AI 연결 안 됨 · 사진 접근 없음 |
| `settings-loading` | 연결 확인 중 |

### 막힌 화면을 볼 때 보는 것

`plan-stuck` · `plan-not-sent` · `results-export-failed` · `making-busy`(멈춘 것) 넷은
같은 규칙으로 그렸다. **붉은색이 없고, 이유를 사람 말로 적고, 다음 행동 버튼이 같이 있다**
(`AGENTS.md §1-6`). 붉은색은 진짜 실패에만 쓰는데 지금까지 나온 상황 중 해당되는 게 없다.


## 스크린샷 다시 뽑기

```
xcodebuild -scheme MadiUIShots -configuration Debug build
$(xcodebuild -scheme MadiUIShots -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/madi-ui-shots docs/design/screens
```

모든 화면을 **1440×900 과 1100×700** 두 크기로 찍는다. 1100×700 은 창 최소 크기다
(Claude Design 시안은 이 크기를 한 번도 확인하지 않았다).

찍는 방식은 `Madi/UI/Snapshot/main.swift` 에 있다. Xcode 프리뷰 캔버스는 파일로 뽑을 방법이
없어서, 같은 뷰를 **진짜 `NSWindow` 에 띄워** 그 창을 뜬다. 그래서 그림에 나오는 툴바 ·
사이드바 · 인스펙터는 실제 AppKit 이 그린 것이다.

### 그림에서 실물과 다른 점

**화면 기록 권한이 있으면** 창을 그대로 뜨므로 재질 · 반투명이 실물과 같다. 남는 차이는 하나다.

- **창이 비활성 상태로 찍힌다.** macOS 14 는 사용자가 띄우지 않은 앱을 앞으로 올려주지 않는다.
  그래서 **툴바 버튼과 제목이 회색**이다 — 실제로 앱을 쓰면 `만들기` 는 강조색이다.
  본문(인스펙터 버튼 · 선택 표시)은 tint 를 그대로 쓰므로 색이 맞다

**권한이 없으면** 뷰 계층을 직접 그린다. 그 경우 그림 아래에 **한 줄로 그렇게 적힌다.**
- 사이드바 · 툴바의 재질이 단색으로 나온다
- 툴바 세그먼트에서 고른 칸의 글자가 빠진다

권한 주기: `madi-ui-shots --권한` 을 한 번 실행하고 터미널을 다시 연다.
