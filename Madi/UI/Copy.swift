import Foundation

/// 화면에 나가는 **모든** 문구. 뷰에 문자열을 직접 쓰지 않는다 (AGENTS.md §14).
///
/// 말투 규칙 (AGENTS.md §1-5, §1-6):
/// - 전문 용어 금지. 인코딩→만드는 중, 렌더→만들기, 컴포지션→편집안,
///   리프레임·크롭→화면 잡기, 트랜스크립트→자막. 프록시 · 타임라인은 아예 노출하지 않는다.
/// - 오류는 알림창이 아니라 채팅 안에서 AI 말투로, 다음 행동 버튼과 함께.
/// - 사람 이름 · 스튜디오 이름을 여기 박지 않는다. 전부 설정값이다 (AGENTS.md §1-7).
public enum Copy {

    // MARK: - 공통

    public enum App {
        public static let name = "마디"
        public static let galleryWindowTitle = "마디"
    }

    public enum Action {
        public static let cancel = "취소"
        public static let back = "이전"
        public static let next = "계속"
        public static let skip = "건너뛰기"
        public static let stop = "멈추기"
        public static let undo = "되돌리기"
        /// 촬영본에서 시작하는 **단 하나의** 길. 누르면 편집안이 열리고 AI 가 초안을 짠다.
        /// "바로 뽑기" 처럼 장면 카드를 건너뛰는 길은 두지 않는다 (AGENTS.md §1-3, §10).
        public static let makeShort = "숏폼 만들기"
        /// 편집안에서 실제 영상을 만들 때. 장면 카드를 보고 난 뒤다.
        public static let make = "만들기"
        /// 결과물에서 그 편집안으로 돌아간다. 고치는 일은 편집안에서만 한다.
        public static let openPlanFromResult = "편집안 열기"
        public static let play = "재생"
        public static let playFromStart = "처음부터 보기"
        public static let export = "내보내기"
        public static let openInPhotos = "사진 앱에서 보기"
        /// **"삭제" 라고 쓰지 않는다.** 목록에서 안 보이게 할 뿐 원본은 사진 앱에 그대로 있다.
        public static let hideFromList = "목록에서 숨기기"
        /// 진짜로 지운다 — 앱 사본 · 편집안 · 결과물. 사진 앱 원본은 그대로다 (확인창이 그렇게 말한다).
        public static let deleteShot = "마디에서 삭제…"
        public static let search = "검색"
    }

    // MARK: - 사이드바

    public enum Sidebar {
        public static let libraryHeader = "보관함"
        public static let shots = "촬영본"
        public static let results = "결과물"
        public static let making = "만드는 중"

        /// 푸터. 스튜디오 이름은 설정값이라 여기 없다.
        public static let aiConnected = "Claude 연결됨"
        public static let aiConnectedCodex = "Codex 연결됨"
        public static let aiDisconnected = "AI 연결 안 됨"
        /// 설치는 됐는데 로그인이 풀렸다. 설치와 다음 행동이 달라서 따로 말한다.
        public static func aiNeedsLogin(_ name: String) -> String { "\(name) 로그인 필요" }
        /// AI 미연결은 **오류가 아니다**. 붉은색을 쓰지 않는다.
        public static let aiDisconnectedHint = "AI를 연결하면 편집안을 만들어요"
        /// 설정은 앱 메뉴 `마디 > 설정…` (⌘,) 가 기본 경로다.
        /// 사이드바에 칸으로 두지 않는다 — 같은 것이 두 군데가 된다.
        /// 다만 ⌘, 를 모를 수 있으니 누를 자리를 남긴다 (톱니 아이콘).
        public static let openSettings = "설정…"
    }

    // MARK: - 갤러리

    public enum Gallery {
        /// 촬영본 삭제 확인창. 되돌릴 수 없으니 무엇이 지워지고 무엇이 남는지 한 번에 말한다.
        public enum Delete {
            public static let confirmTitle = "이 촬영본을 마디에서 지울까요?"
            public static let confirmMessage = "편집안과 결과물도 함께 지워지고, 되돌릴 수 없어요. 사진 앱의 원본과 사진 앱으로 내보낸 영상은 그대로예요."
            public static let action = "삭제"
        }

        public static let title = "촬영본"

        public enum Filter {
            public static let all = "전체"
            public static let notEdited = "편집 전"
            public static let hasResult = "결과물 있음"
        }

        public enum Group {
            public static let today = "오늘"
            public static let thisWeek = "이번 주"
            public static let lastWeek = "지난주"
            public static let earlier = "그 전"
        }

        /// 빈 상태. 업로드 · 가져오기 버튼이 주인공이 아니다 — 저절로 들어온다는 사실이 주인공이다.
        public enum Empty {
            public static let title = "아이폰으로 찍으면 여기 자동으로 들어와요"
            public static let message = "iCloud 사진에 새 영상이 올라오면 1~2분 안에 나타나요."
            public static let addFromMac = "Mac에 있는 영상 넣기…"
        }

        public enum Importing {
            public static let title = "가져오는 중…"
            public static func progress(done: Int, total: Int) -> String {
                "iCloud 사진에서 가져오는 중 · \(total)개 중 \(done)개"
            }
        }

        public enum Loading {
            public static let title = "촬영본을 불러오고 있어요"
        }

