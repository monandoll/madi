# UI 문구 키 — 개발 쪽에서 필요한 목록

`Madi/UI/Copy.swift` 는 **디자인 쪽이 소유한다.** 개발은 이 파일을 건드리지 않는다.
개발이 필요한 문구는 **키만** 여기에 적고, 실제 문장은 디자인 쪽이 채운다.

개발 쪽 키 정의: `Madi/Review/GateNotice.swift`.

---


## 채운 곳 (디자인, 2026-09-28)

아래 키는 **전부 `Copy.swift` 에 있다.** 멤버 이름을 키 이름과 똑같이 맞췄다 — 키로 찾으면 된다.
진행률 · 이름처럼 값이 들어가는 것은 함수다.

| 절 | 키 → `Copy` 위치 |
|---|---|
| 편집 준비 | `Copy.Prep.modelDownloading(fraction)` · `.modelWarming` · `.modelWaitingForVideo` · `.modelDownloadPaused` · `.modelDownloadFailed` · `.modelDiskFull` (+ 사이드바 짧은 꼴 `.sidebarStopped` · `.sidebarNeedsInternet` · `.sidebarNeedsSpace`) |
| AI 연결 | `Copy.AI.aiNotConnected` · `.aiNotLoggedIn(name)` · `.aiDrafting` · `.aiDraftReady` · `.aiDraftFailed` (이유 한 줄 `.reasonLimit` · `.reasonLoggedOut(name)`) · 채팅 수정 실패는 `.aiEditFailed` · **새 키** `.analyzeFailed` |
| 스스로 살펴보기 | `Copy.Review.reviewChecking` · `.reviewGaveUp(reason:tip:)` (이유 · 요령 예 `.gaveUpReason…` · `.gaveUpTip…`) · `.reviewSoftNote(item)` (예 `.softShort` · `.softLong` · `.softHook`) |
| 채팅 수정 | `Copy.Remember.askRemember` · `.askRememberDetail` · `.rememberYes` · `.rememberNo` |
| 업데이트 | `Copy.Update.checkForUpdates` = "업데이트 확인…" |
| 사진 보관함 | `Copy.Photos.photoLibraryUsage` · `.photoLibraryDenied(folder:)` · `.importFromPhotosSince` · `.importFetchingOriginal(fraction)` · `.importFailed` (+ `.importFailedShort` · `.retryImport`) |
| 자막 모양 | `Copy.Look.lookSectionTitle` · `.lookFontDefault` · `.lookFontHint` · `.lookItalic` · `.lookWeight` · `.lookSecondarySameAsMain` · `.lookFontMissing` (+ 굵기 이름 · 색 이름 · 미리보기 문장 `.previewMain` · `.previewSecondary`) |
| 품질 안내 | `Copy.Gate.subjectTooSmall` · `.subjectTooSmallLowResolution` · `.subjectNotFound` · `.subjectAlreadyCropped` (+ 결과물 줄에 붙는 짧은 꼴 `.tipCloser` · `.tipResolution` · `.tipBackground` · `.tipWholeBody`) |
| 느린 Mac (`§17`) | **새 키** `Copy.Machine.slowMac` · `.slowMacDetail` |

