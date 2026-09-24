# 디자인 흐름

디자인은 **AI(Claude Code)가 SwiftUI 로 직접** 한다. Claude Design 은 쓰지 않는다.
Claude Design 으로 먼저 만든 시안은 `design/claude-design/` 에 참고 자료로 남아 있다.

```
design/claude-design/*.html (참고)
        ↓
디자인 AI  →  Madi/UI/**  SwiftUI 뷰 + #Preview (샘플 데이터, 로직 없음)
              Madi/UI/Tokens.swift  색 · 간격 · 타이포
              Madi/UI/Copy.swift    모든 문구
              docs/design/screens/  화면별 #Preview 스크린샷
        ↓
사람이 확인 → 확정된 뷰가 곧 정답 (§1-10)
        ↓
개발 AI  →  같은 뷰에 실제 데이터와 동작을 연결
```

## 브랜치 분리

개발 AI 가 `rebuild` 에서 1단계를 하고 있다. 같은 폴더에서 두 AI 가 동시에 git 을 만지면 부딪힌다.
**디자인 AI 는 worktree 에서 한다.**

```bash
cd /Users/kimeunjoong/orca/madi
git worktree add ../madi-design -b design rebuild
# 디자인 AI 는 /Users/kimeunjoong/orca/madi-design 에서 작업
```

디자인 AI 는 `Madi/UI/**` 와 `docs/design/**` 만 만진다. 개발 AI 는 `Madi/UI/**` 를 만지지 않는다.
겹치는 파일이 없으므로 나중에 `design` 을 `rebuild` 로 합칠 때 충돌이 거의 없다.

프롬프트: `docs/prompts/design-ai.md`
