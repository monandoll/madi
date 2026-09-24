# 마디 (madi) — 운동·재활 크리에이터를 위한 AI 숏폼 편집 앱

**macOS 네이티브 앱.** Swift · SwiftUI 단일 언어. 화면부터 합성 엔진까지 전부 앱 안에 있다.
서버 없음, 웹 없음, 브라우저 없음.

전작(`legacy/v0.2`, Electron + Node + ffmpeg)을 버리고 다시 만든다. 코드를 옮겨 오지 않는다.
전작이 실패한 이유는 인프라가 아니라 **편집을 표현하는 자료구조**였다. 그 결론을 이 문서 전체가 전제한다.

1차 사용자는 물리치료사 겸 숏폼 크리에이터 1명 (인스타 12.5만, 유튜브 4만, 릴스·숏츠·틱톡 동시 운영).
편집 지식이 없다. 타임라인을 못 읽는다. 터미널을 열지 않는다.
말로 요청하면 **바로 업로드 가능한 영상**이 나와야 한다.

목표는 "AI가 도와준다"가 아니라 **편집 2~3시간 → 10분**이다. 이 수치가 유일한 성공 기준이다.

---

## 0. 반복 금지 목록

전작에서 실측으로 확인된 실패 원인이다. 코드 리뷰 때 이 표를 기준으로 거절한다.

| # | 전작이 한 것 | 왜 망했나 | 이번 규칙 |
|---|---|---|---|
| 1 | `Edit = {keep, parts, cuts, crop, subtitles}` | 표현 가능한 편집이 트림·크롭·자막뿐. 줌·BGM·효과음·오버레이·훅카드가 **구조적으로 불가능**. AI가 아무리 똑똑해도 출력 어휘가 없었다 | 코어 자료구조는 `Composition`(장면 · 레이어 · 키프레임). 편집 어휘를 먼저 넓히고 AI를 붙인다 |
| 2 | 9:16 크롭이 `cropFocus: Double` 하나 (정적 x좌표) | 인물이 화면 구석에 작게 박힘. 숏폼에서 피사체가 작으면 그 시점에 끝난 영상 | 리프레이밍은 **사람 bbox 추적 기반 시간축 키프레임** |
| 3 | 자막을 ffmpeg ASS 로 번인. 문장 통째로, 56pt on 1080 | 화면 폭의 5%짜리 자막. 딱 봐도 자동 생성 자막 | 자막은 **CoreText + CALayer**. 분절·크기·모션·외곽선은 템플릿이 강제 |
| 4 | 스타일을 `style.md` 자연어 규칙으로 두고 AI가 매번 해석 | 같은 요청에 매번 다른 결과. 일관성이 없으면 "내 채널 영상"이 아니다 | **스타일은 코드 자산**. AI는 스타일 값을 쓸 수 없다. 슬롯만 채운다 |
| 5 | 완성본에서 스타일을 "학습" | AI 에게 자연어로 스타일을 추측하게 시켰다. 매번 다른 값이 나왔다 | **재지 말고 학습하라는 게 아니다. 학습 말고 재라.** 자막 크기·위치·색·분절은 픽셀로 **측정 가능하다** (실제로 했다 — `tools/measure.mjs`). 측정 불가한 것은 "무엇을 잘랐는지" 뿐이고 그건 원본이 있어야 한다 |
| 6 | 렌더 결과를 아무도 다시 안 봄 | "처참하다"는 걸 코드가 모름. 품질 기준이 코드에 없었다 | `§8 품질 게이트` + `§7 self-eval` 이 1단계부터 들어간다 |
| 7 | (재작성 중 학습) 프레임 1장 보고 스키마를 정하려 했다 | 5편을 세어 보니 우선순위가 뒤집혔다 | **5편 이상 보고 정한다.** `docs/findings/2026-09-23-layout-survey.md` |

추가로 버리는 것: 자연어 스타일 규칙, `Memory` 승인 플로우, `Reference.insight`,
"AI 없이도 동작" 이중 경로(유지비만 컸다).

---

## 1. 제품 원칙 (코드 판단 기준)

1. **결과가 바로 올릴 수 있어야 한다.** "고치면 쓸 만함"은 실패다. 크리에이터가 CapCut을 다시 열지 않아야 한다.
2. **스타일은 자산, 콘텐츠는 AI.** 폰트·색·크기·모션·자막 위치를 AI가 정하면 버그다.
3. **장면 단위로 보여준다.** 풀 타임라인 편집기는 만들지 않지만, 장면 카드(썸네일 + 자막 + 길이)는 반드시 보여준다. 사용자가 틀린 곳을 짚을 방법이 없으면 안 된다.
4. **AI는 자기 결과를 본다.** 렌더 → 프레임 추출 → 재검사 → 수정. 사람에게 보여주기 전에 최소 1회.
5. UI에 전문 용어 금지. "인코딩"→"만드는 중", "컴포지션"→"편집안", "리프레임"→"화면 잡기".
6. 오류는 알림창이 아니라 채팅 안에 AI 말투로. 상태는 조용하게, 붉은색은 진짜 실패에만.
7. 개인화는 전부 설정값. 사용자 이름·스튜디오명을 코드에 박지 않는다.
8. **렌더는 항상 `Composition`으로부터 재현 가능**해야 한다. 결과 파일만 있고 결정이 없는 상태를 만들지 않는다.
9. **크리에이터에게 설치 이상의 것을 요구하지 않는다.** 터미널·CLI·계정 설정은 앱이 대신한다.
   "한 줄만 붙여넣으면 된다"도 요구다.
10. **디자인 시안이 정답이다.** `design/` 의 Claude Design 내보내기를 픽셀 단위로 따른다.
    임의로 컴포넌트를 "개선"하지 않는다. 다르게 해야 할 이유가 생기면 고치지 말고 물어본다.
11. **파일을 옮기게 하지 않는다.** 아이폰으로 찍으면 앱에 이미 있어야 한다.
    편집을 10분으로 줄여 놓고 파일 옮기는 데 5분 쓰면 목표를 반쯤 버리는 것이다.

