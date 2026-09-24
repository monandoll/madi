# 디자인 흐름

디자인은 **Claude Design** 으로 한다. 프롬프트는 `docs/prompts/claude-design.md`.

```
Claude Design  →  design/*.html (시안, 읽기 전용)
                      ↓
개발            →  Madi/UI/Tokens.swift  (색 · 간격 · 타이포 추출)
                   Madi/UI/Copy.swift    (모든 문구. 하드코딩 금지)
                   SwiftUI 구현 — 시안을 픽셀 단위로 따른다
```

## 규칙

- `design/` 은 **읽기 전용**이다. 개발이 임의로 컴포넌트를 "개선"하지 않는다.
  시안과 다르게 해야 할 이유가 생기면 고치지 말고 물어본다 (전작 관습을 잇는다).
- **영상 자막 스타일은 디자인 대상이 아니다.** `AGENTS.md §9` 의 실측표는
  크리에이터 실제 영상을 픽셀로 재서 나온 사실이다. 앱 UI 토큰과 섞지 않는다.
- 문구는 `Copy.swift` 한 파일에 모은다. `AGENTS.md §14`.

## 전작 참고

전작도 Claude Design 으로 시안을 만들었다. 색 토큰과 화면 구성은 참고 가치가 있다.

```
git show legacy/v0.2:CLAUDE.md                        # 디자인 토큰 목록
git show legacy/v0.2:design/v2/Desktop.dc.html > /tmp/legacy-desktop.html
git show legacy/v0.2:design/v2/Mobile.dc.html  > /tmp/legacy-mobile.html
git show legacy/v0.2:design/Setup.dc.html      > /tmp/legacy-setup.html
```

단 전작은 웹(브라우저) 기준이었다. 이번은 macOS 네이티브라 사이드바·툴바·여백 관습이 다르다.