        /// 사진 보관함을 못 읽는 상태. **오류가 아니다** — 다음 행동을 준다.
        public enum NoAccess {
            public static let title = "사진 보관함을 아직 못 봐요"
            public static let message =
                "괜찮아요. 사진 없이도 Mac에 있는 영상을 직접 넣어서 쓸 수 있어요.\n"
                + "나중에 허용하려면 시스템 설정을 열어주세요."
            public static let openSystemSettings = "시스템 설정 열기"
        }

        public enum Cell {
            public static let making = "만드는 중"
            public static func results(_ n: Int) -> String { "결과물 \(n)" }
        }

        /// 숨긴 뒤 상태줄에 한 줄로 알린다. 알림창을 띄우지 않는다.
        public enum Hidden {
            public static let notice = "목록에서 숨겼어요 · 사진 앱의 원본은 그대로 있어요"
        }

        /// 찾는 게 없을 때. **왜 없는지**를 말한다 — 거르개 때문인지, 말이 안 맞는 건지.
        public enum NoResults {
            public static func title(_ query: String) -> String {
                query.isEmpty ? "여기 보여줄 촬영본이 없어요" : "‘\(query)’에 맞는 촬영본이 없어요"
            }
            public static let message = "다른 말로 찾아보세요. 제목에서만 찾아요."
            public static func filterNote(_ filter: String) -> String {
                "지금 ‘\(filter)’만 보는 중이에요"
            }
            public static let showAll = "전체 보기"
        }

        public enum Status {
            public static let syncedWithICloud = "iCloud 사진과 맞춰져 있음"
            public static func lastChecked(_ minutes: Int) -> String {
                minutes < 1 ? "방금 확인" : "\(minutes)분 전 확인"
            }
            public static func selection(total: Int, selected: Int) -> String {
                selected == 0 ? "\(total)개" : "\(total)개 중 \(selected)개 선택됨"
            }
        }

        /// 오른쪽 정보 패널.
        public enum Info {
            public static let shotAt = "찍은 날"
            public static let duration = "길이"
            public static let speech = "말소리"
            public static let results = "결과물"
            public static let noSelection = "촬영본을 고르면 여기에 보여드려요"
            /// 오른쪽 패널 여닫기 버튼. 툴바 아이콘의 툴팁으로 쓴다.
            public static let toggle = "정보 보기"
            public static let noResultYet = "아직 없음"
        }
    }


    // MARK: - 편집안

    public enum Plan {
        public static let title = "편집안"
        /// 편집안을 고르는 메뉴. `편집안 2` 처럼 번호가 붙는다.
        public static func version(_ n: Int) -> String { "편집안 \(n)" }
        public static let backToGallery = "촬영본"

        /// 편집안 고르기. 고칠 때마다 새로 생기고 이전 것은 남는다 (`§1-8`).
        public enum Versions {
            public static let header = "편집안"
            public static let note = "고칠 때마다 새로 생겨요. 이전 편집안은 그대로 있어요."
            public static func meta(duration: String, scenes: String, when: String) -> String {
                "\(duration) · \(scenes) · \(when)"
            }
            /// **개수이지 버튼이 아니다.** 공유 아이콘을 붙이면 누르면 내보내는 줄 안다.
            public static func results(_ n: Int) -> String { "결과물 \(n)개" }
        }

        public enum Info {
            public static let header = "이 편집안"
            public static let length = "길이"
            public static let scenes = "장면"
            public static let format = "규격"
            public static let caption = "자막 자리"
            /// `0:42 → 0:37`
            public static func lengthChange(from: String, to: String) -> String { "\(from) → \(to)" }
            public static func removedGaps(count: Int, seconds: Double) -> String {
                "쉬는 구간 \(count)곳 뺌 (−\(Int(seconds.rounded()))초)"
            }
            public static let nowPlaying = "지금 보는 장면"
        }

        /// 자막 자리. **영상마다 하나**다 (`CaptionSlot`).
        ///
        /// 위치어(`위쪽` · `아래쪽`)를 쓰지 않는다. 자막 자리는 빈 곳으로 정해지지 않고
        /// **그 영상이 주로 보여주는 몸의 범위**로 정해진다. "피사체를 피해 둔다" 는
        /// 10편으로 검증해서 기각된 가설이다
        /// (`docs/findings/2026-09-25-caption-position-rule-test.md`).
        public enum Caption {
            public static let upperBody = "상반신 영상"
            public static let fullBody = "전신 영상"
            public static let lowerBody = "하체 클로즈업 영상"
        }

        public enum Scenes {
            public static func header(count: Int, total: String) -> String {
                "장면 \(count)개 · \(total)"
            }
            public static let remove = "빼기"
            /// 줄 버튼과 우클릭 메뉴가 **같은 말**을 쓴다. 다르면 다른 기능인 줄 안다.
            public static let extend = "1초 늘리기"
            public static let editCaption = "자막"
            public static let editCaptionFull = "자막 고치기"
            public static let extendOne = "1초 늘리기"
            public static let shortenOne = "1초 줄이기"
            public static let playFromHere = "여기서부터 재생"
            public static let removeScene = "장면 빼기"
            public static let noCaption = "자막 없음"
            /// 접었을 때 나머지 덩어리 수. 줄을 고르면 전부 펼친다.
            public static func moreCaptions(_ n: Int) -> String { "외 \(n)개" }
            public static let reorderHint = "끌어서 순서를 바꿀 수 있어요"
            /// 뺀 쉬는 구간 자리. 되돌릴 수 있다는 걸 보이게 남긴다.
            public static func removedGap(_ seconds: Double) -> String {
                "쉬는 구간 " + shortSeconds(seconds)
            }
            public static let bringBack = "되돌리기"
            public static let captionPlaceholder = "여기 자막을 적어주세요"
            /// 영문 보조도 직접 고칠 수 있다. 비워 두면 AI 가 본문에 맞춰 다시 만든다.
            public static let secondaryPlaceholder = "영문 보조"
            /// 영문을 손대지 않으면 AI 가 새 본문에 맞춰 다시 만든다.
            public static let secondaryHint = "영문을 그대로 두면 AI가 다시 맞춰요"
            public static let doneEditing = "완료"
        }

