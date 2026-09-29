# ViewData 대응표 — 엔진 → 화면 (6단계, 2026-09-27)

`Madi/UI/ViewData.swift` 가 **약속**이다. 개발은 `Madi/UI/**` 를 건드리지 않는다.
개발은 UI 밖에 **엔진 → ViewData 로 바꾸는 층**을 만든다. ViewData 를 바꿔야 하면 고치지 않고 아래 3절에 적는다.

표시:
- ✅ 엔진에 있다 — 옮겨 담기만 한다
- 🔧 엔진에 재료는 있다 — 바꾸는 층에서 계산한다 (규칙을 같이 적었다)
- 🛠 엔진에 없다 — 개발이 **UI 밖에** 새로 만든다 (6단계 개발 일)
- ❓ 정해야 한다 — 기준이 없다. 누가 정할지 적었다

엔진 쪽 이름: `video` · `digest` · `composition` · `output` · `job` · `event` 는 DB 표 (`Madi/Store/`),
`Composition` 은 `Madi/Model/Composition.swift`.

---

## 1. 칸마다 어디서 오나

### 썸네일 · 촬영본 · 갤러리

| ViewData | 칸 | 출처 | |
|---|---|---|---|
| `Thumbnail` | `fileURL` | 원본 첫 화면 · 결과물 첫 화면 · 장면 첫 화면 한 장. 지금은 다이제스트 격자 시트뿐(`digest.sheetPaths`) | 🛠 한 장짜리 그림을 `~/Library/Caches/madi/thumbs/` 에 뽑는다. `§4` 의 720p 프록시는 아직 없다 |
| `ShotItem` | `id` | `video.id` | ✅ |
| | `title` | 말소리에서 뽑은 제목. 초안이 있으면 `Composition.meta.title`(AI 가 쓴다), 없으면 빈 문자열 | 🔧 초안 전에는 비어 있다 — 디자인 가정(“없으면 날짜”)대로 |
| | `shotAt` | `video.capturedAt`, 없으면 `video.importedAt` | ✅ |
| | `duration` | `video.durationSec` | ✅ |
| | `speech` | `clear · noisy · silent` | ❓ `silent` 은 전사 낱말 수 0 으로 가를 수 있다. **`noisy` 를 가를 측정이 없다** (SNR 을 재지 않는다). 개발이 기준을 정해 보고한다 — 촬영본 전에는 `clear` / `silent` 둘만 나온다 |
| | `isMaking` | 이 영상에 살아 있는 작업(`job` 의 analyze · agent · render · selfEval, queued/running)이 있는가 | 🔧 |
| | `results` | 이 영상 편집안들의 `output` 중 `verdict == shown` | 🔧 |
| `ResultRef` | `id` | `output.id` | ✅ |
| | `platform` | `Composition.meta.platform` (기본 `reels`) | ✅ AI 는 지금 이 칸을 고르지 않는다 — 전부 릴스로 나온다 |
| | `planLabel` | `편집안 N` — 이 영상의 **보이는** 편집안 순번 | 🔧 번호 규칙은 아래 `PlanVersion` |
| | `when` | `output.createdAt` 을 사람 말로 (`오늘 오후 2:40`) | 🔧 |
| | `duration` · `sceneCount` | 편집안에서 | ✅ |
| | `isNew` | 아직 안 본 결과물 | 🛠 "봤다" 를 적는 칸이 없다 — 개발이 만든다 |
| | `exportedNote` | 내보낸 이력 | 🛠 내보내기가 아직 없다 (6단계 개발 일) |
| `ShotGroup` | `title` · `subtitle` | `shotAt` 으로 오늘 · 이번 주 · 지난주 · 그 전 | 🔧 |
| `GalleryState` | `.loading` | DB 를 처음 읽는 동안 | 🔧 |
| | `.empty` | `video` 가 0 행 | ✅ |
| | `.importing(done, total)` | `video.status` 가 `importing` 인 행 수 · 전체 | 🔧 **한 편 안의 진행률은 없다** (iCloud 원본 받기 진행률을 엔진이 들고 있지 않다) |
| | `.noPhotoAccess` | `PHPhotoLibrary.authorizationStatus` | 🔧 `PhotoLibraryWatcher.start()` 가 거절이면 false 를 돌려준다 — 상태로 들고 있지는 않다 |

### 사이드바 · 설정 · 첫 실행

| ViewData | 칸 | 출처 | |
|---|---|---|---|
| `AIConnection` | | `AgentJob.defaultChoice()` — 설정 `madi.agent`, 없으면 연결된 쪽(둘 다면 Claude) | ✅ |
| `StudioStatus` | `studioName` | 설정값 | 🛠 저장 칸이 없다 (`UserDefaults` 키를 만든다). 코드에 박지 않는다 (`§1-7`) |
| | `shotCount` · `resultCount` · `makingCount` | `video` 행 수 · `output(shown)` 수 · 살아 있는 작업이 있는 영상 수 | 🔧 |
| `AISetup` | `.picked` · `.waiting` · `.connected(account)` | `CLILocator.connection` — 설치 · 로그인. `account` 는 Claude 만 준다(`claude auth status` 의 `email`). **Codex 는 계정 주소를 안 준다** | 🔧 / 🛠 로그인 대행(`waiting`)은 개발이 만든다 (`§2` — 앱이 CLI 설치 · 로그인 진입을 대신한다) |
| `PhotoAccess` | | `PHPhotoLibrary.authorizationStatus` | 🔧 |
| `SettingsValues` | `activeAI` | 설정 `madi.agent` | ✅ |
| | `keepDays` | 보관 기간 | 🛠 기간이 지난 **앱 사본** 을 지우는 작업이 없다 |
| | `albumName` | 어느 앨범에서 가져올지 | 🛠 지금은 "첫 실행 뒤 찍은 영상 전부" 를 들인다 — 앨범으로 거르는 길이 없다 |

