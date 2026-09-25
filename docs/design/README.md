# 화면 디자인

확정된 화면은 `Madi/UI/` 의 SwiftUI 뷰 자체다 (`AGENTS.md §1-10`).
이 폴더에는 **그 뷰를 찍은 그림**과 **사람에게 물어볼 것**만 둔다.

| | |
|---|---|
| `screens/` | 화면별 스크린샷. `<화면>-<상태>-<가로>x<세로>.png` |
| `decisions.md` | 무엇을 시스템 기본값으로 뒀는지 · 추측한 것 · 물어볼 것 |

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