        /// 편집안을 짜는 중.
        /// 편집안을 짜는 단계. **엔진이 실제로 도는 순서와 이름을 맞췄다** (viewdata-map 1절).
        /// 영상 받기 → (편집 준비) → 말 받아적기 → 사람 찾기 → 장면 나누기.
        /// 앞의 둘은 해당될 때만 넣는다 — iCloud 원본을 받아야 할 때, 첫 실행 직후 준비가 안 끝났을 때.
        public enum Preparing {
            public static let title = "편집안 만드는 중…"
            public static let header = "진행"
            public static let fetchOriginal = "영상 받기"
            public static let prepare = "편집 준비"
            public static let transcribe = "말 받아적기"
            public static let findPerson = "사람 찾기"
            public static let split = "장면 나누기"
            /// ⚠ 엔진에 따로 도는 단계가 없다 — AI 가 장면을 고르며 같이 한다. 단계 목록에 넣지 않는다.
            @available(*, deprecated, message: "엔진에 없는 단계다. 목록에서 빼고 split 하나로 (viewdata-map 1절)")
            public static let findGaps = "쉬는 구간 찾기"
            /// ⚠ 화면 잡기는 렌더 안에서 된다 — 짜는 단계가 아니라 `Making.encode` 에 들어 있다.
            @available(*, deprecated, message: "화면 잡기는 렌더 안에서 된다. Making.encode 로 (viewdata-map 1절)")
            public static let reframe = "화면 잡기"
            public static let done = "끝"
            public static func remaining(_ text: String) -> String { "\(text) 남음" }
            public static let stop = "멈추기"
            public static let scenesComing = "나누는 중…"
        }

        /// 영상을 만드는 중. 화면을 떠나지 않는다.
        /// 엔진은 자막 · 화면 잡기 · 인코딩을 **렌더 한 번**에 한다 (~20초). 그다음 살펴보고,
        /// 모자라면 다시 다듬는다 (최대 2회). 그래서 단계는 둘이다.
        public enum Making {
            public static let title = "영상 만드는 중…"
            public static let encode = "영상 만들기"
            /// 검사 + 되먹임. "검사" · "렌더" 는 금지어라 이렇게 쓴다 (copy-keys `reviewChecking`).
            public static let review = "살펴보고 다듬기"
            @available(*, deprecated, message: "렌더 한 번에 자막까지 된다. encode 하나로 (viewdata-map 1절)")
            public static let captions = "자막 만들기"
            @available(*, deprecated, message: "렌더 한 번에 화면 잡기까지 된다. encode 하나로 (viewdata-map 1절)")
            public static let reframe = "화면 잡기"
            public static let keepsGoing = "창을 닫아도 계속 만들어요. 다 되면 알림으로 알려드려요."
            public static let readOnly = "만드는 동안에는 고칠 수 없어요"
            public static func percent(_ fraction: Double) -> String {
                "\(Int((fraction * 100).rounded()))%"
            }
        }

        /// 아직 다루지 못하는 촬영본. 롱폼은 `AGENTS.md §16` 에서 6단계 전까지 범위 밖이다.
        /// **"못 만들어요" 가 아니라 "아직 못 만들어요" 다.**
        public enum NotYet {
            public static let title = "이 길이는 아직 못 만들어요"
            /// ⚠ 10분은 **추측**이다. 크리에이터 촬영 길이를 아직 모른다 (decisions.md).
            public static let longMessage =
                "10분이 넘는 긴 영상은 아직 다루지 못해요. 짧은 촬영본으로 먼저 만들어볼까요?"
            public static let pickAnother = "다른 촬영본 고르기"
        }

        /// 장면이 하나뿐인 편집안. 짧은 촬영본에서 나온다. **막지 않는다** — 그대로 만들 수 있다.
        public enum SingleScene {
            public static let note = "장면이 하나예요"
        }

        /// 멈춘 편집안 (`PlanState.stopped`). 이유 문장은 `Copy.AI` · `Copy.Review` 에서 온다.
        public enum Stopped {
            public static let title = "여기서 멈췄어요"
            public static let tryAgain = "다시 해 보기"
            public static let tryAgainDetail = "같은 영상으로 한 번 더 짜 볼게요"
            public static let pickAnother = "다른 촬영본 고르기"
            public static let pickAnotherDetail = "다른 영상으로 먼저 만들어 봐요"
            public static let login = "로그인하기"
            public static let loginDetail = "브라우저가 열리고, 로그인하면 자동으로 돌아와요"
            public static let shootingTips = "다시 찍을 때 요령"
            public static let shootingTipsDetail = "사람이 크게 · 배경이 단순하게"
        }