### 편집안

| ViewData | 칸 | 출처 | |
|---|---|---|---|
| `CaptionSlot` · `SceneRoleKind` | | `Composition.captionSlot` · `Scene.role` — 이름이 같다 | ✅ |
| `SceneCardItem` | `id` · `number` · `role` · `duration` | `Scene.id` · 순서 · `role` · `Scene.duration` | ✅ |
| | `caption` · `moreCaptions` · `secondary` | `Scene.captions` 의 첫 덩어리 / 나머지 / 첫 덩어리의 영문. 자막은 **앱이 전사에서 채운다** (4단계) | ✅ 영문은 문장 번역을 덩어리에 나눈 것이라 한 덩어리만 보면 문장 중간에서 끊긴다 |
| | `thumbnail` | 장면 첫 화면 | 🛠 (썸네일과 같다) |
| | `removedGapAfter` | "이 장면 뒤에 뺀 쉬는 구간" | 🔧 **엔진에 이 개념이 없다.** AI 는 장면만 고른다. 원본에서 이어진 두 장면(`다음.in − 이번.out` > 0)이면 그 차이를 넣는다. 순서를 바꾼 장면 사이는 비운다. 뜻이 맞는지 디자인 확인 필요 |
| `PlanVersion` | 전부 | 이 영상의 `composition` 들 | 🔧 **번호는 사람이 본 판만 센다** — 초안과 채팅 수정(`origin` draft · chat). 되먹임 판(`selfEval`)은 번호를 받지 않고, 보여진 결과물의 편집안이 그 자리를 대신한다 |
| `PlanView` | `sourceDuration` · `targetDuration` | `video.durationSec` · `meta.targetDurationSec` | ✅ |
| | 나머지 | 위에서 | ✅ / 🔧 |
| `PrepareStep` | 제목 · 상태 | 디자인 가정은 **받아적기 → 장면 나누기 → 쉬는 구간 찾기 → 화면 잡기**. 실제 순서는 아래 | ❓ 이름을 맞춰야 한다 |
| | `remaining` | | 🔧 분석은 영상 길이로 어림할 수 있다 (1분 원본 ≈ 2분, Apple Silicon). 모르면 비운다 |
| `MakingProgress` | `fraction` | 렌더 진행률 | 🛠 지금 렌더러는 **0 과 1 만** 알린다 (`AVAssetExportSession.progress` 를 폴링해야 한다) |

**실제 파이프라인 순서** (디자인의 `PrepareStep` 과 맞출 것):

| 엔진 | 걸리는 시간 (1분 원본, Release, Apple Silicon) | 사람 말 후보 |
|---|---|---|
| 원본 받기 (iCloud, "저장 공간 최적화" 면) | 원본 크기 · 인터넷 | 영상 받는 중 |
| (첫 실행 직후만) 편집 준비 — 모델 받기 · 데우기 | 받기 수십 초 · 데우기 ~5분 | 편집 준비 중 |
| 다이제스트 — 전사 · 사람 찾기 · 소리 · 컷 · 시트 | ~2분 (사람 찾기 · 컷이 대부분) | 말 받아적기 · 사람 찾기 |
| AI 초안 | 20~40초 | 장면 나누기 |
| 렌더 (화면 잡기 · 자막 포함) | ~20초 | 영상 만들기 |
| 검사 → (되먹임 → 다시 렌더) 최대 2회 | 되먹임 한 번에 20~30초 + 렌더 | 다시 다듬기 |

"쉬는 구간 찾기" 는 따로 도는 단계가 없다 — AI 가 장면을 고르며 같이 한다.

### 대화

| ViewData | 칸 | 출처 | |
|---|---|---|---|
| `ChatMessage` | `.user` · `.assistant` | 채팅 저장소 | 🛠 **채팅 저장소가 없다.** 지금 AI 가 한 말은 `event(agent.turn.finished).said` 에만 남는다. 6단계에서 `chat` 표를 만든다 |
| | `.userNotSent` | 보내지 못한 말 | 🛠 (채팅 수정과 같이) |
| | `.summary(EditSummary)` | 두 편집안의 차이 | 🔧 길이 · 장면 수 · 바뀐 장면 · 자막 자리를 비교해 줄로 |
| | `.choices` | 다음 행동 | 🔧 상황마다 (3절) |
| | `.result(ResultRef)` | 보여진 결과물 | ✅ |
| | `.typing` | AI 턴이 도는 중 | ✅ `agent.turn.started` ~ `finished` |
| `EditSummary.canUndo` | | 결과물이 없는 편집안인가 | ✅ `output` 이 없으면 제자리에서 고칠 수 있다 (`§5`) |

### 결과물 · 만드는 중

| ViewData | 칸 | 출처 | |
|---|---|---|---|
| `ResultGroup` | | `output(shown)` 을 영상으로 묶는다 | 🔧 |
| `ResultDetail` | `previous` · `changes` | 같은 영상의 바로 앞 **보여진** 결과물과 그 편집안 차이 | 🔧 |
| `ResultsState` | | `output(shown)` 수 | ✅ |
| `ExportTarget` | | 사진 앱 · Mac 에 저장 · AirDrop | 🛠 내보내기가 없다 (6단계 개발 일) |
| `MakingJob` | `.running(progress)` | `job(render, running)` + 렌더 진행률 | 🔧 / 🛠 (진행률) |
| | `.queued(note)` | `job(queued)` | ✅ |
| | `.stopped(reason, actions)` | `job(failed)` + `error` | 🔧 `error` 는 개발자 문장이다 — 사람 말 이유로 옮기는 표가 필요하다 (3절) |
| `DoneItem` | | 오늘 `verdict` 가 `shown` 이 된 결과물 | 🔧 |

---

## 2. 엔진에는 있는데 화면이 없는 상태 — **디자인에 넘기는 목록**