---

## 2. 아키텍처

앱 하나다. 프로세스도 하나다 (AI CLI 자식 프로세스 제외).

```
madi.app  (Swift · SwiftUI · macOS 14+)
 │
 ├─ UI          SwiftUI — 갤러리 · 편집안 · 장면 카드 · 채팅 · 설정
 ├─ Store       GRDB(SQLite) — 미디어 · 다이제스트 · 컴포지션 · 작업 · 설정
 ├─ Queue       Swift actor + SQLite `jobs` — 렌더 1 · 분석 1 동시
 │
 ├─ Import      PhotoKit — iCloud 사진에서 촬영본을 읽는다 (업로드 없음)
 │              + 폴더 감시 (보조)
 │
 ├─ Analyze     → Digest (§6)
 │              Vision      VNDetectHumanBodyPoseRequest — 사람 bbox · 19관절
 │              WhisperKit  word 단위 전사 (CoreML)
 │              AVFoundation 오디오 에너지 · 무음 · 씬 컷 · 프레임 시트
 │
 ├─ Render      → Composition → mp4 (§7)
 │              AVMutableComposition            컷 · 순서 · 배속
 │              AVVideoCompositionCoreAnimationTool + CALayer   자막 · 오버레이 · 줌
 │              CoreText                        흰 글씨 + 검은 외곽선
 │              AVAssetExportSession (VideoToolbox)  내보내기
 │
 ├─ Review      품질 게이트(측정) + self-eval (§8)
 │
 └─ Agent       Process 스폰 — claude -p / codex exec (§10)
                MCP 서버 (stdio, 앱 내장) — 도구 2개
```

- **Apple Silicon 에서는 외부 바이너리를 받지 않는다.** ffmpeg · onnxruntime · Chrome Headless 전부 불필요.
  애플 프레임워크로 대체된다. 첫 실행 준비 화면도, quarantine 해제도 필요 없다.
  **Intel Mac 에서만** 전사 폴백으로 whisper.cpp 를 받는다 (`§17`). 그때는 quarantine 해제가 필요하다.
- **HTTP 서버가 없다.** 화면이 같은 프로세스 안이라 함수 호출로 끝난다.
  포트 · CORS · WebSocket · mixed content · 페어링 토큰이 전부 소멸한다.
- **영상이 기기를 떠나지 않는다.** 수강생·회원이 찍힌 촬영본이 섞일 수 있어
  제3자 개인정보가 들어올 수 있다. 로컬 처리가 기본값이고, 이걸 깨는 설계는 넣지 않는다.
- AI 는 **크리에이터 본인 Claude/Codex 구독**을 쓴다 (`Process` 스폰). 둘 다 지원한다.
  앱이 CLI 설치와 로그인 진입까지 대신한다. 사람은 브라우저에서 OAuth 버튼만 누른다.
- 유일한 자식 프로세스는 AI CLI 다. 따라서 **App Sandbox 를 끈다** — App Store 배포를 하지 않는다.

### 촬영본이 들어오는 길

```
아이폰 촬영 → iCloud 사진 자동 동기화 → 앱이 PhotoKit 으로 읽음 → 갤러리에 바로 뜸
```

업로드 화면이 없다. QR · 와이파이 · 토큰 · 터널 전부 필요 없다.

주의할 것:
- iCloud 사진 용량. 무료 5GB 로는 부족하다. 전달 전에 확인한다.
- "저장 공간 최적화" 설정이면 Mac 에 저화질만 있다.
  `PHImageRequestOptions.isNetworkAccessAllowed = true` 로 원본을 요청하고 진행률을 보여준다.
- 사진 라이브러리 접근 권한 (`NSPhotoLibraryUsageDescription`). 첫 실행 때 한 번.
- PhotoKit 이 막히거나 쓰기 싫어하면 **폴더 감시**로도 들어올 수 있게 둔다 (보조 경로).

### 배포

- 공증된 `.dmg`. 드래그해서 설치한다.
- **Apple Developer Program($99/년)은 판매 시작 시점에 낸다.** 그 전에는 지인 1명 대상이므로
  첫 실행만 우클릭 → 열기로 넘긴다. 서명 파이프라인을 0단계 전에 만들지 않는다.
- 자동 업데이트는 Sparkle. 사용자는 "업데이트 있음" 알림과 버튼만 본다.
- App Sandbox 끔, Hardened Runtime 켬 + `com.apple.security.cs.allow-unsigned-executable-memory`
  등 AI CLI 스폰에 필요한 엔타이틀먼트. `§12-6` 에서 정리한다.

### 이 선택이 만드는 부담 (숨기지 않는다)

1. **Remotion 을 버렸다.** 합성을 CoreAnimation/CoreText 로 직접 만든다.
   React 컴포넌트로 공짜였던 것들(레이아웃·줄바꿈·애니메이션)을 손으로 짠다.
   대신 Chrome 을 안 띄우니 더 빠르고, 라이선스 문제도 없다.
2. **모바일 화면이 없다.** 아이폰에서 결과를 확인하려면 사진 앱으로 내보내야 한다.
   iOS 앱을 만들지 않는다 (`§16`). 요구가 실제로 생기면 그때 SwiftUI 멀티플랫폼으로 검토한다.
3. **아키텍처가 둘이다.** Apple Silicon 과 Intel 을 모두 지원하지만 **성능 등급이 다르다** (`§17`).
   전사·사람감지 구현을 프로토콜로 감싸야 하고, Intel 경로는 별도로 테스트해야 한다.
   "느리다"를 버그로 취급하지 않는다 — 등급이 다른 것이다.
4. 크리에이터가 Claude/Codex 구독을 유지해야 한다. 끊기면 AI 기능이 멈춘다 — 조용히 실패하지 않는다.

---

## 3. 스택