        /// 로그인이 풀린 AI. 설치가 아니라 **로그인만** 하면 된다.
        public enum NotLoggedIn {
            public static func title(_ name: String) -> String { "\(name) 로그인만 하면 돼요" }
            public static let message = "로그인이 풀려서 편집안을 부탁할 수 없어요. 한 번만 다시 로그인해 주세요."
            public static let action = "로그인하기"
        }

        /// AI 가 연결돼 있지 않을 때. **오류가 아니다** (AGENTS.md §10).
        public enum NoAI {
            public static let title = "AI를 연결하면 편집안을 만들어요"
            public static let action = "AI 연결하기"
        }
    }

    // MARK: - 대화

    public enum Chat {
        public static let header = "대화"
        public static let inputPrompt = "말로 요청하기"
        public static let inputPromptBusy = "다 되면 이어서 요청할 수 있어요"
        public static let send = "보내기"
        public static let speak = "말로 하기"

        /// 아래 추천 칩. 고치는 요청이 대부분이다.
        public enum Chips {
            public static let cutGaps = "쉬는 구간 잘라줘"
            public static let captions = "자막 넣어줘"
            public static let shorter = "30초로 줄여줘"
            public static let reels = "인스타 규격으로"
            public static let shorts = "유튜브 쇼츠로"
            public static let hookFirst = "앞에 훅 넣어줘"
        }

        /// 말을 못 보낸 경우. AI 가 끊겼거나 답이 없을 때.
        public enum NotSent {
            public static let mark = "보내지 못했어요"
            public static let retry = "다시 보내기"
            public static let reconnect = "AI 다시 연결"
            public static let reason =
                "AI 연결이 끊겨서 방금 요청을 못 보냈어요. 쓰신 말은 그대로 뒀어요."
            public static let reconnectDetail = "설정을 열지 않아도 여기서 바로 돼요"
            public static let laterDetail = "연결되면 그때 다시 보내주세요"
            public static let later = "나중에"
        }

        public enum Summary {
            public static let playFromStart = "처음부터 보기"
            public static let undo = "되돌리기"
        }

        /// 다 만든 영상 카드.
        public enum Result {
            public static let done = "다 만들었어요"
            public static let open = "결과물 보기"
            public static let export = "내보내기"
        }
    }


    // MARK: - 결과물

    public enum Results {
        public static let title = "결과물"
        public static let isNew = "새로"

        public enum Compare {
            public static let sideBySide = "나란히"
            public static let single = "하나만"
            public static let before = "이전"
            public static let now = "지금"
            public static let playBoth = "둘 다 처음부터 재생"
            public static let play = "처음부터 재생"
            public static func changesFrom(_ label: String) -> String { "\(label)과 달라진 점" }
            public static let firstResult = "이 촬영본의 첫 결과물이에요"
        }

        public enum Empty {
            public static let title = "아직 만든 영상이 없어요"
            public static let message = "촬영본에서 편집안을 열고 ‘만들기’를 누르면\n다 만든 영상이 여기에 모여요."
            public static let action = "촬영본 보기"
        }

        public enum Loading {
            public static let title = "결과물을 불러오고 있어요"
        }

        public enum Export {
            public static let action = "내보내기"
            public static let title = "어디로 보낼까요?"
            public static let confirm = "내보내기"
            public static let photos = "사진 앱"
            public static let photosDetail = "아이폰에서 바로 확인하고 올릴 수 있어요"
            public static let files = "Mac에 저장"
            public static let filesDetail = "폴더를 고르면 파일로 저장해요"
            public static let airdrop = "AirDrop"
            public static let airdropDetail = "가까이 있는 기기로 바로 보내요"
            public static func done(_ target: String) -> String { "\(target)(으)로 보냈어요" }
            /// 내보내다 막힌 경우. 결과물 화면에는 채팅이 없어서 화면 위 한 줄로 말한다.
            public static func failed(_ target: String) -> String {
                "\(target)에 넣지 못했어요"
            }
            public static let failedReason = "잠시 뒤 다시 해보거나 Mac에 저장해 주세요."
            public static let retry = "다시 내보내기"
            public static let saveToMac = "Mac에 저장"
            /// 목록 줄에 남는 이력. `사진 앱에 저장함 · 오후 2:40`
            public static func historyLine(target: String, when: String) -> String {
                "\(target)에 저장함 · \(when)"
            }
        }

        public static let noSelection = "결과물을 고르면 여기에 보여드려요"

        /// 결과물은 **우리가 만든 파일**이라 지울 수 있다. 다만 되살릴 수 있어야 하므로
        /// macOS 휴지통으로 보낸다. "삭제" 라고 쓰지 않는다.
        public enum Trash {
            public static let action = "휴지통으로 옮기기"
            public static let confirmTitle = "이 영상을 휴지통으로 옮길까요?"
            public static let confirmMessage = "사진 앱으로 내보낸 건 그대로 있어요."
            public static let notice = "휴지통으로 옮겼어요"
        }
    }

    // MARK: - 만드는 중 (화면)

