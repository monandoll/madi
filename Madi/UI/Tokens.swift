import SwiftUI

/// 화면 토큰. **기본은 시스템 값이다.**
///
/// macOS 앱에서 색 · 여백 · 글자 크기를 직접 정하면 그 순간 "웹 같다" 가 된다.
/// 그래서 여기 있는 것은 두 종류뿐이다.
///
/// 1. 시스템 값을 그대로 부르는 별칭 (왜 이 자리에 이 값인지 이름으로 설명하려고 둔다)
/// 2. 시스템에 없어서 어쩔 수 없이 정한 값 — **전부 주석으로 이유를 적는다**
///
/// 글꼴은 토큰이 없다. 앱 UI 는 전부 시스템 글꼴(SF)이고 `.headline` · `.caption` 같은
/// 시맨틱 스타일만 쓴다. Pretendard 는 **영상 안 자막 전용**이라 여기 들어오지 않는다
/// (AGENTS.md §3 폰트: 둘을 섞지 않는다).
public enum Tokens {

    // MARK: - 색

    public enum Palette {
        /// 앱 전체 tint. **커스텀인 이유**: 시스템 강조색은 사용자가 시스템 설정에서 고른 색이라
        /// Mac 마다 다르다. "만들기" 같은 주요 버튼 색이 Mac 마다 달라지면 화면 캡처와
        /// 설명이 안 맞는다. 시안(`design/claude-design`)이 쓰는 초록을 앱 tint 로 고정한다.
        /// 루트에서 `.tint(...)` 로 한 번 걸고, 직접 그리는 것(선택 테두리 등)에만 이 값을 쓴다.
        /// `Color.accentColor` 는 시스템 강조색이라 여기와 다른 색이 나온다 — 섞어 쓰지 않는다.
        public static let accent = Color(red: 0.176, green: 0.416, blue: 0.333)  // #2D6A55

        /// 실패. 시스템 빨강을 그대로 쓴다.
        /// **진짜 실패에만** 쓴다 — AI 미연결 · 대기 · 멈춤은 실패가 아니다 (AGENTS.md §1-6).
        public static let failure = Color.red

        /// 사람이 손대야 진행되는 상태 (멈춤 · 저장 공간 부족).
        public static let attention = Color.orange

        /// 지금 잘 돌아가는 중 (AI 연결됨 · iCloud 맞춰짐).
        public static let ok = Color.green

        /// 썸네일 · 미리보기가 아직 없을 때 자리만 잡는 면.
        public static let placeholder = Color(nsColor: .quaternarySystemFill)
    }

    /// 장면 역할 색. **커스텀이 아니다** — 시스템 색을 역할에 배정만 했다.
    /// 색은 "구분"용이고 의미는 항상 글자(`Copy.Role`)가 같이 말한다. 색맹 사용자를 위해
    /// 색만으로 정보를 주지 않는다.
    public enum RoleTint {
        public static let hook = Color.pink
        public static let demo = Color.blue
        public static let explain = Color.green
        public static let cta = Color.purple
        public static let filler = Color.secondary
    }

    // MARK: - 간격

    /// SwiftUI 기본 간격(8pt 격자)에 이름을 붙인 것. 새 숫자를 만들지 않는다.
    public enum Space {
        public static let hairline: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let inner: CGFloat = 8
        public static let between: CGFloat = 12
        public static let section: CGFloat = 16
        public static let page: CGFloat = 20
    }

    // MARK: - 모서리

    public enum Radius {
        /// 썸네일 · 장면 카드. macOS 의 파일 아이콘 · 사진 앱 썸네일과 같은 급.
        public static let thumbnail: CGFloat = 6
        /// 정보 카드 · 채팅 말풍선.
        public static let card: CGFloat = 10
    }

    // MARK: - 치수

    /// **커스텀인 이유**: 결과물이 9:16 세로 영상으로 고정이라 썸네일 비율이 화면 문법이 된다
    /// (AGENTS.md §5 `size` 1080x1920). 가로 썸네일로 그리면 결과가 가로인 줄 안다.
    public enum Ratio {
        public static let vertical: CGFloat = 9.0 / 16.0
    }

    public enum Size {
        /// 갤러리 그리드 한 칸의 **바라는** 폭. 이 값으로 칸 수를 세고, 칸은 남는 폭을 나눠 갖는다
        /// (`GalleryScreen.columnCount`). 최소는 4칸이라 1100pt 창에서는 이보다 좁아진다.
        /// **커스텀인 이유**: 세로 칸이라 한 줄에 적게 놓으면 한 화면에 몇 개 안 보인다.
        public static let gridItemIdeal: CGFloat = 170

        /// 오른쪽 정보 패널 · 채팅 패널 폭. `Inspector` 기본값이 좁아 세로 미리보기가 눌린다.
        public static let inspectorIdeal: CGFloat = 280
        public static let inspectorMin: CGFloat = 240

        /// 창 최소 크기. 1100×700 에서 깨지지 않는지 항상 확인한다 (design-ai 지침).
        public static let windowMin = CGSize(width: 1100, height: 700)
        public static let windowIdeal = CGSize(width: 1440, height: 900)

        /// 첫 실행 창. 고정 크기 (`docs/design/screens/`).
        public static let onboarding = CGSize(width: 720, height: 540)
    }
}