| 영역 | 선택 | 비고 |
|---|---|---|
| 언어 | **Swift 6** | 제품 코드는 Swift 단일. 측정 도구만 Node (`tools/`) |
| UI | SwiftUI (macOS 14+) | Observation, `@Observable` |
| DB | **GRDB.swift** (SQLite) | 마이그레이션 · 관측 쿼리. SwiftData 쓰지 않는다 |
| 큐 | Swift actor + SQLite `jobs` | 렌더 1 · 분석 1 동시 |
| 가져오기 | **PhotoKit** + 폴더 감시(보조) | 업로드 없음 |
| 전사 | **WhisperKit** (CoreML, Apple Silicon) / **whisper.cpp** (Intel 폴백) | `TranscriptionProvider` 프로토콜 뒤에 숨긴다. word timestamps 필수 |
| 사람 감지 | **Vision** `VNDetectHumanBodyPoseRequest` | bbox + 19관절, 0.5s 간격. `PoseProvider` 프로토콜. Intel 에서도 동작(3~5배 느림) |
| 컷·배속 | **AVMutableComposition** | |
| 합성 | **AVVideoCompositionCoreAnimationTool** + CALayer | 자막 · 오버레이 · 줌 |
| 글자 | **CoreText** `NSAttributedString` | 외곽선은 **stroke 패스 + fill 패스 2회**. 음수 strokeWidth 는 글자를 깎는다 |
| 내보내기 | **AVAssetExportSession** (VideoToolbox) | H.264 / HEVC. `animationTool` 이 여기서만 적용된다 — `AVAssetWriter` 로는 자막이 안 붙는다 |
| 에이전트 | `Process` → `claude -p --output-format stream-json` · `codex exec` | **둘 다 필수**. `AgentProvider` 프로토콜 뒤에 숨긴다 |
| MCP | 앱 내장 stdio 서버 | 도구 2개 (`§10`) |
| 배포 | 공증 `.dmg` + Sparkle | **Universal 2** (`ARCHS = arm64 x86_64`). App Store 안 함 (샌드박스 불가) |
| 폰트 | Pretendard Variable (OFL) | 앱 번들에 동봉 |

Python 없음. 네트워크 요청은 AI CLI 와 (Intel 전용) whisper.cpp 다운로드 외에 없다.

**추상화는 두 개만 만든다.** `TranscriptionProvider` · `PoseProvider`.
아키텍처 분기를 이 두 곳에 가두고 다른 데로 새지 않게 한다.
`#if arch(arm64)` 를 코드 곳곳에 뿌리지 않는다 — 런타임에 한 번 골라 주입한다.

---

## 4. 레포 구조

```
Madi.xcodeproj
Madi/
  App/              진입점, 메뉴바, 창, 설정, 권한 요청
  UI/               SwiftUI — Gallery · PlanDetail · SceneCard · Chat · Settings
  Model/            Composition · Scene · Caption · Overlay · Digest (Codable)  ← §5
  Store/            GRDB 스키마 · 마이그레이션 · 리포지토리
  Queue/            actor 기반 작업 큐
  Import/           PhotoKit, 폴더 감시, 프록시 생성
  Analyze/          Digest 생성
    Transcription/  TranscriptionProvider — WhisperKit(arm64) · WhisperCpp(x86_64)
    Pose/           PoseProvider — Vision
    Audio/ Scene/ Frames/
  Render/           AVMutableComposition · CALayer 트리 · AVAssetExportSession
  Review/           품질 게이트 측정 · self-eval 루프
  Agent/            AgentProvider · Claude · Codex · 프롬프트 조립
  MCP/              stdio 서버, 도구 2개
  Templates/        ★ 스타일. 스키마는 코드, 값은 데이터 (§9)
    StyleSchema.swift     파라미터 정의 · 검증 범위 · 기본값. **AI 접근 불가**
    ShortFormTemplate.swift  레이어 트리 조립. 값을 받아 그린다
    CaptionLayer.swift    CoreText 자막 레이어
    OverlayLayer.swift    타이틀 · 원 · 화살표 · 마크
    Layout.swift          role/slot 별 좌표 규칙, 리프레임 목표치
    StyleFitter.swift     완성본 프레임 → 측정 → 새 값 제안 (2단계 이후)
    Spec.json             AI 에게 보여줄 "이 템플릿이 지원하는 것"
  Resources/        Pretendard, 기본 BGM/SFX
    styles/short.v1.json  기본 스타일 **값**. 측정에서 나온 숫자. 빌드 없이 바뀐다
  UI/Tokens.swift   design/ 시안에서 추출한 색 · 간격 · 타이포
  UI/Copy.swift     모든 UI 문구. 하드코딩 금지
MadiTests/          단위 테스트
MadiUITests/
design/             Claude Design 시안 내보내기. **읽기 전용.** 개발이 픽셀 단위로 따른다
reference/          크리에이터 공개 숏폼 프레임 (스타일 근거. 지우지 않는다)
tools/              measure.mjs — PNG 에서 자막 지표 측정 (Node, 개발용)
docs/
  stage-0.spec.md   렌더러 스파이크 spec
  style-authoring.md 템플릿 작성법
  target-machine.md
  findings/         측정·조사 기록
archive/
  remotion-spike/   버린 웹/Remotion 스파이크. 측정 절차 참고용. 빌드하지 않는다
```

---

## 5. 코어 도메인 모델

`Madi/Model/Composition.swift`. 모두 `Codable` + 검증.