**개발 일 하나**: `photoLibraryUsage` 는 `Info.plist` 에 들어가야 해서 `Copy` 로는 안 닿는다.
`project.yml` 의 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` 에 `Copy.Photos.photoLibraryUsage` 문장을 그대로 옮겨 적는다
(지금 넣어 둔 임시 문장과 뜻이 같고 띄어쓰기만 다르다 — "이 Mac을").

**자막 모양 화면**: 설정에 **탭**을 하나 새로 두었다 (`일반` · `자막 모양`, `settings-look`). 미리보기는 화면이 그리지 않는다 —
바꾸는 층이 `CaptionPainter.draw` 로 그려 `CaptionLook.preview` 에 넣는다 (`§7` 레이어 트리는 하나).
글꼴이 지워졌으면 `CaptionLook.fontMissing = true` — 목록에 그 이름을 그대로 두고 이유를 한 줄 붙인다 (`settings-look-font-missing`).

---

## 전사 모델 준비 — 첫 실행 뒤 (3단계)

**디자인 첫 실행 화면에는 이 상태가 없다.** 개발 쪽에서 필요한 상태를 넘긴다. 어디에 보일지는 디자인이 정한다.

첫 실행이 끝나자마자 앱이 **백그라운드로** 말 알아듣기 모델(약 500MB)을 받고, 받은 뒤 한 번 준비(약 1분)한다.
그동안에도 영상은 계속 들어온다. 크리에이터가 할 일은 없다 — **기다리게 하는 화면이 아니라 조용한 상태 표시다** (`§1-6`).

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `modelDownloading` | 받는 중 (진행률 0~1 이 함께 온다) | 편집 준비를 하고 있다. 기다릴 필요 없고, 영상은 그대로 들어온다 |
| `modelWarming` | 다 받고 처음 한 번 준비하는 중 (~1분) | 거의 다 됐다 |
| `modelWaitingForVideo` | 영상이 들어왔는데 준비가 아직 안 끝났을 때 (채팅) | 영상은 받아 뒀고, 준비가 끝나면 바로 본다 |
| `modelDownloadPaused` | 인터넷이 끊겨 멈췄을 때 | 인터넷이 다시 되면 이어서 받는다. 붉은색 아님 — 실패가 아니다 |
| `modelDownloadFailed` | 여러 번 다시 해도 안 될 때 (채팅) | 준비를 못 했다. 인터넷 연결을 한 번 봐 달라 |
| `modelDiskFull` | 저장 공간이 모자랄 때 (채팅) | 공간이 약 1GB 필요하다 |

- "모델" · "다운로드" · "CoreML" · "컴파일" 은 금지어 (`§1-5`). "편집 준비" 같은 말로
- 준비가 끝났을 때는 **아무 말도 하지 않아도 된다** — 조용한 게 기본이다
- 앱을 업데이트한 뒤에는 `modelWarming` 만 한 번 다시 온다 (새 빌드마다 준비를 다시 한다)

---

## AI 연결 · 편집안 만들기 (4단계)

앱이 크리에이터 본인 구독의 Claude 나 Codex 를 불러 편집안 초안을 만든다 (`§10`).
AI 가 연결돼 있지 않으면 **부르지 않고** 한 줄만 보인다. AI 없이 편집안을 만드는 길은 없다.
설치 · 로그인을 앱이 대신 해 주는 것은 6단계다 — 지금은 상태를 알아내기까지만 한다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `aiNotConnected` | Claude · Codex 둘 다 설치돼 있지 않을 때 | AI 를 연결하면 편집안을 만든다 (`§10` 의 한 줄) |
| `aiNotLoggedIn` | 설치는 됐는데 로그인이 안 됐을 때 | 로그인만 하면 된다. 어느 쪽(Claude / Codex)인지는 값으로 온다 |
| `aiDrafting` | 편집안 초안을 만드는 중 (보통 수십 초) | 영상을 보고 편집안을 짜는 중이다. 조용한 상태 표시 |
| `aiDraftReady` | 초안이 저장됐을 때 | 장면 카드로 보여 줄 준비가 됐다. 만들기(렌더)는 사용자가 고른다 |
| `aiDraftFailed` | 턴이 실패했을 때 (채팅, AI 말투) | 이번엔 편집안을 못 만들었다. 다시 해 보겠다 / 구독 한도 · 로그인 만료면 그 이유 한 줄 |

- "CLI" · "MCP" · "프롬프트" · "토큰" · "턴" 은 금지어 (`§1-5`)
- 붉은색은 `aiDraftFailed` 에만, 그것도 다시 해도 안 될 때만 (`§1-6`)

---

## 스스로 검사 · 다시 만들기 (5단계)

초안이 나오면 앱이 바로 만들어 **스스로 검사**하고, 기준에 못 미치면 AI 가 한두 번 고쳐 다시 만든다 (`§7` · `§8`).
크리에이터에게는 **검사를 마친 결과만** 보인다 (`§10`). 고치는 과정은 보이지 않는다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `reviewChecking` | 만들고 검사하는 중 (보통 1분 안팎, 고치면 더) | 거의 다 됐다. 조용한 상태 표시 |
| `reviewGaveUp` | 두 번 고쳐도 기준에 못 미쳐 보여 줄 결과가 없을 때 (채팅, AI 말투) | 이번 영상으로는 올릴 만한 결과를 못 만들었다. 이유 한 줄(예: 사람이 화면에서 너무 작게 · 빠르게 움직인다) + 다시 찍을 때의 조언 |
| `reviewSoftNote` | 보여 주되 아쉬운 점이 남았을 때 (채팅, AI 말투) | 결과는 올릴 수 있다. 다만 한 가지(예: 목표보다 조금 짧다)가 남았다 — 짧게 |

- "검사" · "게이트" · "self-eval" · "렌더" 는 금지어 (`§1-5`). "확인" · "다시 다듬기" 같은 말로
- 붉은색은 `reviewGaveUp` 에만

---

## 채팅 수정 (6단계)

크리에이터가 채팅으로 고쳐 달라고 하면 AI 가 새 편집안을 만든다. 고친 뒤 **한 번** 묻는다 (`§10`).
채팅 줄 중 앱이 붙이는 것(선택지 · 알림)은 DB 에 **키만** 있다 — 문장은 여기서 채운다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `askRemember` | 수정이 끝난 뒤 (채팅, AI 말투) | 앞으로도 이렇게 할까요? — 예면 다음 영상부터 같은 방식으로 만든다 |
| `rememberYes` | 버튼 | 앞으로도 이렇게 |
| `rememberNo` | 버튼 | 이번만 |
| `aiDraftFailed` | 수정 턴이 실패 (위 "AI 연결" 절과 같은 키) | 이번엔 못 고쳤다. 쓴 말은 그대로 있으니 다시 보내면 된다 |

---

## 결과물 내보낸 이력 (6단계)

목록 줄의 이력은 `Copy.Results.Export.historyLine(target:when:)` 를 쓴다. 사진 앱은 `photos`("사진 앱")로 "사진 앱에 저장함 · 오후 2:40" 이 되는데,
폴더 저장은 `files` 가 "Mac에 저장" 이라 "Mac에 저장에 저장함" 이 된다 — 이름 하나가 더 필요하다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| ~~`exportedToFolder`~~ | 폴더에 저장한 결과물의 목록 줄 | 2026-09-30 개발이 넣음 — `historyLine(target: 폴더 이름, …)` ("다운로드에 저장함 · 오후 2:40", viewdata-map ㉒) |

---

## 업데이트 (6단계)

앱은 하루 한 번 알아서 새 판을 확인한다 (Sparkle). 새 판 알림 창의 문구는 Sparkle 이 한국어로 그린다.
앱 메뉴에 손으로 확인하는 항목 하나가 필요하다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `checkForUpdates` | 앱 메뉴(`마디` 메뉴) 항목 | 새 판이 있는지 지금 확인한다 (예: "업데이트 확인…") |

---

## 사진 보관함 권한 — 첫 실행 (3단계)

macOS 가 띄우는 권한 창의 설명 문장이다. `Copy.swift` 가 아니라 앱 `Info.plist` 에 들어간다
(`project.yml` 의 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`). 지금은 개발이 임시 문장을 넣어 뒀다 — 다듬어 달라.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `photoLibraryUsage` | 첫 실행, 사진 보관함 권한 창 | 찍은 영상을 옮기지 않고 바로 편집하려고 읽는다. **영상은 이 Mac 을 떠나지 않는다** (수강생 · 회원이 찍힐 수 있다 — §2) |
| `photoLibraryDenied` | 권한을 안 줬을 때 (채팅) | 사진 앱 대신 폴더에 넣어도 된다 — 폴더 위치를 알려 준다. 설정에서 다시 켤 수 있다 |
| `importFromPhotosSince` | 첫 실행 뒤 (조용한 안내) | **앞으로 찍는 영상부터** 들어온다. 예전 영상은 들이지 않는다 |
| `importFetchingOriginal` | iCloud 에서 원본을 받는 중 (진행률 0~1) | 영상 원본을 가져오는 중 — "저장 공간 최적화" 면 오래 걸릴 수 있다 |
| `importFailed` | 원본을 못 받았을 때 (채팅) | 이 영상을 가져오지 못했다. 다음에 다시 시도한다 |

