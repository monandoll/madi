# 화면 디자인

확정된 화면은 `Madi/UI/` 의 SwiftUI 뷰 자체다 (`AGENTS.md §1-10`).
이 폴더에는 **그 뷰를 찍은 그림**과 **사람에게 물어볼 것**만 둔다.

| | |
|---|---|
| `screens/` | 화면별 스크린샷. `<화면>-<상태>-<가로>x<세로>.png` |
| `decisions.md` | 무엇을 시스템 기본값으로 뒀는지 · 추측한 것 · 물어볼 것 |

## 화면 목록

창 화면은 **1440×900 · 1100×700** 두 크기로 있고(파일명 끝), 첫 실행 창은 720×540,
설정은 540×580, 내보내기 시트는 460×360 한 장씩이다.

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
| `onboarding-ready` | 준비됐어요. **지금부터 찍는 영상이 들어온다**는 한 줄 |
| `onboarding-ready-slow` | 같은 화면 + Intel Mac 이면 "만드는 데 더 오래 걸려요" (`§17`) |

### 갤러리

| 그림 | 무엇 |
|---|---|
| `gallery-loaded` | 정상. 하나 골라 정보 패널이 열린 상태 |
| `gallery-empty` | 빈 상태. "아이폰으로 찍으면 여기 자동으로 들어와요" |
| `gallery-importing` | iCloud에서 가져오는 중 (아래 상태줄에 진행) |
| `gallery-loading` | 불러오는 중 |
| `gallery-no-access` | 사진 접근 없음. **오류가 아니다** — 다음 행동을 준다 |
| `gallery-hidden` | 목록에서 숨긴 뒤 상태줄 알림 + 되돌리기 |
| `gallery-no-results` | 찾는 게 없을 때. **왜 없는지**(거르개 때문인지)를 말하고 푸는 버튼을 준다 |
| `gallery-import-states` | 원본 받는 중(진행률) · 받기 실패(흐린 칸 + 노란 표시, 정보 패널에 `다시 가져오기`) |
| `gallery-preparing` | 첫 실행 직후 편집 준비 — 사이드바 아래 조용한 한 줄 + 진행 막대 |
| `gallery-prep-stopped` | 편집 준비가 멈춤 (저장 공간). 노란 표시 + 이유 |

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
| `plan-single-scene` | 5초짜리라 장면이 하나뿐인 편집안. **막지 않는다** |
| `plan-too-long` | 아직 못 다루는 길이 (롱폼은 `§16` 범위 밖). "아직" 이라고 말한다 |
| `plan-no-ai` | AI 연결 안 됨. 한 줄만 |
| `plan-logged-out` | 설치는 됐는데 로그인이 풀림 — "연결하기" 가 아니라 "로그인하기" |
| `plan-first-run` | 첫 실행 직후 — 준비 단계 맨 앞에 `영상 받기` · `편집 준비`, 채팅에 "받아 뒀어요" |
| `plan-draft-failed` | AI 가 초안을 못 짬 (구독 한도). 편집안 없이 멈춘 자리 + 다음 행동 |
| `plan-analyze-failed` | 영상을 살펴보다 멈춤. 다시 해 보기 |
| `plan-gave-up` | 두 번 다듬어도 기준 미달 — **붉은 표시는 여기뿐**. 장면 목록은 그대로 둔다 |
| `plan-soft-note` | 올려도 되는데 한 가지 남음 — 채팅 한 줄 |
| `plan-gate-notice` | 원본 한계 (인물이 작게 찍힘) — 결과는 나왔고 다음 촬영 요령 한 줄 |
| `plan-ask-remember` | 채팅 수정 뒤 "앞으로도 이렇게 할까요?" 한 번 (`§10`) |
| `plan-versions` | 편집안 고르기 (팝오버 내용만, 300×200) |

### 결과물

| 그림 | 무엇 |
|---|---|
| `results-compare` | 이전 버전과 나란히 + 달라진 점 |
| `results-single` | 첫 결과물 (견줄 것이 없음) |
| `results-export-sheet` | 내보내기 — "어디로 보낼까요?" (460×360) |
| `results-export-failed` | 내보내다 막힘. 붉은색 없이 다음 행동 두 개 |
| `results-trash` | 휴지통으로 옮길까요 + "사진 앱으로 내보낸 건 그대로 있어요" |
| `results-many` | 결과물이 쌓였을 때 (31개 · 11개 묶음) |
| `results-notice` | 원본 한계 안내가 붙은 결과물 — 줄과 비교 화면에 전구 한 줄 |
| `results-empty` · `results-loading` | 빈 상태 · 불러오는 중 |

### 만드는 중

| 그림 | 무엇 |
|---|---|
| `making-busy` | 도는 것 · 기다리는 것 · 멈춘 것 · 오늘 다 만든 것 |
| `making-empty` | 만드는 게 없을 때 |