    public enum MakingScreen {
        public static let title = "만드는 중"
        /// 사이드바 숫자와 이 화면 제목은 **같은 것을 센다** — 지금 만들고 있는 것.
        /// 기다리는 것 · 멈춘 것은 묶음 제목에서 따로 센다.
        public static func waitingHeader(_ n: Int) -> String { "기다리는 중 \(n)개" }
        public static func stoppedHeader(_ n: Int) -> String { "멈춘 것 \(n)개" }
        public static let doneTodayHeader = "오늘 다 만든 것"
        public static let openResult = "결과물 보기"
        public static let cancel = "취소"
        public static let stop = "멈추기"

        public enum Empty {
            public static let title = "지금 만드는 영상이 없어요"
            public static let message = "편집안에서 ‘만들기’를 누르면\n여기서 얼마나 남았는지 볼 수 있어요."
        }

        public static func queuedNote(_ what: String) -> String { "\(what)이 끝나면 바로 시작해요" }
        public static func stoppedAt(_ percent: Int) -> String { "\(percent)%에서 멈췄어요" }
    }


    // MARK: - 첫 실행

    /// 묻는 것은 셋뿐이다 — 사진 · AI · 이름. 그 밖에는 앱이 알아서 한다 (`AGENTS.md §1-9`).
    public enum Onboarding {
        public static let appName = "마디"
        public static let skip = "건너뛰기"
        public static let next = "계속"
        public static let back = "이전"

        public enum Photos {
            public static let title = "사진 보관함을 볼 수 있게 해주세요"
            public static let message =
                "아이폰으로 찍은 영상이 iCloud 사진으로 Mac에 들어오면, 마디가 알아서 가져와요."
            public static let pointVideoOnly = "영상만 읽어요"
            public static let pointVideoOnlyDetail = "사진이나 다른 앨범은 건드리지 않아요"
            public static let pointOriginal = "원본은 그대로 둬요"
            public static let pointOriginalDetail = "편집은 복사본으로 하고, 아이폰 사진은 바뀌지 않아요"
            public static let pointAnytime = "언제든 끌 수 있어요"
            public static let pointAnytimeDetail = "설정에서 다시 바꿀 수 있어요"
            public static let allow = "사진 접근 허용"

            /// 허용하지 않아도 **막히지 않는다.** 다른 길을 알려준다.
            public static let deniedTitle = "괜찮아요, 이대로도 쓸 수 있어요"
            public static let deniedMessage =
                "사진 없이도 Mac에 있는 영상을 직접 넣어서 쓸 수 있어요. "
                + "나중에 허용하려면 시스템 설정을 열어주세요."
            public static let openSystemSettings = "시스템 설정 열기"
        }

        public enum AI {
            public static let title = "어떤 AI와 함께 편집할까요?"
            public static let message =
                "말로 부탁한 걸 알아듣고 편집안을 만드는 역할이에요. 이미 쓰고 있는 계정으로 로그인하면 돼요."
            public static let claude = "Claude"
            public static let claudeDetail = "Anthropic 계정으로 로그인"
            public static let codex = "Codex"
            public static let codexDetail = "OpenAI 계정으로 로그인"
            public static func login(_ name: String) -> String { "\(name)로 로그인" }
            public static let loginHint = "브라우저가 열리고, 로그인하면 자동으로 돌아와요"
            public static let waiting = "브라우저에서 로그인을 마쳐주세요"
            public static let waitingCancel = "취소"
            public static func connected(_ name: String) -> String { "\(name) 연결됨" }
            public static let otherAccount = "다른 계정으로"
            public static let needed = "AI를 연결해야 편집안을 부탁할 수 있어요"
            /// 여기서 막되 **가두지는 않는다.** 창은 닫을 수 있고, 다음에 켜면 이 단계부터 다시 한다.
            public static let closeHint = "창을 닫아도 돼요. 다음에 켜면 여기서 이어서 해요."
        }

        public enum Studio {
            public static let title = "스튜디오 이름을 정해주세요"
            public static let message = "앱 왼쪽 아래와 결과물 이름에 쓰여요. 나중에 설정에서 바꿀 수 있어요."
            public static let placeholder = "예: 바른몸 스튜디오"
            public static let previewLabel = "결과물은 이런 이름으로 저장돼요"
            public static let start = "시작하기"
            /// 이 단계에는 건너뛰기 버튼이 없다. 비워 두면 기본 이름으로 시작한다.
            public static let skipHint = "비워 두면 ‘내 스튜디오’로 시작해요"
            public static let defaultName = "내 스튜디오"
        }

        public enum Ready {
            public static let title = "준비됐어요"
            public static let message =
                "아이폰으로 찍은 촬영본이 자동으로 들어와요.\n처음 가져오는 데 1~2분쯤 걸려요."
            public static let start = "마디 시작하기"
        }
    }

    // MARK: - 설정

    public enum Settings {
        public static let title = "설정"
        public static let tabGeneral = "일반"

        public enum AI {
            public static let header = "AI 연결"
            public static let connected = "연결됨"
            public static let disconnect = "연결 끊기"
            public static let connect = "연결하기"
            public static let notConnected = "연결 안 됨"
            public static let active = "쓰는 AI"
            public static let activeHint = "바꾸면 새 계정으로 다시 로그인해요"
        }

        public enum Studio {
            public static let header = "스튜디오"
            public static let name = "스튜디오 이름"
            public static let nameHint = "앱 왼쪽 아래와 결과물 이름에 쓰여요"
        }

