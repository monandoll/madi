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
        public static let openPlan = "편집안 열기"
        public static let makeShort = "바로 숏폼 뽑기"
        public static let make = "만들기"
        public static let play = "재생"
        public static let playFromStart = "처음부터 보기"
        public static let export = "내보내기"
        public static let openInPhotos = "사진 앱에서 보기"
        public static let removeFromLibrary = "보관함에서 빼기"
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
        public static let openSettings = "설정 열기"
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