이 상태들은 지금 **엔진이 실제로 들어가는** 상태인데 그릴 자리가 없다.
문구 키가 이미 있는 것은 `copy-keys.md` 에 적혀 있다 (문장은 디자인이 쓴다).

| # | 상태 | 엔진에서 | 언제 · 얼마나 | 문구 키 | 어디에 그릴지 (디자인이 정한다) |
|---|---|---|---|---|---|
| 1 | **편집 준비 중** — 모델 받는 중 · 데우는 중 · 멈춤(인터넷) · 실패 · 공간 부족 | `ModelPreparer.State` · `event(model.*)` | 첫 실행 직후 수 분. 앱 업데이트 뒤 데우기만 다시 | `modelDownloading` · `modelWarming` · `modelDownloadPaused` · `modelDownloadFailed` · `modelDiskFull` · `modelWaitingForVideo` | ViewData 에 칸이 없다 → 3절 요청 ①. 사이드바 푸터 한 줄? |
| 2 | **다시 다듬는 중** (되먹임) | `output.verdict == hidden` + `job(selfEval)` | 초안 렌더 뒤 20초~1분 더. 4단계 판정에서 12편 중 1편 | `reviewChecking` | `PlanState.making` 의 한 단계로 보일 수 있다 — `PrepareStep` 이름 하나 추가면 된다 |
| 3 | **끝내 기준에 못 미침** — 두 번 다듬어도 인물 크기 등 하드 기준 미달, 보여 줄 결과가 없다 | `output.verdict == failed` · `event(review.gaveUp)` | 드물다 (5단계 판정 0회) | `reviewGaveUp` | 편집안은 있는데 결과물이 없다. 채팅 한 줄 + 다음 행동? `PlanState` 에 자리가 없다 → 3절 요청 ② |
| 4 | **보여 주되 아쉬운 점이 남음** — 두 번 다듬어도 길이 · 훅 등이 기준 밖 | `event(review.shown)` 의 `items` | 드물다 | `reviewSoftNote` | 채팅 한 줄 (`ChatMessage.assistant`) |
| 5 | **원본 한계** — 인물이 너무 작게 찍혀 최대로 키워도 모자람. 결과는 보여 준다 | 리포트 `G1 = sourceLimited` | 대용 6편 중 2편(`NOCX` · `fuTj`) | `GateNotice` 키 (`Madi/Review/GateNotice.swift`) | `plan-unsure-reframe`(판정 불가)와 비슷한 자리 + **촬영 조언** 한 줄. 판정 불가와 **다른 상태**다 |
| 6 | **AI 턴 실패** — 구독 한도 · 로그인 만료 · CLI 가 죽음 · 시간 초과 | `job(agent, failed)` · `event(agent.turn.finished).error` | 드물다 | `aiDraftFailed` | `PlanState.preparing` 이 끝나지 않은 채 멈춘다. 채팅 + 다시 하기? → 3절 요청 ② |
| 7 | **AI 설치됨 · 로그인 안 됨** | `AgentConnection.notLoggedIn` | 로그인이 풀렸을 때 | `aiNotLoggedIn` | `AIConnection` 은 `none` 하나뿐 — "설치 안 됨" 과 구별되지 않는다. 다음 행동이 다르다 (설치 vs 로그인) → 3절 요청 ③ |
| 8 | **원본 받기 실패** (iCloud 원본을 못 받음) | `video.status == failed` · `video.error` | 드묾 | 없음 → 키 필요 | 갤러리 칸 하나의 상태. `ShotItem` 에 자리가 없다 → 3절 요청 ④ |
| 9 | **분석 실패** (전사 · 사람 찾기가 죽음) | `job(analyze, failed)` | 드묾 | 없음 → 키 필요 | 편집안 화면에서 `PlanState` 자리가 없다 → 요청 ② 와 같이 |
| 10 | **이 Mac 은 느리다** (Intel) | `MachineArch.current == x86_64` | Intel Mac 첫 실행 | 없음 → 키 필요 (`§17` "이 Mac 에서는 만드는 데 더 오래 걸립니다") | 첫 실행 · 설정? |
| 11 | **말이 없는 촬영본** | 전사 낱말 0 | 대용 세로 10편 중 9편(스톡) | `plan-stuck` 이 그린 상태 | ✅ 그려져 있다 — 엔진 쪽 조건은 "낱말 0" |

---

## 3. ViewData 변경 요청 (개발은 고치지 않는다)

| # | 무엇 | 왜 | 제안 |
|---|---|---|---|
| ① | **편집 준비 상태**를 받을 칸 | 2절 1번. 첫 실행 직후 수 분간 "왜 아무것도 안 되지" 가 된다 | `StudioStatus` 에 `preparing: PrepareStep?` 같은 선택 칸 |
| ② | 편집안 화면의 **멈춘 상태** | 2절 3 · 6 · 9번. 지금 `PlanState` 는 `preparing` 에서 끝나지 않으면 갈 곳이 없다 | `PlanState.stopped(plan: PlanView?, reason: String, actions: [ChatChoice])` — `MakingJob.State.stopped` 와 같은 모양 |
| ③ | AI **설치 안 됨 / 로그인 안 됨** 구별 | 2절 7번. 다음 행동이 다르다 | `AIConnection` 에 `.notLoggedIn(AIConnection)` 또는 사이드바가 `AISetup` 을 받게 |
| ④ | 촬영본 한 칸의 **받기 실패** | 2절 8번 | `ShotItem` 에 `problem: String?` |
| ⑤ | 결과물의 **원본 한계 안내** | 2절 5번. 결과 옆에 촬영 조언을 붙일 자리 | `ResultRef` 에 `notice: String?` (또는 `ResultDetail`) |
| ⑥ | `ShotItem.speech` 의 `noisy` | 1절. 엔진이 가를 측정이 없다 | 촬영본 뒤 기준이 생길 때까지 `noisy` 는 안 나온다 — 그대로 두되 알고 있기 |