### 설정 (540×580, 탭 둘)

| 그림 | 무엇 |
|---|---|
| `settings-connected` | 일반 탭 — AI 연결 · 스튜디오 · 촬영본 보관 |
| `settings-disconnected` | AI 연결 안 됨 · 사진 접근 없음 |
| `settings-slow-logged-out` | 로그인이 풀림 + Intel Mac 한 줄 |
| `settings-loading` | 연결 확인 중 |
| `settings-look` | **자막 모양 탭** (`§9`) — 미리보기 · 글꼴 · 굵기 · 기울임 · 색 견본. 크기 · 위치 칸은 없다 |
| `settings-look-font-missing` | 쓰던 글꼴이 지워짐 — 조용히 바꾸지 않고 이유를 말한다 |

### 막힌 화면을 볼 때 보는 것

`plan-stuck` · `plan-not-sent` · `plan-draft-failed` · `plan-analyze-failed` · `results-export-failed` ·
`gallery-import-states` · `gallery-prep-stopped` · `making-busy`(멈춘 것)은 같은 규칙으로 그렸다.
**이유를 사람 말로 적고, 다음 행동 버튼이 같이 있고, 노란 표시다** (`AGENTS.md §1-6`).
붉은 표시는 **`plan-gave-up` 하나뿐**이다 — 두 번 다듬어도 보여 줄 결과가 없어서 다시 해도 안 되는 경우.

## 앱 아이콘

`docs/design/icon/app-icon-1024.png`. 세로(9:16) 영상 한 편이 길이가 다른 **마디 셋**으로 나뉜 모양 —
이 앱이 하는 일(촬영본을 장면으로 나눠 숏폼을 만든다) 그대로다. 바탕은 앱 강조색 초록.
다시 그리려면:

```
swiftc -O -o /tmp/make-icon docs/design/icon/make-icon.swift && /tmp/make-icon
```

`Madi/UI/Assets.xcassets/AppIcon.appiconset` 에 10장(16~1024)을 쓴다. 앱 타깃은
`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 으로 이걸 쓴다.


## 스크린샷 다시 뽑기

```
xcodebuild -scheme MadiUIShots -configuration Debug build
$(xcodebuild -scheme MadiUIShots -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/madi-ui-shots docs/design/screens
```

한 화면만 다시 뜨려면 이름 앞부분을 준다 (전부 뜨면 수 분 걸린다):

```
MADI_SHOTS_ONLY=plan-gave-up madi-ui-shots docs/design/screens
```

줄마다 어느 길로 찍었는지(`← 실제 창` / `← 뷰 그리기`) 찍힌다. 도중에 죽어도 거기까지는 남는다.

모든 화면을 **1440×900 과 1100×700** 두 크기로 찍는다. 1100×700 은 창 최소 크기다
(Claude Design 시안은 이 크기를 한 번도 확인하지 않았다).

찍는 방식은 `Madi/UI/Snapshot/main.swift` 에 있다. Xcode 프리뷰 캔버스는 파일로 뽑을 방법이
없어서, 같은 뷰를 **진짜 `NSWindow` 에 띄워** 그 창을 뜬다. 그래서 그림에 나오는 툴바 ·
사이드바 · 인스펙터는 실제 AppKit 이 그린 것이다.

### 다른 창은 따로 뜬다

시트 · 팝오버는 AppKit 에서 **부모 창과 다른 창**이라 창을 떠도 안 따라온다.
그래서 내용만 따로 뜬다 — `results-export-sheet`(460×360) · `plan-versions`(300×200).
실제로는 각각 결과물 화면 위 시트, 툴바 `편집안 2 ⌄` 아래 팝오버로 뜬다.

### 그림에서 실물과 다른 점

**화면 기록 권한이 있으면** 창을 그대로 뜨므로 재질 · 반투명이 실물과 같다. 남는 차이는 하나다.

- **창이 비활성 상태로 찍힌다.** macOS 14 는 사용자가 띄우지 않은 앱을 앞으로 올려주지 않는다.
  그래서 **툴바 버튼과 제목이 회색**이다 — 실제로 앱을 쓰면 `만들기` 는 강조색이다.
  본문(인스펙터 버튼 · 선택 표시)은 tint 를 그대로 쓰므로 색이 맞다

**권한이 없으면** 뷰 계층을 직접 그린다. 그 경우 그림 아래에 **한 줄로 그렇게 적힌다.**
- 사이드바 · 툴바의 재질이 단색으로 나온다
- 툴바 세그먼트에서 고른 칸의 글자가 빠진다

권한 주기: `madi-ui-shots --권한` 을 한 번 실행하고 터미널을 다시 연다.