```swift
struct Composition: Codable {
    let id: String
    let videoID: String
    let templateID: String          // Templates/<id>. 스타일은 전부 여기 있다
    let templateVersion: Int
    var size: CGSize                // 1080 x 1920
    var fps: Int                    // 30
    var meta: Meta                  // title, platform, targetDurationSec
    var scenes: [Scene]             // 배열 순서 = 결과물 순서. 원본 순서와 달라도 된다
    var audio: AudioTracks          // bgm(gain, duck), sfx[]
    var revisionOf: String?         // 결과물이 있는 컴포지션은 제자리 수정 금지
    var createdAt: Date
}

struct Scene: Codable {
    let id: String
    var role: Role                  // hook · demo · explain · cta · filler
    var source: Source
    var speed: Double               // 1 = 원속, 0.5 = 슬로우
    var reframe: ReframeTrack       // mode: auto|fixed|keyframes, keyframes[{t, rect}], padding
    var captions: [Caption]
    var overlays: [Overlay]
    var transitionIn: Transition    // cut · fade · whip · zoom
}

// ⚠ 미결. 공개 숏폼 5편 조사 결과 우선순위대로
//   (docs/findings/2026-09-23-layout-survey.md):
//   1) source 가 영상만 가정한다. 해부학 그림이 **장면 자체**인 경우가 5편 중 2편 —
//      enum Source { case video(id:String, in:Double, out:Double)
//                    case image(assetID:String, duration:Double) }
//   2) Overlay circle/arrow 의 payload 미정의 (5편 중 3편 · 2편). Spec.json 에 확정
//   3) Caption.slot == .top 렌더 검증 — Before/After 라벨 (5편 중 2편)
//   4) reframe 키프레임 보간 — 줌·클로즈업 (5편 중 3편, 1단계와 함께)
//   5) layout: splitV + sources[] + Overlay .mark(o/x) — 5편 중 1편. 가장 나중
//   구현 전에 10편까지 늘려 빈도를 다시 센다.

struct Caption: Codable {
    let id: String
    var start: Double               // 장면 로컬 초
    var end: Double
    var text: String                // 2~7자 분절된 한 덩어리. 문장 통째로 넣지 않는다 (G5)
    var secondary: String?          // 영문 등 보조 문구
    var emphasis: [Range<Int>]      // text 안 강조 구간. 색은 템플릿이 정한다
    var slot: Slot                  // main · top. 실제 좌표는 Layout.swift
}

struct Overlay: Codable {
    let id: String
    var kind: Kind                  // titleCard · arrow · circle · image · counter · progress
    var start: Double
    var end: Double
    var anchor: CGPoint             // 0..1 정규화
    var payload: [String: JSONValue]  // kind별. Spec.json 이 스키마를 정의
}
```

**AI 가 쓸 수 없는 것**: 폰트, 색, 글자 크기, 자막 절대 좌표, 애니메이션 곡선, 외곽선 두께.
`Composition` 에 그런 필드를 추가하지 않는다. `payload` 안쪽도 `assertNoStyleValues()` 로 막는다
(금지 키: `font*`, `color`, `size`, `stroke*`, `opacity`, `easing`, `x`, `y`, `top`, `bottom` …).

기타: `Video`, `Proxy`(720p 프리뷰), `Digest`, `Output`(+ `reviewReport`), `Job`, `Chat`.

```swift
// 스타일 값. 코드가 아니라 데이터다 (§9)
struct Style: Codable {
    let id: String              // "short.v1"  ← 사람 이름을 넣지 않는다 (§1-7)
    var name: String            // "수현쌤 숏폼"  ← 표시용. 설정값이다
    var version: Int
    var values: StyleValues     // StyleSchema 가 정의·검증한다
    var measuredFrom: [String]  // 어떤 영상에서 재서 나온 값인지
    var isActive: Bool
    var createdAt: Date
}
```

`Composition.templateID` 는 **그리기 로직**을 가리키고, `styleID` 는 **값**을 가리킨다.
로직은 바꾸려면 빌드가 필요하지만 값은 아니다.

---

## 6. 분석 파이프라인 — Digest

AI 가 영상을 "읽는" 유일한 창구. 프레임을 통째로 넣지 않는다. 팩된 텍스트 + 소수 이미지.

1. **transcript** — WhisperKit, **word-level timestamp 필수**. 문장 단위로 묶어 표기
2. **subject** — Vision, 0.5s 간격 사람 bbox + 19관절. 리프레이밍 근거이자 "시범 중 / 말하는 중" 판정 근거
3. **audio** — 무음 구간, RMS 곡선 요약
4. **scene** — 프레임 차분 기반 컷 지점
5. **frames** — 씬 전환 직후 프레임을 4칸 격자로, 최대 2장

```
# VIDEO v_01   duration 182.4s   1920x1080   30fps

## TRANSCRIPT
[002.52-005.36] 오늘은 거북목 스트레칭 알려드릴게요

## SUBJECT  (0.5s, 정규화 xywh, pose)
002.5  0.41 0.22 0.18 0.62  .97  standing
(요약) 인물 평균 화면 점유 높이 0.61 · 좌우 이동 0.12 · 12.4~19.8s 바닥 자세

## AUDIO
silence 012.4-014.1 (1.7s)

## SCENES
cut 031.2  cut 058.9

## FRAMES
sheets/v_01_0.png   (000s / 031s / 059s / 090s)
```

- **동작을 추측하지 않는다.** 자막만 보고 "이때 스트레칭 중"이라고 쓰지 않는다. `SUBJECT` 와 `FRAMES` 로 확인한다.
- 다이제스트는 캐시한다. 원본이 바뀌지 않으면 재생성하지 않는다.

---

## 7. 렌더 파이프라인

```
Composition
   │
   ├─ 1. plan       장면별 원본 구간 계산. reframe.mode == .auto 면 subject 트랙으로
   │                키프레임을 채운 뒤 **Composition 에 다시 적는다** (재현 가능성)
   ├─ 2. compose    AVMutableComposition — 컷 · 순서 · 배속
   ├─ 3. layers     CALayer 트리 — 리프레임 변환 · 자막 · 오버레이 · 줌
   │                AVVideoCompositionCoreAnimationTool 로 붙인다
   ├─ 4. write      AVAssetExportSession (VideoToolbox) → mp4
   ├─ 5. gate       §8 품질 게이트 측정
   └─ 6. self-eval  실패 항목이 있으면 프레임 시트 + 게이트 리포트를 AI 에 되먹임
                    → Composition 수정 → 2번부터 재실행 (최대 2회)
```