### ⑦ — 가장 먼저 필요하다: `RootView` 가 사람의 행동을 밖으로 넘기지 않는다

하위 화면에는 콜백이 다 있다 (`PlanScreen.onMake · onStop · onConnectAI`, `ChatPanel.onSend · onChip · onChoice · onUndo ·
onRetrySend · onOpenResult`, `SceneList.onRemove · onExtend · onShorten · onRestoreGap · onMove`, `PlanVersionList.onPick`,
`SettingsScreen.on…`). 그런데 **`RootView` 가 이어 주지 않는다**:

- `GalleryScreen.onMakeShort` 는 누른 `ShotItem` 을 받지만 버리고 `showsPlan = true` 만 한다 —
  엔진은 **어느 촬영본을 열었는지** 모른다. `plan` 도 하나만 받으므로 바꾸는 층이 그 촬영본의 편집안을 넣어 줄 수 없다
- `PlanScreen` · `ChatPanel` · `SceneList` 의 콜백이 `RootView` 에서 연결되지 않는다 — 채팅 · 만들기 · 멈추기 · 장면 손질이 엔진에 안 닿는다
- `ResultsScreen` 의 내보내기 · 휴지통, `MakingScreen` 의 멈춘 작업 다음 행동도 같다

제안: `RootView` 가 행동 하나를 받는 입구를 둔다 — 예 `var onAction: (UIAction) -> Void`, `UIAction` 은 값 타입
(`.openShot(ShotItem.ID)` · `.send(String)` · `.chip(String)` · `.choice(ChatChoice)` · `.make` · `.stop` · `.pickVersion(PlanVersion.ID)` ·
`.scene(SceneCardItem.ID, SceneAction)` · `.export(ResultRef.ID, ExportTarget)` · `.trash(ResultRef.ID)` …).
**이게 없으면 화면을 앱에 붙여도 보기만 된다.** 디자인 쪽 결정 전까지 개발은 바꾸는 층을 "값을 내는 쪽" 만 만든다.

### 바꾸는 층이 아직 내지 않는 것 (문장이 `Copy.swift` 에 없어서)

`Madi/App/Bridge/ViewDataMapper.swift` 는 문장을 `Copy` 에서 **읽기만** 한다. 아래는 엔진에 줄이 있지만 문장이 없어 화면에 내지 않는다 —
`copy-keys.md` 의 키가 `Copy.swift` 에 생기면 낸다:
- 채팅 선택지 "앞으로도 이렇게 할까요?" (`askRemember` · `rememberYes` · `rememberNo`)
- 채팅 알림 — 수정 실패 (`aiDraftFailed`), 되먹임 끝내 실패 (`reviewGaveUp`), 아쉬운 점 남음 (`reviewSoftNote`), 원본 한계 안내
- 만드는 중 화면의 멈춘 작업 이유 (`job.error` 는 개발자 문장이다)

## 4. 개발이 UI 밖에 만들 것 (6단계 개발 일)

- **바꾸는 층** — DB 를 관측해 위 ViewData 를 내는 곳 (`Madi/App/` 또는 새 폴더, `Madi/UI` 밖)
- 썸네일 한 장 뽑기 · 렌더 진행률 · "봤다" 표시 · 스튜디오 이름 저장
- **채팅 저장소 · 채팅 수정** (`§10` — 수정은 새 편집안 `revisionOf` · origin `chat`, "앞으로도 이렇게 할까요?")
- **내보내기** — 사진 앱 · Mac 에 저장 (AirDrop 은 시스템 공유)
- 보관 기간 지난 **앱 사본** 지우기 · 앨범 거르기
- CLI 설치 · 로그인 대행 (`§2` · `§1-9`)
- `.dmg` · Sparkle · 서명 (계정 · 비용이 드는 것은 결정으로 가져간다)

---

## 5. 디자인 답 (2026-09-28)

위 2 · 3절을 전부 처리했다. **ViewData 바꾼 것은 전부 기본값이 있는 추가다** — 바꾸는 층은
고치지 않아도 빌드된다 (`MadiBridgeTests` 통과). 이름을 바꾼 문구 키만 **폐기 경고**가 난다 (아래 "단계 이름").

### ⑦ 행동 입구 — `UIAction` (`Madi/UI/UIAction.swift`)

`RootView(…, onAction: (UIAction) -> Void)` **하나**로 전부 나간다. 화면별로 묶었다:

```swift
switch action {
case .gallery(.makeShort(let shotID)):   // 그 촬영본의 plan · planMessages 를 넣는다
case .plan(.make) / .plan(.stop) / .plan(.pickVersion(id)) / .plan(.moveScenes(from:to:)) / .plan(.choice(c))
case .scene(let id, .editCaption(let text, let secondary))   // secondary == nil → AI 가 영문을 다시 맞춘다
case .scene(let id, .remove / .extend / .shorten / .restoreGap / .select / .playFromHere)
case .chat(.send(s) / .chip(s) / .choice(c) / .retrySend(s) / .undo / .openResult(id))
case .results(.export(id, target) / .trash(id) / .openPlan(id) / .noticeChoice(c))
case .making(.stop(id) / .cancel(id) / .choice(id, c) / .openResult(id))
case .openSettings
}
```

- `RootView` 가 스스로 하는 것은 **길 찾기뿐**이다 (편집안을 열었는지, 사이드바 칸). 그것도 행동을 **먼저 내보낸 뒤**에 한다
- **편집안을 닫게 하려면 `plan` 을 nil 로** 넣는다 — 편집안 화면은 `plan` 이 있을 때만 선다 (예: 멈춘 편집안의 "다른 촬영본 고르기")
- 모든 값에 **무엇에 대한 일인지** id 가 들어 있다. 화면이 기억하는 선택에 기대지 않는다
- 첫 실행 창 · 설정 창은 앱 창 밖이라 따로 받는다: `OnboardingWindow(onAction: (UIAction.Onboarding) -> Void)`,
  `SettingsScreen(onAction: (UIAction.Settings) -> Void)`. 같은 타입의 가지라 한 곳에서 받아도 된다