        public enum Shots {
            public static let header = "촬영본"
            public static let keep = "보관 기간"
            /// **앱이 가진 사본만** 지운다. 사진 앱 원본을 지우는 앱이 아니다.
            /// 문구에서 그걸 분명히 말한다 — 안 그러면 보관 기간을 줄이기가 무섭다.
            public static let keepHint =
                "기간이 지난 촬영본은 앱에서만 지워요. 사진 앱의 원본과 결과물은 그대로 있어요."
            public static func days(_ n: Int) -> String { "\(n)일" }
            public static let forever = "계속 두기"
            public static let album = "사진 폴더"
            /// 짧게 쓴다. `iCloud 사진 · 전체 보관함` 은 설정 줄에서 잘린다.
            public static let albumAll = "전체 보관함"
            public static let pickAlbum = "앨범 고르기"
            public static let photoAccess = "사진 접근"
            public static let photoAccessOn = "허용됨"
            public static let photoAccessOff = "허용 안 됨"
        }

        public static let loading = "연결을 확인하고 있어요"
    }


    // MARK: - 개발 쪽 문구 키 (docs/design/copy-keys.md)
    //
    // 아래는 엔진이 **키만** 들고 있는 문장이다. 멤버 이름을 키 이름과 똑같이 맞췄다 —
    // 개발은 copy-keys.md 의 키로 여기서 찾는다. 어디에 쓰이는지는 각 줄 주석에.

    /// 편집 준비 — 첫 실행 뒤 앱이 혼자 하는 것. **기다리게 하는 화면이 아니라 조용한 상태 표시다.**
    /// "모델" · "다운로드" · "CoreML" · "컴파일" 은 쓰지 않는다 (`§1-5`).
    /// 준비가 끝나면 **아무 말도 하지 않는다.**
    public enum Prep {
        /// 사이드바 아래 한 줄. 진행률이 같이 온다.
        public static func modelDownloading(_ fraction: Double) -> String {
            "편집 준비 중 · \(Int((fraction * 100).rounded()))%"
        }
        public static let modelDownloadingDetail = "기다리지 않아도 돼요. 영상은 그대로 들어와요."
        public static let modelWarming = "편집 준비 거의 다 됐어요"
        /// 채팅 — 영상이 먼저 들어왔을 때.
        public static let modelWaitingForVideo = "영상은 받아 뒀어요. 편집 준비가 끝나는 대로 바로 볼게요."
        /// 사이드바 — 인터넷이 끊겨 멈춤. **실패가 아니다.**
        public static let modelDownloadPaused = "인터넷이 되면 편집 준비를 이어서 해요"
        /// 채팅 — 여러 번 해도 안 될 때.
        public static let modelDownloadFailed = "편집 준비를 마치지 못했어요. 인터넷 연결을 한 번 봐 주세요. 연결되면 다시 해 볼게요."
        /// 채팅 — 저장 공간.
        public static let modelDiskFull = "편집 준비에 저장 공간이 1GB쯤 더 필요해요. 조금 비워 주시면 이어서 할게요."
        /// 사이드바 — 위 둘의 짧은 꼴.
        public static let sidebarStopped = "편집 준비가 멈췄어요"
        public static let sidebarNeedsInternet = "인터넷 연결을 확인해 주세요"
        public static let sidebarNeedsSpace = "저장 공간이 1GB쯤 필요해요"
    }

    /// AI 연결 · 편집안 만들기. "CLI" · "MCP" · "프롬프트" · "토큰" · "턴" 은 쓰지 않는다.
    public enum AI {
        public static let aiNotConnected = "AI를 연결하면 편집안을 만들어요"
        public static func aiNotLoggedIn(_ name: String) -> String { "\(name) 로그인만 하면 돼요" }
        /// 조용한 상태 표시.
        public static let aiDrafting = "영상을 보고 편집안을 짜고 있어요"
        /// 채팅 — 초안이 나왔다. 만들기는 사람이 고른다.
        public static let aiDraftReady = "편집안이 나왔어요. 장면을 한번 보시고 ‘만들기’를 눌러 주세요."
        /// 채팅 — 초안을 못 짰다.
        /// 이유 문장(`reason…`)을 **뒤에 붙인다.** "다시 해 볼게요" 는 이유마다 때가 달라서 여기 넣지 않는다
        /// (한도면 "조금 뒤에", 모르면 "한 번 더").
        public static let aiDraftFailed = "이번엔 편집안을 못 만들었어요."
        /// 채팅 — 채팅 수정을 못 했다 (같은 키, 수정 턴).
        public static let aiEditFailed = "이번엔 못 고쳤어요. 쓰신 말은 그대로 있으니 다시 보내 주세요."
        /// `aiDraftFailed` 의 이유 한 줄 — 구독 한도 · 로그인 만료.
        public static let reasonLimit = "지금 쓰시는 AI 구독의 사용량이 다 찼어요. 조금 뒤에 다시 해 볼게요."
        /// 까닭을 모를 때.
        public static let reasonUnknown = "한 번 더 해 볼게요."
        public static func reasonLoggedOut(_ name: String) -> String {
            "\(name) 로그인이 풀렸어요. 다시 로그인해 주시면 이어서 할게요."
        }
        /// 분석이 멈췄을 때 (viewdata-map 2절 9 — 새 키 `analyzeFailed`).
        public static let analyzeFailed = "영상을 살펴보다 멈췄어요. 한 번 더 해 볼게요."
    }