- 자막은 **CoreText** 로 그린다. 외곽선은 **두 번 그린다** — 양수 `strokeWidth` 로 획만 깔고
  그 위에 fill 을 얹는다. 음수로 주면 CoreText 가 fill → stroke 순으로 그려서 획 절반이
  글자 안쪽을 파먹고, 글자 높이가 획 두께만큼 줄어든다.
  크리에이터 원본은 검은 외곽선 바로 안쪽이 온전한 흰색이다 — 안 깎인 쪽이 맞다
  (`docs/findings/2026-09-25-coretext-caption-measurement.md §1`).
- CALayer 애니메이션은 `beginTime` 을 `AVCoreAnimationBeginTimeAtZero` 기준으로 잡는다.
  0 을 그대로 쓰면 무시된다. `isRemovedOnCompletion = false`, `fillMode = .both`.
- 리프레임 키프레임은 스무딩한다(0.4s 저역통과). 프레임이 떨리면 즉시 실패 (G3).
- 중간 산출물은 `~/Library/Caches/madi/<compositionID>/`. 성공 시 정리, 실패 시 남긴다.

### 내보내기와 프리뷰는 경로가 다르다. 레이어 트리만 같다

`AVVideoCompositionCoreAnimationTool` 은 **내보내기에서만** 적용된다.
`AVAssetWriter` · `AVPlayer` · `AVAssetImageGenerator` 는 전부 무시한다.
0단계에서 실측으로 확인했다 (`docs/findings/2026-09-25-coretext-caption-measurement.md §8`).

| | 쓰는 것 |
|---|---|
| 내보내기 | `AVAssetExportSession` + `videoComposition.animationTool` |
| 프리뷰 | `AVPlayer` + `AVSynchronizedLayer` 에 **같은 레이어 트리** |

- **불변 조건은 "같은 `videoComposition`" 이 아니라 "레이어 트리를 만드는 함수가 하나" 다.**
  `Composition` + 스타일 값 → `[CALayer]` 를 내는 함수는 하나뿐이고,
  내보내기와 프리뷰가 그 하나를 부른다. 두 번째 구현이 생기면 그 순간 어긋나기 시작한다.
- 같은 시각의 **프리뷰 스냅샷**과 **내보낸 프레임**을 `tools/measure.mjs` 와 같은 계산으로
  대조하는 테스트를 둔다. 둘이 다르면 빌드를 깬다.
- **self-eval 프레임은 반드시 내보낸 파일에서 뽑는다** (`§7-6`).
  `AVAssetImageGenerator` 를 원본 컴포지션에 걸면 자막이 없는 프레임이 나오고,
  AI 는 "자막이 없다" 고 판단해 엉뚱한 수정을 한다.
- `AVAssetExportSession` 으로 막히는 게 나오면(프리셋 제약 등) 커스텀 `AVVideoCompositing` 으로
  프레임별 합성한다. **비상구이지 기본값이 아니다.**

---

## 8. 품질 게이트

`Madi/Review/Gate.swift`. **코드로 측정한다.** AI 판단에 맡기지 않는다.
`Output.reviewReport` 에 항목별 pass/fail + 측정값을 남긴다.

| # | 항목 | 기준 |
|---|---|---|
| G1 | 피사체 크기 | 인물 bbox 높이 >= 프레임 높이 55% 인 구간이 전체의 80% 이상 |
| G2 | 피사체 잘림 | 머리 상단·발목 관절이 프레임 밖으로 나가는 구간 5% 이하 |
| G3 | 리프레임 안정 | 인접 키프레임 간 중심 이동 <= 프레임 폭의 3%/frame |
| G4 | 자막 크기 | 글자 높이 >= 프레임 높이 **3.2%** (원본 실측 3.59% 에 여유 -15%) |
| G5 | 자막 분절 | 한 덩어리 <= **15자**, 2줄 이내 (원본 실측: 15자까지 한 줄) |
| G6 | 자막 싱크 | 캡션 start 와 대응 word start 오차 <= 0.15s |
| G7 | 자막 가림 | 자막 박스가 어깨선 위 관절을 덮지 않음 |
| G8 | 훅 | 0~1.5초 구간에 `role == .hook` 장면 또는 titleCard 존재 |
| G9 | 정적 구간 | 무음 + 저모션이 1.2초 이상 이어지는 구간 없음 |
| G10 | 컷 리듬 | 장면 길이 중앙값 1.5~4.0초 |
| G11 | 길이 | `meta.targetDurationSec` ±15% |
| G12 | 오디오 | 클리핑 없음, LUFS -16 ~ -13, BGM 덕킹 동작 |

- **G1 · G4 · G6 은 하드 게이트.** 실패하면 사용자에게 보여주지 않고 self-eval 로 되돌린다.
- 나머지는 소프트. 리포트에 남기고 채팅에서 한 줄로 알린다.
- 게이트 수치는 **원본 실측에서 나온다.** 근거 없이 정한 숫자를 하드 게이트로 걸지 않는다.
  두 번 겪었다:
  - G4 를 4.5% 로 뒀다가 크리에이터 실제 영상(3.59%)이 통과하지 못했다
    (`docs/findings/2026-09-23-reference-measurement.md §4`)
  - G5 를 13자로 뒀다가 크리에이터 자막 "반대쪽도 똑같이 진행해주세요"(15자, 원본은 한 줄)가
    **두 줄로 쪼개졌다.** 전편 자막 15개를 다 세어 15자로 고쳤다
    (`docs/findings/2026-09-25-coretext-caption-measurement.md §9`).
    글자 수는 실제 제약이 아니다 — **폭이 제약**이고 `maxWidthRatio` 가 이미 막는다.
    15자가 폭의 0.844 를 쓰므로 상한 0.90 안에 들어온다
- **G1~G12 는 아키텍처와 무관하다.** 품질은 Intel 에서도 같아야 한다.
  다른 것은 **시간**뿐이다 (`§17` 성능 등급). 느린 것을 품질 실패로 기록하지 않는다.