### 3절 요청

| # | 답 | 어디 |
|---|---|---|
| ① 편집 준비 | `StudioStatus.preparing: EnginePrep?` — `.downloading(0...1)` · `.warming` · `.paused` · `.failed` · `.diskFull`. 끝나면 **nil** (아무 말도 안 한다) | 사이드바 아래 한 줄 (`gallery-preparing` · `gallery-prep-stopped`) |
| ② 멈춘 편집안 | `PlanState.stopped(plan: PlanView?, reason:, actions:, isFinal: Bool = false)`. 편집안이 있으면 장면 목록은 그대로 두고 요약 자리에 이유를 세운다. **`isFinal` 은 두 번 다듬어도 안 된 경우(`reviewGaveUp`)에만** — 그때만 붉은 표시 | `plan-gave-up` · `plan-draft-failed` · `plan-analyze-failed` |
| ③ 로그인만 안 됨 | `AIConnection.notLoggedIn(AIProduct)` · `AISetup.notLoggedIn(AIProduct)` · `PlanState.notLoggedIn(AIProduct)`. `AIProduct` = `claude` · `codex` | 사이드바 노란 점 + "Claude 로그인 필요", 편집안 `plan-logged-out`, 설정 `settings-slow-logged-out` |
| ④ 받기 실패 | `ShotItem.problem: String?` (+ 새로 `fetchProgress: Double?` — 원본 받는 중, `importFetchingOriginal` 자리) | 갤러리 칸 · 정보 패널 (`gallery-import-states`). `숏폼 만들기` 가 잠기고 `다시 가져오기` 가 선다 |
| ⑤ 원본 한계 안내 | `ResultRef.notice: String?` — **짧은 꼴** `Copy.Gate.tip…` 을 넣는다. 긴 설명(`Copy.Gate.subjectTooSmall` 등)은 채팅 한 줄 | 결과물 줄 · 비교 화면 (`results-notice`), 채팅 (`plan-gate-notice`) |
| ⑥ `noisy` | 그대로 둔다. 기준이 생기기 전까지 `clear` · `silent` 만 나와도 화면은 문제없다 | — |

### 2절 상태 — 어디에 그렸나

| # | 상태 | 그린 곳 |
|---|---|---|
| 1 | 편집 준비 | 사이드바 아래 한 줄 (①). 영상이 먼저 들어오면 편집안 채팅에 `Copy.Prep.modelWaitingForVideo`, 준비 단계 목록 맨 앞에 `편집 준비` (`plan-first-run`) |
| 2 | 다시 다듬는 중 | `MakingProgress.steps` 의 두 번째 단계 `살펴보고 다듬기` (아래 "단계 이름") |
| 3 | 끝내 기준 미달 | `PlanState.stopped(…, isFinal: true)` (②) — **붉은색은 여기뿐** |
| 4 | 아쉬운 점 남음 | 채팅 한 줄 `Copy.Review.reviewSoftNote(…)` (`plan-soft-note`) |
| 5 | 원본 한계 | 결과물 줄 · 비교 화면에 전구 한 줄 (⑤) + 채팅. **판정 불가(`plan-unsure-reframe`)와 다른 상태**다 — 이건 다 쟀고 원본이 모자란 것 |
| 6 | AI 턴 실패 | `PlanState.stopped` (②) + 채팅 `Copy.AI.aiDraftFailed` · 이유 한 줄 (`reasonLimit` · `reasonLoggedOut`) |
| 7 | 로그인 안 됨 | ③ |
| 8 | 원본 받기 실패 | ④ |
| 9 | 분석 실패 | `PlanState.stopped` (②) + `Copy.AI.analyzeFailed` (새 키) |
| 10 | 느린 Mac | 첫 실행 `준비됐어요` 에 한 줄 (`OnboardingState.isSlowMac`), 설정 일반 탭 맨 아래 (`SettingsValues.isSlowMac`) — `Copy.Machine.slowMac` |
| 11 | 말 없는 촬영본 | 원래 그려져 있다 (`plan-stuck`) |

### 단계 이름 — 엔진 순서에 맞췄다

`PrepareStep` 은 **엔진이 실제로 도는 순서**로 쓴다. "쉬는 구간 찾기" · "화면 잡기" 는 짜는 단계에서 뺐다
(쉬는 구간은 AI 가 장면을 고르며 같이 하고, 화면 잡기 · 자막은 렌더 한 번에 된다).

| 언제 | 단계 (`Copy.Plan…`) |
|---|---|
| 편집안 짜는 중 (`.preparing`) | `Preparing.fetchOriginal` 영상 받기 *(iCloud 원본을 받아야 할 때만)* → `Preparing.prepare` 편집 준비 *(준비가 안 끝났을 때만)* → `Preparing.transcribe` 말 받아적기 → `Preparing.findPerson` 사람 찾기 → `Preparing.split` 장면 나누기 |
| 만드는 중 (`.making`) | `Making.encode` 영상 만들기 → `Making.review` 살펴보고 다듬기 |

`Preparing.findGaps` · `Preparing.reframe` · `Making.captions` · `Making.reframe` 는 **폐기 표시**만 해 두고 남겼다 —
바꾸는 층(`ViewDataMapper.prepareSteps` · 채팅 수정 중 `.making`)이 새 이름으로 옮기면 지운다.
옮길 때 `ViewDataMapperTests.planPreparing` 의 기대값(단계 4개)도 같이 바뀐다.

### 1절 "뜻이 맞는지 디자인 확인 필요" — `removedGapAfter`

