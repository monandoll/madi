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

### 그림에서 실물과 다른 점 (캡처의 한계)

화면 녹화 권한 없이 창을 뜨려면 뷰 계층을 직접 그려야 하는데, 그 경로로는 안 따라오는 게 있다.

- **사이드바 · 툴바의 반투명 재질이 단색으로 나온다.** 실제 앱에서는 뒤가 살짝 비친다
- **툴바 세그먼트에서 고른 칸의 글자가 안 나온다.** 실제로는 "전체" 가 보인다
- **사이드바에서 고른 줄의 강조 표시가 약하게 나온다**

배치 · 크기 · 문구를 보는 데는 문제가 없다. 색과 재질을 판단할 때만 실물로 본다.