    /// 스스로 살펴보고 다시 다듬기. "검사" · "게이트" · "self-eval" · "렌더" 는 쓰지 않는다.
    public enum Review {
        /// 조용한 상태 표시.
        public static let reviewChecking = "거의 다 됐어요"
        /// 채팅 — 두 번 다듬어도 기준에 못 미쳐 보여 줄 결과가 없다. **붉은색은 여기에만.**
        public static func reviewGaveUp(reason: String, tip: String) -> String {
            "이번 영상으로는 올릴 만한 결과를 못 만들었어요. \(reason) \(tip)"
        }
        public static let gaveUpReasonSmall = "사람이 화면에서 너무 작게 잡혀요."
        public static let gaveUpReasonFast = "사람이 화면 밖으로 자주 나가요."
        public static let gaveUpTipCloser = "다음엔 조금 더 가까이서 찍어 주시면 잘 나와요."
        public static let gaveUpTipStill = "다음엔 한자리에서 움직여 주시면 잘 나와요."
        /// 채팅 — 올릴 수는 있는데 한 가지가 남았다. **짧게.**
        public static func reviewSoftNote(_ item: String) -> String {
            "올려도 괜찮아요. 다만 \(item). 신경 쓰이시면 말씀해 주세요."
        }
        public static let softShort = "목표보다 조금 짧아요"
        public static let softLong = "목표보다 조금 길어요"
        public static let softHook = "첫 1초가 조금 밋밋해요"
    }

    /// 채팅 수정 뒤 한 번 묻는 것 (`§10`).
    public enum Remember {
        public static let askRemember = "앞으로도 이렇게 할까요?"
        public static let askRememberDetail = "‘앞으로도’를 누르시면 다음 영상부터 같은 방식으로 만들어요."
        public static let rememberYes = "앞으로도 이렇게"
        public static let rememberNo = "이번만"
    }

    /// 앱 메뉴 (`마디` 메뉴). 새 판 알림 창은 Sparkle 이 그린다.
    public enum Update {
        public static let checkForUpdates = "업데이트 확인…"
    }

    /// 사진 보관함.
    public enum Photos {
        /// ⚠ `Copy.swift` 가 아니라 `Info.plist` 에 들어간다 — `project.yml` 의
        /// `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` 에 이 문장을 옮겨 적는다 (개발 일).
        /// 영상이 Mac 을 떠나지 않는다는 걸 권한 창에서 먼저 말한다 (수강생 · 회원이 찍힐 수 있다 — §2).
        public static let photoLibraryUsage =
            "아이폰으로 찍은 영상을 옮기지 않고 바로 편집하려고 사진 보관함을 읽어요. 영상은 이 Mac을 떠나지 않아요."
        /// 채팅 — 권한을 안 줬을 때.
        public static func photoLibraryDenied(folder: String) -> String {
            "사진 보관함을 못 봐도 괜찮아요. ‘\(folder)’ 폴더에 영상을 넣어 주시면 바로 가져와요. 나중에 설정에서 다시 켤 수 있어요."
        }
        /// 첫 실행 뒤 조용한 안내 — **앞으로 찍는 영상부터** 들어온다.
        public static let importFromPhotosSince = "지금부터 찍는 영상이 들어와요. 예전 영상은 가져오지 않아요."
        /// 갤러리 칸 · 정보 패널 — iCloud 에서 원본을 받는 중.
        public static func importFetchingOriginal(_ fraction: Double) -> String {
            "원본 가져오는 중 · \(Int((fraction * 100).rounded()))%"
        }
        public static let importFetchingOriginalDetail = "iCloud ‘저장 공간 최적화’가 켜져 있으면 오래 걸릴 수 있어요."
        /// 채팅 · 갤러리 칸 — 원본을 못 받았다.
        public static let importFailed = "이 영상을 가져오지 못했어요. 다음에 다시 해 볼게요."
        public static let importFailedShort = "가져오지 못했어요"
        public static let retryImport = "다시 가져오기"
    }

    /// 자막 모양 — 설정. **고르는 것만 있다.** 크기 · 위치 칸은 없다 (`§9`).
    public enum Look {
        public static let lookSectionTitle = "자막 모양"
        public static let lookSectionDetail = "글씨 모양만 바꿔요. 크기와 자리는 그대로예요."
        /// 옛 결과물은 자기 모양으로 재현돼야 한다 (`§9` · `§1-8`). 그래서 바꾼 모양은 **다음 영상부터**다.
        public static let appliesNext = "바꾼 모양은 다음에 만드는 영상부터 적용돼요. 이미 만든 영상은 그대로예요."
        public static let font = "글꼴"
        public static let lookFontDefault = "기본 글꼴"
        public static let lookFontHint = "편집 앱에서 쓰던 글꼴을 이 Mac에 설치하면 여기 나와요."
        public static let lookItalic = "기울임"
        public static let lookWeight = "굵기"
        public static let weightRegular = "보통"
        public static let weightMedium = "조금 굵게"
        public static let weightBold = "굵게"
        public static let weightHeavy = "아주 굵게"
        public static let fill = "본문 색"
        public static let secondaryFill = "영문 줄 색"
        public static let lookSecondarySameAsMain = "영문 줄도 같은 글꼴 · 기울임으로"
        public static let preview = "미리보기"
        /// 채팅 · 설정 — 저장된 글꼴이 지워졌다. 조용히 대체하지 않는다.
        public static let lookFontMissing =
            "쓰시던 글꼴을 이 Mac에서 찾을 수 없어서 편집안을 못 만들어요. 글꼴을 다시 설치하거나 다른 글꼴을 골라 주세요."
        public static let lookFontMissingShort = "이 Mac에 없는 글꼴이에요"
        /// 미리보기 문장. 크기가 그대로인 게 보여야 해서 한글 본문 + 영문 한 줄.
        public static let previewMain = "반대쪽도 똑같이 진행해주세요"
        public static let previewSecondary = "Repeat on the other side."
        /// 미리보기 문장 칸 (사람이 바꿔 넣는다).
        public static let previewTextField = "미리보기 문장"
        public static let previewSecondaryField = "영문 줄"
        /// 컬러 피커로 고른 색의 이름.
        public static let customColor = "직접 고른 색"
        public static let pickColor = "다른 색 고르기"
    }