**맞다.** 원본에서 바로 이어진 두 장면 사이의 틈 = AI 가 뺀 쉬는 구간이다. 순서를 바꾼 장면 사이는 비운다 —
그건 "뺀 것" 이 아니라 "옮긴 것" 이라 되돌릴 대상이 아니다. 10초 넘는 틈을 거르는 것도 좋다
(그건 쉬는 구간이 아니라 다른 부분을 통째로 안 쓴 것이다).

---

## 6. 붙이면서 남은 것 (개발 → 디자인, 2026-09-28)

`AppController`(`Madi/App`)가 `RootView` 에 값을 넣고 `UIAction` 을 받는다. 붙이면서 걸린 것:

| # | 무엇 | 왜 | 제안 |
|---|---|---|---|
| ⑧ | **결과물 고르기가 밖으로 안 나온다** | `ResultsScreen` 이 고른 결과물을 안에서만 기억한다 — `resultDetail`(이전 판과 나란히)을 채울 수 없다. 지금은 비어 있다 | `UIAction.Results.select(ResultRef.ID)` |
| ⑨ | 편집안 칸에서 **결과물을 연 것**이 안 나온다 | `plan(.openResults)` 는 어느 결과물인지 모른다 — "봤다" 를 적을 수 없다 | `openResults` 에 id, 또는 결과물 화면에서 ⑧ |

### 디자인 답 (2026-09-28)

**⑨ 넣었다.** `UIAction.Plan.openResults` → `openResults(ResultRef.ID?)`.
- id 는 `PlanView.latestResultID`(새 칸, 기본값 nil) — 이 편집안의 **가장 최근 결과물**. 매퍼가 채운다
- `RootView` 는 그 id 를 결과물 칸의 처음 고를 것으로 넘긴다. 채팅 `openResult(id)` · 만드는 중 `openResult(id)` 도 같은 길로 그 결과물을 골라 연다
- 개발 코드는 **고치지 않아도 컴파일된다** — `case .openResults, .play:` 는 딸린 값을 안 적어도 맞는다. "봤다" 를 적으려면 `case .openResults(let id?): Exporter.markSeen(id)` 로 나누면 된다

**⑧ 넣었다.** `UIAction.Results.select(ResultRef.ID?)`.
- `ResultsScreen` 이 고른 결과물이 바뀔 때마다 내보낸다. 처음 열 때 고른 것(⑨ 로 넘어온 것 포함)도 한 번 나온다. 고른 게 없으면 `select(nil)`
- 개발: `case .select(let id):` 에서 그 id 로 `resultDetail`(이전 판과 나란히)을 채운다.
  지금은 `@unknown default` 가 받아서 빌드는 되고 경고만 난다

개발 쪽에 남았던 것 — **전부 이었다 (2026-09-28)**:
- 목록에서 숨기기 · 되돌리기 (`video.hiddenAt`, 가장 최근에 숨긴 것부터 되살린다)
- 자막 모양 저장 — 새 스타일 판(다음 영상부터). 굵기 대응 보통 400 · 조금 굵게 480(지금 기본 · 실측) · 굵게 700 · 아주 굵게 900.
  미리보기는 렌더 코드(`StillRenderer`)가 판마다 한 장 그린다
- 앨범 거르기 — 설정 "앨범 고르기" 를 누르면 **메뉴**(전체 보관함 + 앨범들)가 뜬다. 확인 버튼이 없어 새 문구가 필요 없다
- "아쉬운 점 남음" — 보여 준 결과물 리포트의 소프트 항목(G11 짧음 · 김, G8 훅)으로 채팅 한 줄. G9 는 문구가 없어 안 낸다
- 원본 받는 중 진행률 — 가져오기가 메모리 게시판에 올린다
- "다시 가져오기" 는 분석이 아니라 **원본을 다시 받는다** (다시 훑으면 받기 실패한 영상을 다시 받는다)

### ⑩ 앱 안 재생 — 지금은 재생이 안 된다 (개발 → 디자인, 2026-09-28)

사용자 확인: **동영상 재생이 안 된다.** 까닭 둘:
- `PlanPlayer` · `ResultCompare` 는 썸네일 + 버튼인 **자리표시**다 (`PlanPlayer` 주석: "실제 재생은 개발이 붙인다")
- `ResultsScreen` 이 `ResultCompare(onPlay:)` 를 잇지 않아 결과물 화면의 "처음부터 재생" 은 행동조차 안 나온다.
  갤러리 정보 패널의 ▶ 는 버튼이 아니라 장식이다

~~개발이 임시로 한 것: QuickTime 으로 연다~~ → **앱 안에서 재생한다 (2026-09-28, 사용자 결정 "개발이 최소로 직접 고침")**.
개발이 `Madi/UI` 에서 고친 줄 (디자인이 다시 그려도 된다 — 지킬 것은 "내보낸 mp4 를 앱 안에서 재생"):
- 새 파일 `Common/MediaPlayerView.swift` — `AVPlayerView` 를 감싼 뷰 · 주소마다 재생기 하나(`MediaPlayers`) ·
  편집안 영상(`PlanVideo`, 위치 옮기기 알림 `.madiPlayerSeek` 을 받는다)
- `ViewData`: `ResultRef.fileURL` · `PlanView.previewURL` (기본값 nil)
- `PlanPlayer`: `url` 이 있으면 썸네일 · 자리표시 막대 대신 영상 (재생 막대는 `AVPlayerView` 것)
- `PlanScreen`: `PlanPlayer(url: plan.previewURL)` 한 줄
- `ResultCompare`: 결과물마다 영상, "둘 다 처음부터 재생" 은 같이 처음부터 튼다
- 편집안 "처음부터 보기" · 장면 "여기서 재생" 은 바꾸는 층이 알림으로 플레이어를 그 위치(장면 시작)로 옮겨 튼다
- 아직 안 만든 판(사람이 고친 판)은 영상이 없어 썸네일이다 — `§7` 레이어 트리 미리보기는 따로 만든다
- (2026-09-28 두 번째) 재생 막대를 `AVPlayerView` 것에서 **PlanPlayer 자리표시 막대와 같은 꼴**(`PlayerTransport` — 위치 막대 ·
  처음으로 · 재생/멈춤 · 시간)로 바꿨다. `AVPlayerView` 막대는 158pt 칸에서 겹쳤다. 결과물 칸도 같은 막대(`ResultVideo`).
  그림을 누르면 재생 · 멈춤