---

## 9. 스타일 — 스키마는 코드, 값은 데이터

원칙과 구현을 섞지 않는다.

- **원칙: AI 가 스타일을 정하지 않는다.** `§0-4` 실패 원인이다. 이건 바뀌지 않는다.
- **구현: 스타일 값은 코드에 박지 않는다.** 데이터다. 빌드 없이 바뀐다.

스타일이 Swift 상수로 박히면 크리에이터가 스타일을 바꿀 때마다 개발자가 코드를 고치고
새 빌드를 배포해야 한다. 숏폼 스타일은 몇 달마다 바뀐다. 그건 제품이 아니다.

### 3층

| 층 | 어디 | 바꾸려면 |
|---|---|---|
| **스키마** | `Madi/Templates/StyleSchema.swift` | 빌드 필요. 어떤 파라미터가 존재하는가 + 검증 범위 |
| **값** | `Resources/styles/short.v1.json` → DB `styles` 테이블 | **빌드 불필요** |
| **그리기** | `ShortFormTemplate.swift` · `CaptionLayer.swift` · `Layout.swift` | 빌드 필요 |

AI 는 여전히 스타일 값을 쓸 수 없다. 스키마가 막는다 (`§5 assertNoStyleValues`).
값이 데이터가 된 것은 **사람이 고치기 쉬워진 것**이지 AI 에게 권한을 준 것이 아니다.

### 이름에 사람 이름을 넣지 않는다

`styleID` 는 `short.v1` 처럼 중립적이어야 한다. `SuhyunShortV1` 같은 이름은
`§1-7`(개인화는 전부 설정값)과 충돌한다. "수현쌤 숏폼" 은 `Style.name` 필드다.

### 값은 어떻게 채우나 — 재는 것이다

**학습하지 않는다. 잰다.** 둘은 다르다.

1. 크리에이터 공개 숏폼 **5편 이상**을 프레임 캡처해 `reference/` 에 넣는다.
   **1편만 보고 값이나 스키마를 정하지 않는다.** 5편을 보면 우선순위가 뒤집힌다
   (실제로 뒤집혔다 — `docs/findings/2026-09-23-layout-survey.md`)
2. 자막 폰트·크기·외곽선·위치·분절 길이·등장 모션을 **픽셀로 재서** `short.v1.json` 에 적는다.
   절차는 `docs/style-authoring.md`. 검증은 `tools/measure.mjs`
3. role 별 화면 구성과 리프레임 목표 점유율을 `Layout.swift` 에 적는다
4. `Spec.json` 에 AI 가 쓸 수 있는 role · slot · overlay kind 와 payload 스키마를 적는다
5. `reference/` 중 1편을 손으로 `Composition` 으로 재현해 렌더하고 원본과 나란히 본다 → **통과 기준**

### 스타일이 바뀌면 (2단계 이후)

크리에이터가 직접 숫자를 만지게 하지 않는다. "외곽선 7px" 을 알 리가 없다.

`StyleFitter` 가 새로 올린 완성본 3~5편의 프레임을 **재서** 새 값을 제안한다.

> "요즘 자막이 조금 커졌네요. 새 스타일로 맞출까요?"

- 사용자가 승인하면 새 `Style` 레코드(version+1)를 만들고 `isActive` 를 옮긴다.
  **이전 버전을 지우지 않는다** — 옛 결과물이 자기 스타일로 계속 재현돼야 한다 (`§1-8`).
- 측정은 결정론적이다. AI 가 추측하는 게 아니다. `tools/measure.mjs` 와 같은 계산이다.
- 승인 전에 **before/after 프레임을 나란히 보여준다.** 숫자만 보여주지 않는다.

### `short.v1` — 원본 실측값 (렌더러와 무관한 사실)

`docs/findings/2026-09-23-reference-measurement.md`. 720x1280 에서 재서 비율로 기록.

| 항목 | 값 | 신뢰도 |
|---|---|---|
| 본문 글자 높이 | 프레임 높이의 **3.59%** (1920 기준 69px) | 높음 — 3편 동일 |
| 본문 아래끝 | 아래에서 **0.2352** | 높음 — 4편 0.2344~0.2352 |
| 보조 문구 베이스라인 | 아래에서 **0.2023** | 높음 — 4편 중 3편 동일 |
| 외곽선 (바깥 두께) | 4~5px @720 → 6~7.5px @1080 | 중간 |
| 보조 문구 크기 | 본문 폰트의 **0.4444** (라틴 어센더 24px @1920) | 중간 |
| 한 줄 최대 | **15자** | 높음 — 전편 자막 15개를 다 셌다 |
| 자막 크기 | **고정.** fit-to-width 아님 (글자 수 6~15자에서 글자 높이 일정) | 높음 |
| 강조색 | **쓰지 않는다.** 본문 전부 흰색 | 높음 |
| 보조 문구 색 | 노란색 | 중간 |
| 인물 화면 점유 높이 | 0.72 목표 | 중간 |

"한 줄 최대" 는 공개 숏츠 1편(18.5초)의 자막 **15개를 전부 읽어서** 센 값이다.
최댓값이 15자였고 원본은 그걸 한 줄로 쓴다. 이전 값 12자는 프레임 몇 장만 보고 정한 것이었다.

**이 표는 CoreText 로 다시 그려도 그대로다.** 맞춰야 할 목표값이다.
반면 이전 Remotion 스파이크에서 쓴 `fontSize 78` · `baselineNudgeRatio 0.153` 같은 값은
CSS 줄상자 때문에 나온 보정이라 **버린다.** CoreText 는 폰트 메트릭을 직접 주므로
`CTLineGetBoundsWithOptions(.useGlyphPathBounds)` 로 실제 글자 높이를 계산해 역산한다.

---

## 10. AI 에이전트 규칙

### 도구는 2개뿐