    /// 품질 안내 (`Madi/Review/GateNotice.swift`). 결과는 나왔고 **다음 촬영 때 도움이 될 한 줄**이다.
    /// 붉은색이 아니다. 탓하지 않는다 — "잘못 찍었다" 가 아니라 "다음엔 이렇게 하면 더 좋다".
    /// 숫자를 보여 주지 않는다. "리프레임" · "마스크" · "업스케일" 은 쓰지 않는다.
    public enum Gate {
        public static let subjectTooSmall =
            "영상은 다 만들었어요. 다음엔 조금 더 가까이서 찍으시면 사람이 화면에 크게 나와요."
        public static let subjectTooSmallLowResolution =
            "영상은 다 만들었어요. 다음엔 조금 더 가까이서, 또는 더 높은 화질(4K)로 찍으시면 사람을 더 크게 잡을 수 있어요."
        public static let subjectNotFound =
            "영상은 다 만들었어요. 배경이 단순한 곳에서 찍으시면 사람을 더 잘 찾아서 화면을 더 잘 잡아요."
        public static let subjectAlreadyCropped =
            "영상은 다 만들었어요. 다음엔 몸 전체가 화면에 들어오게 찍으시면 화면을 더 잘 잡을 수 있어요."
        /// 결과물 옆에 붙는 짧은 꼴 (`ResultRef.notice`).
        public static let tipCloser = "다음엔 조금 더 가까이서 찍어 보세요"
        public static let tipResolution = "더 높은 화질(4K)로 찍으면 더 크게 잡혀요"
        public static let tipBackground = "배경이 단순하면 더 잘 잡혀요"
        public static let tipWholeBody = "몸 전체가 들어오게 찍어 보세요"
    }

    /// 이 Mac 이 느릴 때 (Intel, `§17`). **솔직하게 알린다** — 조용히 느려지게 두지 않는다.
    public enum Machine {
        public static let slowMac = "이 Mac에서는 만드는 데 더 오래 걸려요"
        public static let slowMacDetail = "결과물은 똑같이 나와요. 시간만 더 걸려요."
    }

    // MARK: - 상태 문구

    /// 촬영본에서 말소리가 얼마나 잡혔는지. "오디오 SNR" 같은 말을 쓰지 않는다.
    public enum Speech {
        public static let clear = "잘 들려요"
        public static let noisy = "조금 시끄러워요"
        public static let silent = "소리가 없어요"
    }

    /// 장면 역할. 색과 함께 **항상 글자로도** 말한다.
    public enum Role {
        public static let hook = "훅"
        public static let demo = "시범"
        public static let explain = "설명"
        public static let cta = "마무리"
        public static let filler = "쉬는 구간"
    }

    public enum Platform {
        public static let reels = "인스타 릴스"
        public static let shorts = "유튜브 쇼츠"
        public static let tiktok = "틱톡"
        public static let verticalNote = "세로"
    }

    // MARK: - 숫자 · 날짜

    /// 길이는 항상 `0:42` 꼴. "42.4s" 처럼 쓰지 않는다.
    public static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 장면 길이처럼 짧은 시간. `7.1초`.
    public static func shortSeconds(_ seconds: Double) -> String {
        String(format: "%.1f초", seconds)
    }

    public static func count(_ n: Int) -> String { "\(n)개" }

    public static func scenes(_ n: Int) -> String { "장면 \(n)개" }

    public static func results(_ n: Int) -> String { "결과물 \(n)" }

    /// 날짜 꼴은 `9. 25.` 가 아니라 **`9월 25일`** 이다.
    /// 시스템 템플릿(`setLocalizedDateFormatFromTemplate`)이 내주는 `9. 25.` 는 표에 쓰는 꼴이라
    /// 촬영본 묶음 제목으로 읽으면 날짜로 안 보인다. 한국어 전용 앱이라 꼴을 직접 적는다.
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    private static let dayFormatter = formatter("M월 d일")
    private static let timeFormatter = formatter("a h:mm")
    private static let fullFormatter = formatter("M월 d일 a h:mm")

    /// `9월 25일`
    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// `오후 2:14`
    public static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// `9월 25일 오후 2:14`
    public static func dayTime(_ date: Date) -> String { fullFormatter.string(from: date) }

    /// 오늘 찍은 것은 시각만, 그 전은 날짜만 보여준다 (사진 앱과 같은 규칙).
    public static func shotStamp(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? time(date) : day(date)
    }
}