- 앱을 **라이트로 고정**했다 (`MadiApp.init`, §16) — 다크 모드 Mac 에서 사이드바 · 배경이 검게 나와 화면이 깨졌다.
  스크린샷 도구가 이미 하던 것을 앱에도 했다. 강조색 `AccentColor` 를 `Tokens.Palette.accent` 로 넣었다
  (사이드바 고른 칸은 사용자가 시스템 설정에서 고른 강조색을 따른다 — macOS 규칙)
- (세 번째) 막대 버튼: 처음으로 · 10초 뒤로 · 재생/멈춤 · 10초 앞으로 · 소리 끄기, 시간은 막대 밑 양 끝.
  다른 판 · 다른 결과물로 옮기거나 화면을 떠나면 재생기를 멈춘다 (안 보이는 영상 소리가 계속 나던 것)
- 스크린샷 `plan-video` · `results-video` 를 더했다. `MADI_SHOTS_VIDEO=<mp4>` 로 실제 영상을 넣어 뜬다

제안 (디자인이 정한다):
- `ResultRef.fileURL: URL?` · `PlanView.previewURL: URL?`(그 판의 보여 준 결과물) 를 ViewData 에 두고, 플레이어 자리에서
  AVKit `VideoPlayer` 로 바로 재생한다 — 내보낸 mp4 에 자막이 이미 그려져 있다 (`§7` 내보낸 파일)
- 아직 안 만든 판(사람이 고친 판)의 미리보기는 `§7` 대로 `AVPlayer` + `AVSynchronizedLayer` + **같은 레이어 트리** 여야 한다 —
  이건 개발이 뷰 하나(`MadiKit`)로 만들어 넘기는 게 맞다. 필요하면 말해 달라
- `ResultCompare.onPlay` 를 `UIAction.Results.play(ResultRef.ID)` 로 내보내기 (앱 안 플레이어 전에는 개발이 QuickTime 으로 연다)


## ⑪ 촬영본 삭제 (2026-09-29, 사용자 요청 "영상 삭제 기능도 있어야지" · 개발이 넣음)

- `UIAction.Gallery.delete(ShotItem.ID)` — 확인창을 거친 뒤 나간다
- 갤러리 우클릭 메뉴 "목록에서 숨기기" 밑에 **"마디에서 삭제…"** (⌘⌫). 누르면 `confirmationDialog`
  (`Copy.Gallery.Delete` — 제목 · 설명 · "삭제"). 결과물 화면 "휴지통으로 옮기기" 확인창과 같은 문법
- 지우는 것: 앱 사본 · 분석 · 편집안 · 결과물 파일 · 채팅 · 줄 선 작업. **사진 앱 원본 · 사진 앱으로 내보낸 영상은 그대로**.
  폴더로 들어온 영상은 입구 폴더(`~/Movies/madi`) 파일을 휴지통으로. 영상 행은 `deletedAt` 표시로 남아 다시 들어오지 않는다
- "목록에서 숨기기" 는 그대로 둔다 (되돌리기 있음). 둘을 하나로 합칠지는 디자인이 정한다

## ⑫ 촬영본 정보 칸에서 재생 (2026-09-29, 사용자 요청 · 개발이 넣음)

- `ShotItem.videoURL` (앱 사본, 다 받은 것만). 있으면 정보 칸 그림 자리가 `InlineVideo` — 누르면 그 자리에서 재생,
  멈춰 있으면 ▶ 를 얹는다. 밑에 편집안과 같은 재생 막대(`PlayerTransport`). 칸 비율은 영상 비율(가로 원본이면 가로 칸)
- 우클릭 "재생" · 스페이스 → 그 촬영본을 고르고 정보 칸에서 튼다 (`.madiShotPlay` 알림). QuickTime 을 열지 않는다
- 다른 촬영본을 고르면 재생을 멈춘다. 스크린샷 `gallery-video` (MADI_SHOTS_VIDEO)

## ⑬ 자막 모양 — 미리보기 문장 입력 · 아무 색 (2026-09-29, 사용자 요청 · 개발이 넣음)

- 미리보기가 **빈 검은 칸**이던 것: 세로 한 장(1080×1920)을 납작한 칸에 넣어 가운데만 보였다. 이제 바꾸는 층이
  자막 둘레 띠(1080×360, `StillRenderer.captionBand`)를 넘기고, 칸은 그 비율(3:1)로 fit
- 미리보기 문장 칸 둘 (`Copy.Look.previewTextField` · `previewSecondaryField`) — 치는 대로 미리보기가 바뀐다.
  모양이 아니라 저장되지 않는다 (앱 설정에 문장만 기억)
- 색: 견본 3개(자주 쓰는 색 바로가기) + **컬러 피커**(`ColorPicker`, 불투명). 견본에 없는 색이면
  `CaptionLook.customID` · 이름 "직접 고른 색", 피커 둘레에 고른 표시. `CaptionLook.fillColor` · `secondaryFillColor` 가 실제 색
- 피커를 끄는 동안은 미리보기만 바뀌고, 손을 멈춘 뒤(0.7초) 새 스타일 판으로 한 번 저장한다

## ⑭ 색 고르기 — iOS 처럼 말풍선 · 자주 쓰는 3색은 사람이 바꾼다 (2026-09-29, 사용자 요청 · 개발이 넣음)

