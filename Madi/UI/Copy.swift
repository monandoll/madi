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
        /// AI 미연결은 **오류가 아니다**. 붉은색을 쓰지 않는다.
        public static let aiDisconnectedHint = "AI를 연결하면 편집안을 만들어요"
        /// 설정은 앱 메뉴 `마디 > 설정…` (⌘,) 가 기본 경로다.
        /// 사이드바에 칸으로 두지 않는다 — 같은 것이 두 군데가 된다.
        /// 다만 ⌘, 를 모를 수 있으니 누를 자리를 남긴다 (톱니 아이콘).
        public static let openSettings = "설정…"
    }

    // MARK: - 갤러리

    public enum Gallery {
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
            public static let secondaryHint = "비워 두면 AI가 다시 맞춰요"
            public static let doneEditing = "완료"
        }

        /// 편집안을 짜는 중.
        public enum Preparing {
            public static let title = "편집안 만드는 중…"
            public static let header = "진행"
            public static let transcribe = "말한 내용 받아적기"
            public static let split = "장면 나누기"
            public static let findGaps = "쉬는 구간 찾기"
            public static let reframe = "화면 잡기"
            public static let done = "끝"
            public static func remaining(_ text: String) -> String { "\(text) 남음" }
            public static let stop = "멈추기"
            public static let scenesComing = "나누는 중…"
        }

        /// 영상을 만드는 중. 화면을 떠나지 않는다.
        public enum Making {
            public static let title = "영상 만드는 중…"
            public static let captions = "자막 만들기"
            public static let reframe = "화면 잡기"
            public static let encode = "영상 만들기"
            public static let keepsGoing = "창을 닫아도 계속 만들어요. 다 되면 알림으로 알려드려요."
            public static let readOnly = "만드는 동안에는 고칠 수 없어요"
            public static func percent(_ fraction: Double) -> String {
                "\(Int((fraction * 100).rounded()))%"
            }
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
