import Foundation

/// `#Preview` 전용 가짜 데이터. **앱 코드에서 부르지 않는다.**
///
/// 제목은 실제 채널 느낌으로 적는다. "샘플 영상 1" 로 두면 글자가 짧아서
/// 줄바꿈 · 말줄임이 어디서 깨지는지 안 보인다.
///
/// 썸네일은 두 군데서 읽는다. **촬영본과 결과물은 그림이 달라야 한다.**
///
/// - 촬영본(`shotFrame`) → `docs/design/sample-frames/`. **자막이 없다.**
///   공개본 프레임은 전부 자막이 박혀 있어서, 자막 아래끝이 0.235 인 편들만 골라
///   위 70% 만 잘라 뒀다 (`docs/findings/2026-09-25-caption-position-10.md`)
/// - 결과물(`resultFrame`) → `reference/`. **자막이 있다.** 그게 결과물이다
///
/// 이 구분이 없으면 미리보기에서 "원본" 과 "만든 것" 이 같아 보인다.
/// 프리뷰 편의이지 앱 동작이 아니다 — 개발이 붙을 때 프록시 · 결과물 그림 URL 로 바뀐다.
public enum SampleData {

    // MARK: - 그림

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Preview
            .deletingLastPathComponent()  // UI
            .deletingLastPathComponent()  // Madi
            .deletingLastPathComponent()  // repo
    }

    private static func file(_ path: String) -> Thumbnail {
        let url = repoRoot.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path)
            ? Thumbnail(fileURL: url) : .none
    }

    /// 촬영본 — 자막 없는 원본처럼 보이는 그림.
    public static func shotFrame(_ id: String) -> Thumbnail {
        file("docs/design/sample-frames/shot-\(id).jpg")
    }

    /// 결과물 — 자막이 박힌 완성본 프레임.
    public static func resultFrame(_ name: String) -> Thumbnail {
        file("reference/\(name)")
    }

    // MARK: - 시각

    /// 프리뷰가 언제 돌아도 같은 그림이 나오도록 "오늘 오후 2:14" 를 고정으로 만든다.
    public static func today(_ hour: Int, _ minute: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    public static func daysAgo(_ days: Int, _ hour: Int, _ minute: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: - 결과물

    public static let results: [ResultRef] = [
        ResultRef(
            id: "o_01", platform: .reels, planLabel: "편집안 2", when: "오늘 오후 2:40",
            duration: 37, sceneCount: 7, isNew: true,
            thumbnail: resultFrame("yt_11s.png")
        ),
        ResultRef(
            id: "o_02", platform: .shorts, planLabel: "편집안 2", when: "오늘 오후 2:44",
            duration: 37, sceneCount: 7, isNew: true,
            thumbnail: resultFrame("yt_13s.png")
        ),
        ResultRef(
            id: "o_03", platform: .reels, planLabel: "편집안 1", when: "어제 오후 6:02",
            duration: 42, sceneCount: 9,
            thumbnail: resultFrame("yt_9s.png")
        ),
    ]

    // MARK: - 촬영본

    public static let shotsToday: [ShotItem] = [
        ShotItem(
            id: "v_01",
            title: "골반이 틀어져있다면, 이 동작 안되실걸요?",
            shotAt: today(14, 14), duration: 42, speech: .clear,
            thumbnail: shotFrame("v_01"), results: results
        ),
        ShotItem(
            id: "v_02",
            title: "거북목 스트레칭, 하루 3번이면 충분합니다",
            shotAt: today(14, 31), duration: 38, speech: .clear,
            thumbnail: shotFrame("v_02")
        ),
        ShotItem(
            id: "v_03",
            title: "라운드숄더 자가 체크 먼저 해보세요",
            shotAt: today(14, 48), duration: 51, speech: .silent, isMaking: true,
            thumbnail: shotFrame("v_03")
        ),
    ]

    public static let shotsThisWeek: [ShotItem] = [
        ShotItem(
            id: "v_04",
            title: "허리 아플 때 폼롤러 이렇게 쓰세요",
            shotAt: daysAgo(2, 11, 20), duration: 64, speech: .clear,
            thumbnail: shotFrame("v_04"),
            results: [
                ResultRef(id: "o_11", platform: .shorts, planLabel: "편집안 2",
                          when: "이틀 전", duration: 48, sceneCount: 8),
                ResultRef(id: "o_12", platform: .shorts, planLabel: "편집안 1",
                          when: "이틀 전", duration: 58, sceneCount: 9),
            ]
        ),
        ShotItem(
            id: "v_05",
            title: "고관절 가동성 루틴 3분",
            shotAt: daysAgo(2, 15, 2), duration: 176, speech: .noisy,
            thumbnail: shotFrame("v_05"),
            results: [
                ResultRef(id: "o_13", platform: .reels, planLabel: "편집안 1",
                          when: "이틀 전", duration: 44, sceneCount: 7),
            ]
        ),
        ShotItem(
            id: "v_06",
            title: "펴진 자세 배에 두툼이 빠르게된",
            shotAt: daysAgo(3, 9, 40), duration: 36, speech: .clear,
            thumbnail: shotFrame("v_06")
        ),
        ShotItem(
            id: "v_07",
            title: "굽은 등, 벽 하나로 펴는 방법",
            shotAt: daysAgo(3, 13, 12), duration: 44, speech: .clear,
            thumbnail: shotFrame("v_07"),
            results: [
                ResultRef(id: "o_14", platform: .reels, planLabel: "편집안 3",
                          when: "사흘 전", duration: 31, sceneCount: 6),
            ]
        ),
        ShotItem(
            id: "v_08",
            title: "승모근이 솟았다면 이것부터",
            shotAt: daysAgo(4, 17, 5), duration: 29, speech: .clear,
            thumbnail: shotFrame("v_08"),
            results: [
                ResultRef(id: "o_15", platform: .shorts, planLabel: "편집안 1",
                          when: "나흘 전", duration: 29, sceneCount: 5),
            ]
        ),
    ]

    public static let shotsLastWeek: [ShotItem] = [
        ShotItem(
            id: "v_09", title: "무릎 통증, 앉는 자세부터 바꾸세요",
            shotAt: daysAgo(9, 10, 30), duration: 58, speech: .clear,
            thumbnail: shotFrame("v_09")
        ),
        ShotItem(
            id: "v_10", title: "발목 접질린 뒤 꼭 해야 하는 것",
            shotAt: daysAgo(9, 16, 18), duration: 47, speech: .noisy,
            thumbnail: shotFrame("v_10")
        ),
        ShotItem(
            id: "v_11", title: "어깨 돌릴 때 소리 나면 보세요",
            shotAt: daysAgo(10, 12, 2), duration: 61, speech: .clear,
            thumbnail: shotFrame("v_11")
        ),
    ]

    public static let groups: [ShotGroup] = [
        ShotGroup(title: Copy.Gallery.Group.today,
                  subtitle: Copy.day(Date()), shots: shotsToday),
        ShotGroup(title: Copy.Gallery.Group.thisWeek,
                  subtitle: "\(Copy.day(daysAgo(4, 12, 0)))–\(Copy.day(daysAgo(2, 12, 0)))",
                  shots: shotsThisWeek),
        ShotGroup(title: Copy.Gallery.Group.lastWeek,
                  subtitle: "\(Copy.day(daysAgo(10, 12, 0)))–\(Copy.day(daysAgo(9, 12, 0)))",
                  shots: shotsLastWeek),
    ]

    /// 가져오는 중: 앞 3개만 들어와 있고 나머지는 아직.
    public static let importingGroups: [ShotGroup] = [
        ShotGroup(title: Copy.Gallery.Group.today,
                  subtitle: Copy.day(Date()), shots: Array(shotsToday.prefix(3)))
    ]

    // MARK: - 스튜디오

    /// 사이드바 숫자는 위 샘플과 **맞아야** 한다. 사이드바가 24 인데 화면에 11개면
    /// 스크린샷을 보는 사람이 "필터가 걸렸나" 를 먼저 의심하게 된다.
    public static let studio = StudioStatus(
        studioName: "바른몸 스튜디오", ai: .claude,
        shotCount: groups.reduce(0) { $0 + $1.shots.count },
        resultCount: groups.flatMap(\.shots).reduce(0) { $0 + $1.results.count },
        makingCount: groups.flatMap(\.shots).filter(\.isMaking).count
    )

    public static let studioEmpty = StudioStatus(
        studioName: "바른몸 스튜디오", ai: .claude,
        shotCount: 0, resultCount: 0, makingCount: 0
    )

    public static let studioNoAI = StudioStatus(
        studioName: "바른몸 스튜디오", ai: .none,
        shotCount: studio.shotCount, resultCount: studio.resultCount, makingCount: 0
    )
}