- `ColorPicker`(macOS 색상 패널이 따로 창으로 뜸)를 걷고 `ColorGridPicker` — 무지개 테두리 동그라미를 누르면
  **버튼 밑 말풍선**으로 iOS 와 같은 격자(회색 12 + 색상 12 × 9)가 뜬다. `Common/ColorGridPicker.swift`
- 견본 3개는 고정이 아니라 **자주 쓰는 색 3칸**(`fav0…2`). 말풍선 아래 3칸을 누르거나 견본을 우클릭 "지금 색으로 바꾸기"
  → 그 칸이 지금 색으로 바뀐다. 본문 · 영문 줄이 따로 기억한다 (앱 설정, 스타일 판이 아니다)
- `UIAction.Settings.Look.setFavorite(Row, index:)` · `Row { main, secondary }`. 문구 `Copy.Look.favorites` · `setFavorite` · `setFavoriteHint`
- 스크린샷 `color-grid-panel` (말풍선은 창 밖이라 안쪽만)
- (2026-09-29 이어서) 말풍선 격자 밑에 **HEX 칸** — 지금 색을 `#RRGGBB` 로 보여 주고, 쳐서 엔터를 누르면 그 색
  (`#FF3366` · `ff3366` · `#f36` 모두 읽는다). 못 읽으면 "#RRGGBB 로 써 주세요". 사용자 요청으로 "숫자를 화면에 안 보인다" 는 규칙을 이 칸에서만 푼다
- (2026-09-30 버그 잡기 · 개발이 고침) 못 읽었다는 문구를 HEX 칸 **아래 줄**로 옮겼다 — 칸 옆에 두면 말풍선 폭(290)에 걸려
  "#RRGGBB 로…" 로 잘렸다. 말풍선 바탕을 불투명(`windowBackgroundColor`, `presentationBackground`)으로 — 기본 재질은 반투명이라
  설정 창 밖으로 나간 부분에 다크 모드 바탕화면이 비쳐 짙은 회색이 됐다 (개발 맥 실제 창)

## ⑮ 준비 단계 퍼센트 (2026-09-29, 사용자 요청 "얼마나 됐는지 모르고 계속 기다릴 수 없다" · 개발이 넣음)

- `PrepareStep.progress`(0…1) — 도는 단계 옆에 막대 + "42%". 잴 수 있는 단계만: 영상 받기 · 말 받아적기 · 사람 찾기
  ("사람 찾기" 줄이 뒤의 소리 · 컷 찾기까지 맡는다 — 7할 · 3할, 100% 에 멈춰 있지 않게)
- `PrepareStep.elapsed` — 잴 수 없는 단계(AI 가 장면을 나누는 중)는 "32초째". 남은 시간을 지어내지 않는다
- 분석은 받아적기 → 사람 찾기 → 소리 · 컷 순서로 **하나씩** 돈다. 전에는 두 줄이 같이 "도는 중" 으로 보였다
- 진행률은 메모리 게시판(`AnalysisProgressBoard`)에 있어 DB 가 안 바뀌면 화면이 안 따라왔다 — 작업이 도는 동안
  0.5초마다 다시 읽는다 (만드는 중 · 받기 진행률도 같이 부드러워진다)
- 1분 영상 실측(모델 데운 상태): 받아적기 3.4초 · 사람 찾기 31초 · 소리 · 컷 18초 — 끊김 없이 올라간다
  (`madi-spike digestprogress <영상>`). 스크린샷 `plan-analyzing`

## ⑯ Claude Design 0929 반영 (2026-09-29, 사용자 요청 · 개발이 옮김)

참고 사본 `docs/design/claude-design-0929/` (내보내기 그대로). `design/claude-design/` 예전 사본은 건드리지 않았다.
- 강조색 #2D6A55 → **#26407A** (`Tokens.Palette.accent` · `AccentColor` 에셋). 누름 `accentPressed` #1E3362 · 옅은 바탕 `accentSoft` #E3E6EE
- 링크: `.buttonStyle(.link)`(시스템 파랑) → `.accentLink` (강조색, 누르면 #1E3362) — 장면 줄 · 갤러리 상태줄 · 첫 실행 · 채팅
- 장면 역할 색: 훅 #B8603A · 시범 #3F8A66 · 설명 #8A63B8 · 마무리 #A39D95 (`Tokens.RoleTint`, 시스템 색 대신)
- 채팅 패널 (`02-Editor-v2` 에서 색 말고 바뀐 것):
  - 머리줄 48pt — "마디" + 상태 점 + "편집안 2에 대해 이야기 중" · "편집안 만드는 중" · "새 촬영본" (`Copy.Chat.Header`)
  - 말풍선 간격 — 같은 사람 6 · 말하는 사람이 바뀌면 18 · 날짜 줄 바로 뒤 0 · 결과 카드 6
  - 말풍선 모서리 18 · 묶음 마지막 말풍선에만 꼬리 · 최대 폭 사람 76% · AI 80%
  - 날짜 줄 "**오늘** 오후 2:20" (날만 굵게)
  - 달라진 점 카드 — 머리줄(첫 장면 그림 · `편집안 2` · `인스타 릴스 · 0:37`) + 표 + 아래 반반 버튼 "처음부터 보기 | 되돌리기"
    (`EditSummary.versionLabel` · `detail` · `thumbnail`, 비면 머리줄 없음)
  - 쓰는 중 — 점 셋이 차례로 통통 (1.2초, 시안 `madiDot`)
  - 입력칸 — 칩(26pt · 줄바꿈) + 36pt 둥근 칸 · 누르면 옅은 강조 테두리 · 글이 있을 때만 보내기(↑) ·
    AI 가 일하는 중이면 "답변이 끝나면 이어서 요청할 수 있어요"(문구 바뀜) + 멈추기(■)
- 시안의 받아쓰기(마이크) 버튼은 넣지 않았다 — 누를 것이 없는 버튼이 된다 (macOS 받아쓰기는 시스템 단축키로 된다)