| 도구 | 하는 일 |
|---|---|
| `read_digest(videoID)` | `§6` 다이제스트 텍스트 반환. 프레임 시트는 MCP 이미지 블록으로 동봉 |
| `write_composition(json)` | 검증 후 저장. 실패하면 에러 메시지를 그대로 돌려줘 고치게 한다 |

- **`render` 는 AI 가 호출하지 않는다.** 컴포지션이 저장되면 큐가 렌더한다.
- 도구를 늘리고 싶어지면 먼저 "이게 없으면 AI 가 뭘 못 하나"를 적는다. 대부분은 프롬프트나 템플릿 문제다.
- 에이전트는 파일을 직접 만지지 않는다. 읽기는 프레임 시트 디렉토리만 허용.

### 컨텍스트 조립 순서

```
1. 제작 지침 (playbook)     — 숏폼 편집 일반 규칙. 고정
2. 템플릿 Spec.json         — 쓸 수 있는 role · slot · overlay 와 payload 스키마
3. 품질 게이트 요약 (§8)     — 지켜야 할 수치
4. 사용자 규칙 (설정에서 직접 쓴 것)
5. digest
6. 대화 이력 / 수정 요청
```

세기 순서: **사용자 규칙 > 템플릿 Spec > 품질 게이트 > 제작 지침.**

### 동작 규칙

- 첫 진입: 다이제스트 생성 → AI 1턴 → `Composition` 초안 → 장면 카드로 표시.
  **자동 렌더하지 않는다.** 사용자가 고르면 렌더.
- 수정 요청은 항상 새 `Composition`(`revisionOf`)을 만든다.
- 수정 요청이 오면 고친 뒤 **"앞으로도 이렇게 할까요?"** 를 한 번 묻고, 예일 때만 사용자 규칙에 적는다.
- self-eval 턴은 사용자에게 보이지 않는다. 게이트 리포트 + 프레임 시트를 주고 컴포지션만 고치게 한다.
- 응답은 채팅에 스트리밍. 도구 호출 내부는 노출하지 않는다.
- AI 미연결 상태에서는 러너를 스폰하지 않는다. UI 는 "AI 를 연결하면 편집안을 만들어요" 한 줄만 보여준다.
  **AI 없는 편집 경로를 따로 만들지 않는다.**

---

## 11. 촬영 규칙 (docs/shooting.md)

편집 난이도를 낮추는 가장 싼 방법은 촬영을 규칙화하는 것이다. 크리에이터에게 A4 한 장으로 준다.

- 세로로, 인물이 화면 높이의 70% 이상 차지하게
- 순서 고정: 훅 멘트 → 동작 시범 3회 → 마무리 한마디
- 각 블록 시작 전에 **1초 정지**. 컷 경계가 된다
- 실수하면 **박수 한 번** 치고 다시. 박수 = "직전 테이크 버려" 신호로 자동 인식
- 배경은 단색 벽. BGM 은 나중에 넣으니 현장에서 틀지 않는다

이 규칙을 지킨 촬영본은 AI 판단이 90% 줄어든다. 지키지 않은 촬영본도 동작해야 하지만 품질은 보장하지 않는다.

---

## 12. 개발 단계

각 단계는 **통과 조건을 만족하기 전에 다음으로 가지 않는다.**
전작은 이 게이트가 없어서 6단계까지 갔는데 0단계를 통과하지 못한 상태였다.

**0. 자막 렌더 스파이크** (AI 없음, DB 없음, UI 최소)
`reference/` 프레임 위에 CoreText 자막을 겹쳐 그려 `§9` 실측표와 맞춘다.
- 통과: 본문 글자 높이 **3.59% ±0.1%**, 본문 아래끝 **0.2352 ±0.003**, 보조 베이스라인 **0.2023 ±0.003**
- 측정은 `tools/measure.mjs` 로 한다 (PNG 를 재므로 무엇이 그렸는지 무관)
- 이어서 `reference/` 1편을 손으로 `Composition` 으로 재현 → 내보내기 → 원본과 나란히 비교
- **눈으로 같은 채널 영상으로 보이지 않으면 여기서 멈춘다.** 1단계로 가지 않는다

**1. 리프레이밍**
Vision → bbox 트랙 → 키프레임 → CALayer 변환.
- 통과: G1 · G2 · G3

**2. 템플릿 완성**
`short.v1` 스타일 값 완성 — 자막 분절 · 강조 · 훅 · 보조 문구.
- 통과: G4 · G5 · G6 · G7

**3. 파이프라인 연결**
PhotoKit 가져오기 → 다이제스트 → 큐 → 렌더 → 갤러리. AI 없이 수동 Composition 으로.
- 통과: 아이폰으로 찍은 영상이 앱에 저절로 뜨고, 3분 안에 완성 영상이 나온다 (Apple Silicon 기준)
- Intel 폴백(`WhisperCppProvider`)도 이 단계에서 붙이고 **동작만** 확인한다. 시간은 재지 않는다

**4. AI 1턴**
`Process` 스폰 + MCP 2도구 + 프롬프트 조립.
- 통과: 새 촬영본에서 사람 손 없이 하드 게이트 3개 통과

**5. self-eval 루프**
- 통과: 10편 중 8편이 1회 되먹임 안에 하드 게이트 통과

**6. 채팅 수정 + 장면 카드 UI + 배포**
- SwiftUI 편집안 · 장면 카드 · 채팅
- 엔타이틀먼트, `.dmg`, Sparkle
- 통과: 크리에이터가 혼자 3편을 만들고 **각 편 10분 이내**.
  깨끗한 Mac 에서 `.dmg` 드래그 → 아이콘 클릭 → 사용까지 터미널 0회

**7. 롱폼**
챕터 분리, 숏폼 자동 추출, 롱폼 구성 채팅.
- 6단계 통과 전에는 시작하지 않는다

---

## 13. 라이선스

