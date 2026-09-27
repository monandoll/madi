# Stage 6 — 채팅 수정 · 장면 카드 UI · 배포

## 상태 — 진행 중 (2026-09-27 시작)

`AGENTS.md §12-6`. 5단계 통과(`stage-5`, 2026-09-27, CI 녹색) 뒤에 시작한다.

```
- SwiftUI 편집안 · 장면 카드 · 채팅
- 엔타이틀먼트, .dmg, Sparkle
통과: 크리에이터가 혼자 3편을 만들고 각 편 10분 이내.
      깨끗한 Mac 에서 .dmg 드래그 → 아이콘 클릭 → 사용까지 터미널 0회
```

## 경계 — 화면은 디자인, 개발은 그 밖 (2026-09-27 사용자 지시)

- **`Madi/UI/ViewData.swift` 가 약속이다.** 개발은 `Madi/UI/**` 를 건드리지 않는다
- 개발은 UI 밖에 **엔진 → ViewData 로 바꾸는 층**을 만든다. ViewData 를 바꿔야 하면 고치지 않고 목록에 적는다
- 대응표 · 화면이 없는 엔진 상태 · 변경 요청: `docs/design/viewdata-map.md` — **디자인에 넘기는 목록**
- 화면과 상관없는 것(채팅 수정 · `.dmg` · Sparkle · 서명)은 같이 진행한다

## 작업 단위

| # | 단위 | 들어가는 곳 | 끝났다는 증거 |
|---|---|---|---|
| 1 | **design 합치기** ✅ | — | `0b8fbfc` 빌드 · 테스트 185개 |
| 2 | **대응표** ✅ | `docs/design/viewdata-map.md` | 칸마다 출처 · 화면 없는 상태 11 · 변경 요청 7 |
| 3 | **서명 · 공증 · `.dmg`** — Developer ID · Hardened Runtime · 엔타이틀먼트 · notarytool · stapler ✅ 공증 앞까지 (자격 증명 대기) | `scripts/` · `project.yml` | 공증된 `.dmg` 를 다른 계정(또는 격리 속성 붙인 채)에서 열어 Gatekeeper 통과 |
| 4 | **Sparkle** — 업데이트 확인 · EdDSA 서명 · appcast (GitHub Releases) ✅ 첫 릴리스 전까지 | `Madi/App/` · `scripts/` | 옛 판이 새 판을 찾아 설치 |
| 5 | **채팅 수정 (엔진)** — `chat` 저장소 · 수정 턴(`origin chat` · `revisionOf`) → 렌더 → 검사 · "앞으로도 이렇게 할까요?" → 사용자 규칙 ✅ 가짜 턴 (실제 CLI 는 아래) | `Madi/Agent/` · `Madi/Store/` | 가짜 CLI 테스트 · 실제 CLI 수정 1회 |
| 6 | **바꾸는 층** — DB → ViewData (값을 내는 쪽). 행동 받기는 요청 ⑦ 결정 뒤 | `Madi/App/Bridge/` | 테스트: DB 상태마다 ViewData |
| 7 | **UI 밖 부품** — 썸네일 한 장 · 렌더 진행률 · "봤다" · 스튜디오 이름 · 내보내기(사진 앱 · Mac) · 보관 기간 · CLI 설치 · 로그인 대행 | 여러 곳 | 각자 테스트 |
| 8 | **판정** — 크리에이터 3편 · 깨끗한 Mac | — | 사람이 한다 |

## 결정

- **서명 · 공증 — 있는 Developer ID 로 (2026-09-27).** 이 Mac 에 `Developer ID Application: eunjoong kim (64YK8W88M5)`
  (2031년까지)이 이미 있다. `§2` 는 "계정은 판매 시점에, 그전엔 우클릭 → 열기" 였는데
  **macOS 15 부터 우클릭 → 열기가 막혀** 시스템 설정 > 개인정보 보호에서 따로 허용해야 한다 — `§12-6` "터미널 0회" 와
  크리에이터 부담을 생각해 지금 서명 · 공증한다. 공증 자격 증명은 사용자가 한 번 저장한다 (`notarytool store-credentials`).
  멤버십이 유효해야 공증이 된다. `§2` 문장을 고친다
- **Sparkle 업데이트 — GitHub Releases (2026-09-27).** 레포 `monandoll/madi` 가 공개라 릴리스에 `.dmg` 와 `appcast.xml` 을 올린다

### 4번 — Sparkle (2026-09-27)

- Sparkle **2.10.0** (SwiftPM, 판 고정). 하루 한 번 자동 확인 (`SUEnableAutomaticChecks` · 86400초)
- appcast: `https://github.com/monandoll/madi/releases/latest/download/appcast.xml`
- **업데이트 서명 키(EdDSA)** — 공개 키는 Info.plist (`project.yml`), **비밀 키는 이 Mac 로그인 키체인(계정 `madi`)에만 있다.**
  이 키를 잃으면 이미 설치된 앱에 업데이트를 보낼 수 없다 — 백업이 필요하다 (`generate_keys --account madi -x <파일>`)
- `scripts/release.sh`: Sparkle 안쪽(XPC · `Updater.app` · `Autoupdate`)을 깊은 것부터 서명 → 공증 뒤
  `generate_appcast`(도구 위치 `MADI_SPARKLE_BIN`, Sparkle 배포본 `bin/`)로 appcast → `--publish` 일 때만 GitHub 릴리스
- 메뉴 "업데이트 확인…" 은 문구 키 `checkForUpdates` 를 디자인이 채운 뒤 붙인다 (`copy-keys.md`)
- 확인: 서명한 앱(Sparkle 포함)이 Hardened Runtime 에서 켜진다. **옛 판 → 새 판 설치 확인은 첫 릴리스 뒤**

## 미뤄 둔 결정

| # | 결정 | 닿는 단위 |
|---|---|---|
| ① | `RootView` 행동 입구 (요청 ⑦) — 디자인 쪽 | 6 |
| ② | CLI 설치를 어떻게 대행하나 — 앱이 공식 설치 스크립트를 부른다 / Homebrew / 안내만 | 7 |