---

## 자막 모양 설정 (`look`) — 설정 화면

`AGENTS.md §9` "템플릿과 자막 모양". 크리에이터의 자막 스타일은 바뀐다 (2026-08-27 에 한 번 바뀌었다).
사용자가 **고르는** 것만 있다. 숫자 입력칸을 만들지 않는다.

개발 쪽 API:
- 글꼴 목록 — `MadiFont.hangulFamilies()` (한글을 그릴 수 있는 설치 글꼴). 맨 앞에 "기본" (= `fontFamily: null`, Pretendard)
- 값 — `StyleValues.look.caption` · `.look.secondary` 의 `fontFamily` · `weight` · `italic` · `fill` · `stroke`
- 검증 — `validate(_:)`. 설치 안 된 글꼴이면 실패한다
- 미리보기 — 같은 레이어 코드(`CaptionPainter.draw`)로 그린다. 따로 그리지 않는다 (`§7`)

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `lookSectionTitle` | 설정의 자막 모양 묶음 제목 | 자막 글씨 모양을 여기서 바꾼다 |
| `lookFontDefault` | 글꼴 목록 첫 항목 (`fontFamily: null`) | 앱 기본 글꼴 |
| `lookFontHint` | 글꼴 목록 아래 | 편집 앱에서 쓰던 글꼴을 이 Mac 에 설치하면 여기 나온다 |
| `lookItalic` | 기울임 켜기/끄기 | 글자를 살짝 기울인다 |
| `lookWeight` | 굵기 고르기 (가늘게 ~ 굵게, 몇 단계) | 글자 굵기 |
| `lookSecondarySameAsMain` | 보조 문구도 본문과 같은 글꼴 · 기울임을 쓸지 | 영문 줄도 같은 모양으로 |
| `lookFontMissing` | 저장된 글꼴이 이 Mac 에서 지워졌을 때 (채팅) | 쓰던 글꼴을 찾을 수 없어서 편집안을 못 만든다. 글꼴을 다시 설치하거나 다른 글꼴을 고르면 된다 |