- **Remotion 문제가 사라졌다.** 쓰지 않는다. 연 비용 0, 인원 제한 0.
- **Pretendard Variable** — OFL. 앱 번들 동봉 가능.
- **WhisperKit** — MIT. 모델 가중치 라이선스는 채택 시점에 확인한다.
- **GRDB.swift** — MIT.
- **BGM/SFX** — 상업 이용 가능한 것만. 출처를 `Madi/Resources/audio/LICENSE.md` 에 남긴다.
- **구독 CLI** — 크리에이터 본인 구독을 본인 기기에서 쓰는 것이므로 회색지대가 아니다.
  다만 유료 판매로 넘어갈 때 Anthropic · OpenAI 약관을 그 시점에 재확인한다.

---

## 14. 개발 규칙

- 커밋 단위는 작게. 화면 하나 또는 워커 하나.
- 새 기능은 `Madi/Model` 의 타입부터. 저장·렌더·AI 가 같은 타입을 쓴다.
- **자막을 이미지로 미리 굽지 않는다.** CoreText 로 매번 그린다. 굽는 순간 수정이 막힌다.
- **렌더 관련 변경은 반드시 프레임 시트를 첨부**해 커밋에 남긴다.
  눈으로 확인하지 않은 렌더 변경은 머지하지 않는다.
- 프리뷰와 최종 렌더가 같은 레이어 코드를 쓰는지 테스트로 지킨다.
- UI 문구·에러 문구는 `Madi/UI/Copy.swift` 한 파일에. 하드코딩 금지. AI 말투로.
- 로그는 `OSLog`. 사용자에게 경로를 노출하지 않는다.
- 사용 이벤트(요청 종류, 소요 시간, 게이트 통과율)를 로컬 SQLite `events` 에 기록. 외부 전송 없음.
- **"편집 시간 10분" 을 계속 측정한다.** 원본 투입부터 내보내기까지 실측을 `events` 에 남기고,
  회귀하면 그 커밋을 되돌린다. `events` 에 **아키텍처(arm64/x86_64)를 같이 기록**하고
  성능 회귀 판정은 Tier 1 수치로만 한다 (`§17`).
- 아키텍처 분기는 `TranscriptionProvider` · `PoseProvider` 두 곳에만 둔다.
  `#if arch(arm64)` 를 코드 곳곳에 뿌리지 않는다.
- 테스트는 짧은 샘플 영상으로. Vision · WhisperKit 은 프로토콜로 감싸 테스트에서 대체한다.

---

## 15. 명령

```
open Madi.xcodeproj
xcodebuild -scheme Madi -configuration Debug build
xcodebuild -scheme Madi test
node tools/measure.mjs <png> [<png> ...]      # 자막 지표 측정
```

---

## 16. 하지 않는 것 (지금은)

- 풀 타임라인 편집기, 트랙, 키프레임 UI
- 범용 편집 도구화. 타깃은 운동·재활 크리에이터로 고정
- 스타일 자동 학습. 템플릿은 사람이 쓴다
- AI 없이 동작하는 별도 편집 경로
- **iOS 앱** — iOS 는 프로세스를 못 띄워 구독 CLI 가 불가능하다.
  아이폰은 촬영만 하고, 결과 확인은 사진 앱으로 내보내 본다
- **웹 UI · HTTP 서버 · 서버 배포** — 영상이 기기를 떠나면 안 된다
- Electron · Node 제품 코드 (Node 는 `tools/` 측정 도구에만)
- Remotion · ffmpeg · whisper.cpp · onnxruntime — 애플 프레임워크로 대체
- App Store 배포 (샌드박스에서 AI CLI 스폰 불가)
- 코드 사이닝 · 공증 · Apple Developer 계정 (판매 시점까지 미룬다)
- 다크 모드
- 롱폼 (6단계 통과 전까지)

---

## 17. 타깃 환경

- 크리에이터 Mac 한 대. macOS 14 이상 (SwiftUI Observation, Vision 관절 API).
- **Universal 2 로 빌드한다** (`ARCHS = arm64 x86_64`). 크리에이터 Mac 사양을 확정하기 전까지
  어느 쪽이든 돌아가야 한다.
- 아이폰은 **촬영 전용.** iCloud 사진으로 Mac 에 들어온다. 앱을 설치하지 않는다.
- 개발 머신과 크리에이터 머신이 다르다. 개발자 Mac 에서만 되는 것을 만들지 않는다.

### 성능 등급

**"동작한다"와 "10분 안에 된다"는 다르다.** 둘을 섞지 않는다.

| | Apple Silicon (Tier 1) | Intel x86_64 (Tier 2) |
|---|---|---|
| 동작 | ✅ | ✅ |
| **편집 10분 목표 (`§14`)** | ✅ 보장 대상 | ❌ 목표를 적용하지 않는다 |
| 품질 게이트 G1~G12 | ✅ | ✅ **동일하게 적용** |
| 전사 | WhisperKit (ANE) | whisper.cpp 폴백 (Metal/CPU) |
| 사람 감지 | Vision (ANE) | Vision (CPU/GPU, 3~5배 느림) |
| 인코딩 | VideoToolbox | VideoToolbox (Quick Sync) |
| 외부 바이너리 | 없음 | whisper.cpp 1개 (다운로드 + quarantine 해제) |

- **Tier 2 에서 느린 것은 버그가 아니다.** `events` 에 아키텍처를 같이 기록하고
  성능 회귀 판정은 Tier 1 수치로만 한다 (`§14`).
- Intel 에서 처음 실행하면 앱이 **솔직하게 알린다** — "이 Mac 에서는 만드는 데 더 오래 걸립니다".
  조용히 느려지게 두지 않는다.
- Tier 2 는 **실제 Intel Mac 에서 최소 1회 검증**한다. Rosetta 로 x86_64 빌드를 돌리는 것은
  동작 확인까지만 유효하고 성능 특성은 다르다. 그걸로 Tier 2 를 검증했다고 적지 않는다.
- WhisperKit 이 x86_64 빌드조차 안 되면 Tier 2 에서는 아예 제외하고 whisper.cpp 만 쓴다.
  1단계 전에 확인한다.