- 크기 · 위치는 바꾸는 칸이 **없다.** 템플릿이 정한다
- 미리보기 문장은 한글 본문 + 영문 보조 한 줄. 크기가 그대로인 게 보여야 한다

---

## 품질 게이트 안내 (`GateNotice`)

`AGENTS.md §8` — 하드 게이트가 결과를 막지 않는 경우에 채팅으로 알린다.
**알림창이 아니라 채팅 안에 AI 말투로** (`§1-6`). 붉은색을 쓰지 않는다 — 실패가 아니다.

| 키 | 언제 | 무엇을 전달해야 하나 |
|---|---|---|
| `subjectTooSmall` | 최대 허용 배율까지 확대해도 인물이 목표만큼 안 커짐 | 결과는 나왔다. 다음에 **조금 더 가까이서** 찍으면 인물이 크게 나온다 |
| `subjectTooSmallLowResolution` | 위와 같고, **원본 해상도를 올리면 여지가 생기는** 경우 | 위 내용 + **더 높은 해상도로 찍으면** 더 크게 잡을 수 있다 |
| `subjectNotFound` | 사람을 못 찾은 구간이 길이의 20% 초과 | 결과는 나왔다. **배경이 단순한 곳**에서 찍으면 더 잘 잡힌다 |
| `subjectAlreadyCropped` | 원본에서 인물이 이미 위·아래로 잘려 있어 G2 를 잴 수 없음 | 결과는 나왔다. 다음엔 **몸 전체가 들어오게** 찍으면 화면을 더 잘 잡는다 |

### 말투 주의

- 사용자를 탓하지 않는다. "잘못 찍었다" 가 아니라 "다음엔 이렇게 하면 더 좋다"
- 숫자를 보여주지 않는다. "업스케일 1.25", "마스크 28% 미검출" 같은 말은 UI 에 나오지 않는다
- **"리프레임" · "마스크" · "업스케일" 은 금지어** (`§1-5`). "화면 잡기" · "사람 찾기" 로

### 배경 (왜 이것들인가)

- `docs/findings/2026-09-25-zoom-design.md` — 1080p 로 멀리서 찍으면 확대 여력이 **음수**다.
  4K 는 2.5배까지 확대할 수 있다
- `docs/findings/2026-09-25-pose-detection-spike.md` — 배경이 복잡하면(기구 · 거울 · 2인 겹침)
  사람을 못 찾는 구간이 30% 까지 간다. 단색 벽에서는 0% 였다
- `docs/findings/2026-09-25-g2-measurement.md §3` — 2인 클로즈업(`6U6Qp35FQaM`)은
  마스크가 화면의 65~93% 를 덮어 원본에서 이미 위·아래가 잘려 있다.
  "우리가 새로 잘랐는가" 를 물을 수 없어 분모가 0 이 된다

---

## 자막 모양 견본 이름 (6단계, 개발 → 디자인 2026-09-28)

설정 자막 모양 탭의 색 견본 **이름**이 `Copy` 에 없고 미리보기 데이터(`SampleData.swatchesMain`)에만 있다.
바꾸는 층은 지금 그 이름을 빌려 쓴다 — `Copy` 로 옮겨 주면 거기서 읽는다. 색 값은 개발이 정한다(노란색은 영문 줄 실측 `#FEE374`).

| 키 | 무엇 |
|---|---|
| `swatchWhite` | 흰색 |
| `swatchYellow` | 노란색 |
| `swatchSky` | 하늘색 |

