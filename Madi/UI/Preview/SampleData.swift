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

    /// **샘플은 한 곳에서 나온다.** 같은 편집안이 화면마다 다른 길이·장면 수로 나오면
    /// 화면을 보는 사람이 어느 쪽이 맞는지부터 묻게 된다.
    /// 아래 값들은 전부 `planScenes` 에서 계산한다 — 장면을 고치면 같이 움직인다.
    public static let planDuration: Double = planScenes.reduce(0) { $0 + $1.duration }
    public static let planSceneCount: Int = planScenes.count
    /// 촬영본 원본 길이. 갤러리의 `v_01` 과 같아야 한다.
    public static let planSourceDuration: Double = 42

    /// 이전 편집안(편집안 1). 쉬는 구간을 안 뺐고 장면을 안 합쳤다.
    public static let previousPlanDuration: Double = 35
    public static let previousPlanSceneCount: Int = 11

    public static let results: [ResultRef] = [
        ResultRef(
            id: "o_01", platform: .reels, planLabel: Copy.Plan.version(2),
            when: "오늘 오후 2:40",
            duration: planDuration, sceneCount: planSceneCount, isNew: true,
            // 내보낸 것은 줄에 한 줄로 남긴다 — "이거 올렸었나" 를 묻지 않게.
            exportedNote: Copy.Results.Export.historyLine(
                target: Copy.Results.Export.photos, when: "오후 2:52"
            ),
            thumbnail: resultFrame("yt_11s.png")
        ),
        ResultRef(
            id: "o_02", platform: .shorts, planLabel: Copy.Plan.version(2),
            when: "오늘 오후 2:44",
            duration: planDuration, sceneCount: planSceneCount, isNew: true,
            thumbnail: resultFrame("yt_13s.png")
        ),
        ResultRef(
            id: "o_03", platform: .reels, planLabel: Copy.Plan.version(1),
            when: "어제 오후 6:02",
            duration: previousPlanDuration, sceneCount: previousPlanSceneCount,
            thumbnail: resultFrame("yt_9s.png")
        ),
    ]

    // MARK: - 촬영본

    public static let shotsToday: [ShotItem] = [
        ShotItem(
            id: "v_01",
            title: "골반이 틀어져있다면, 이 동작 안되실걸요?",
            shotAt: today(14, 14), duration: planSourceDuration, speech: .clear,
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

    /// 다 만든 직후. **사이드바 결과물 숫자가 하나 늘어난다.**
    public static let studioAfterMake = StudioStatus(
        studioName: studio.studioName, ai: studio.ai,
        shotCount: studio.shotCount,
        resultCount: studio.resultCount + 1,
        makingCount: 0
    )

    public static let studioNoAI = StudioStatus(
        studioName: "바른몸 스튜디오", ai: .none,
        shotCount: studio.shotCount, resultCount: studio.resultCount, makingCount: 0
    )
}

// MARK: - 편집안

extension SampleData {

    /// 공개본 한 편(18.5초 숏츠)을 편집안으로 되짚어 만든 샘플이다.
    ///
    /// **장면 카드의 자막과 그 장면 프레임의 자막이 같다.** 아무 프레임이나 붙이면
    /// 카드에는 "천천히 일어나주시면서" 인데 재생 막대에는 다른 자막이 떠서,
    /// 화면을 보는 사람이 "둘 중 뭐가 맞나" 를 먼저 묻게 된다.
    /// 프레임 속 자막은 크리에이터가 실제로 쓴 것이고 우리가 흉내 내 그린 게 아니다
    /// (design-ai 지침 3 — 영상 안 자막은 디자인 대상이 아니다).
    public static let planScenes: [SceneCardItem] = [
        SceneCardItem(
            id: "s1", number: 1, role: .hook,
            caption: "골반이 틀어지신 분들은", secondary: "If your pelvis is misaligned,",
            duration: 2.4, thumbnail: resultFrame("yt_0_6s.png")
        ),
        SceneCardItem(
            id: "s2", number: 2, role: .hook,
            caption: "이거 안되실걸요?", secondary: "you probably can't do this.",
            duration: 1.8, thumbnail: resultFrame("yt_1_5s.png"),
            removedGapAfter: 2.6
        ),
        SceneCardItem(
            id: "s3", number: 3, role: .demo,
            caption: "양쪽 다리를", secondary: "Position both legs",
            moreCaptions: ["무릎 꿇고 앉아주세요"],
            duration: 3.2, thumbnail: resultFrame("yt_3s.png")
        ),
        SceneCardItem(
            id: "s4", number: 4, role: .demo,
            caption: "천천히 일어나주시면서", secondary: "Slowly stand up,",
            duration: 4.1, thumbnail: resultFrame("yt_5s.png")
        ),
        SceneCardItem(
            id: "s5", number: 5, role: .demo,
            caption: "반대쪽도 똑같이 진행해주세요", secondary: "Repeat on the other side.",
            duration: 3.6, thumbnail: resultFrame("yt_7s.png"),
            removedGapAfter: 2.4
        ),
        SceneCardItem(
            id: "s6", number: 6, role: .explain,
            caption: "양 쪽을 비교해봤을때,", secondary: "Compare both sides.",
            duration: 2.9, thumbnail: resultFrame("yt_11s.png")
        ),
        SceneCardItem(
            id: "s7", number: 7, role: .explain,
            caption: "일어나지 못한다면", secondary: "if you can't stand up,",
            duration: 2.2, thumbnail: resultFrame("yt_13s.png")
        ),
        SceneCardItem(
            id: "s8", number: 8, role: .explain,
            caption: "가능성이 높다는 겁니다", secondary: "it's likely misaligned.",
            duration: 3.4, thumbnail: resultFrame("yt_15s.png")
        ),
        SceneCardItem(
            id: "s9", number: 9, role: .cta,
            caption: "다음 영상으로 해결해보세요", secondary: "Check out the next video!",
            duration: 3.4, thumbnail: resultFrame("yt_17s.png")
        ),
    ]

    public static let plan = PlanView(
        id: "c_02", shotID: "v_01",
        shotTitle: "골반이 틀어져있다면, 이 동작 안되실걸요?",
        platform: .reels,
        versionLabel: Copy.Plan.version(2), versionCount: 2,
        sourceDuration: planSourceDuration, targetDuration: planDuration,
        // 앉아서 말하는 상반신 영상이다 (측정에서 A 무리, 아래끝 0.235).
        captionSlot: .upperBody,
        scenes: planScenes, resultCount: 3
    )

    /// 자막을 위로 올린 편집안. 바닥에서 동작하는 영상은 자막이 동작을 가린다.
    public static let planUpperCaption = PlanView(
        id: "c_03", shotID: "v_04",
        shotTitle: "허리 아플 때 폼롤러 이렇게 쓰세요",
        platform: .shorts,
        versionLabel: Copy.Plan.version(1), versionCount: 1,
        sourceDuration: 64, targetDuration: 48,
        captionSlot: .lowerBody,
        scenes: Array(planScenes.prefix(6)), resultCount: 0
    )

    /// 소리가 없어서 자막을 못 만든 편집안. 장면은 나뉘었는데 자막 자리가 비어 있다.
    /// 대화에서 "자막을 못 만들었어요" 라고 말하면 **목록도 그렇게 보여야** 한다.
    public static let planNoCaptions = PlanView(
        id: "c_10", shotID: "v_03",
        shotTitle: "라운드숄더 자가 체크 먼저 해보세요",
        platform: .reels,
        versionLabel: Copy.Plan.version(1), versionCount: 1,
        sourceDuration: 51, targetDuration: 44,
        captionSlot: .fullBody,
        scenes: (1...5).map { i in
            SceneCardItem(
                id: "n\(i)", number: i,
                role: [SceneRoleKind.hook, .demo, .demo, .explain, .cta][i - 1],
                caption: "",
                duration: [6.2, 11.4, 9.8, 8.6, 7.6][i - 1],
                thumbnail: shotFrame("v_0\(i + 2)")
            )
        },
        resultCount: 0
    )

    public static let prepareSteps: [PrepareStep] = [
        PrepareStep(title: Copy.Plan.Preparing.transcribe, state: .done),
        PrepareStep(title: Copy.Plan.Preparing.split, state: .running, remaining: "20초쯤"),
        PrepareStep(title: Copy.Plan.Preparing.findGaps, state: .waiting),
        PrepareStep(title: Copy.Plan.Preparing.reframe, state: .waiting),
    ]

    // MARK: - 대화

    public static let chat: [ChatMessage] = [
        ChatMessage(id: "m1", kind: .user("쉬는 구간 빼고 인스타용으로 만들어줘"),
                    stamp: "오늘 오후 2:20"),
        ChatMessage(id: "m2", kind: .assistant(
            "42초를 장면 9개로 나눴어요. 훅 2개 · 시범 3개 · 설명 3개 · 마무리 1개예요.")),
        ChatMessage(id: "m3", kind: .assistant(
            "쉬는 구간 2곳, 5초를 뺐습니다. 앉아서 말하는 영상이라 자막은 상반신 자리에 뒀어요.")),
        ChatMessage(id: "m4", kind: .summary(EditSummary(lines: [
            .init(label: "쉬는 구간 2곳", value: "−5초"),
            .init(label: "인스타 규격", value: "세로"),
            .init(label: "길이", value: Copy.Plan.Info.lengthChange(
                from: Copy.duration(planSourceDuration), to: Copy.duration(planDuration)
            )),
        ]))),
    ]

    /// 만드는 중에 오는 대화. 아직 아무것도 못 보여주니 말로만 알린다.
    public static let chatPreparing: [ChatMessage] = [
        ChatMessage(id: "p1", kind: .user("쉬는 구간 빼고 인스타용으로 만들어줘"),
                    stamp: "오늘 오후 2:20"),
        ChatMessage(id: "p2", kind: .assistant(
            "영상을 살펴보고 있어요. 장면을 나눈 다음 쉬는 구간을 찾아볼게요.")),
        ChatMessage(id: "p3", kind: .typing),
    ]

    /// 막힌 경우 — 소리가 없어서 자막을 못 만들었다.
    /// 붉은색을 쓰지 않는다. 대신 **다음 행동**을 준다 (AGENTS.md §1-6).
    public static let chatStuck: [ChatMessage] = [
        ChatMessage(id: "e1", kind: .assistant("51초짜리 영상을 장면 5개로 나눴어요."),
                    stamp: "오늘 오후 3:05"),
        ChatMessage(id: "e2", kind: .user("자막 넣어줘")),
        ChatMessage(id: "e3", kind: .assistant(
            "이 영상은 소리가 없어서 자막을 못 만들었어요. 찍을 때 마이크가 꺼져 있었던 것 같아요.")),
        ChatMessage(id: "e4", kind: .choices([
            ChatChoice(title: "자막 없이 만들기",
                       detail: "동작 위주 영상이면 이대로도 괜찮아요", isPrimary: true),
            ChatChoice(title: "자막 직접 적기", detail: "장면 카드마다 한 줄씩 적으면 돼요"),
            ChatChoice(title: "같은 날 찍은 다른 영상 보기",
                       detail: "오후 2:31에 찍은 영상은 소리가 있어요"),
        ])),
    ]

    /// 품질 게이트가 "판정 불가" 를 낸 경우 (AGENTS.md §8 — 측정 불가가 20% 를 넘으면
    /// 사용자에게 보인다). 실패가 아니라 **확인 못 했다**는 말이라 말투가 다르다.
    public static let chatUnsureReframe: [ChatMessage] = chat + [
        ChatMessage(id: "m5", kind: .assistant(
            "한 가지만 알려드릴게요. 12~19초 구간은 화면에 사람이 거의 안 잡혀서 "
            + "화면 잡기가 잘 됐는지 확인하지 못했어요. 만들고 나서 그 부분만 한번 봐주세요.")),
    ]

    /// 만드는 중. 진행은 화면 위쪽에서 보여주고, 대화는 한 줄만 남긴다.
    public static let makingProgress = MakingProgress(
        fraction: 0.66,
        steps: [
            PrepareStep(title: Copy.Plan.Making.captions, state: .done),
            PrepareStep(title: Copy.Plan.Making.reframe, state: .running),
            PrepareStep(title: Copy.Plan.Making.encode, state: .waiting),
        ],
        remaining: "약 1분"
    )

    public static let chatMaking: [ChatMessage] = chat + [
        ChatMessage(id: "mk1", kind: .user("좋아, 만들어줘"), stamp: "오늘 오후 2:41"),
        ChatMessage(id: "mk2", kind: .assistant("만들기 시작했어요. 다 되면 여기에 올려드릴게요.")),
    ]

    /// 다 만든 뒤. 결과물이 **대화에 카드로** 붙는다.
    public static let chatMade: [ChatMessage] = chat + [
        ChatMessage(id: "mk1", kind: .user("좋아, 만들어줘"), stamp: "오늘 오후 2:41"),
        ChatMessage(id: "mk2", kind: .assistant("만들기 시작했어요. 다 되면 여기에 올려드릴게요.")),
        ChatMessage(id: "mk3", kind: .result(results[0])),
    ]

    public static let chatChips: [String] = [
        Copy.Chat.Chips.cutGaps,
        Copy.Chat.Chips.shorter,
        Copy.Chat.Chips.hookFirst,
        Copy.Chat.Chips.shorts,
    ]
}

// MARK: - 결과물 · 만드는 중

extension SampleData {

    public static let resultGroups: [ResultGroup] = [
        ResultGroup(shotTitle: shotsToday[0].title, items: results),
        ResultGroup(shotTitle: shotsThisWeek[3].title, items: [
            ResultRef(id: "o_14", platform: .reels, planLabel: Copy.Plan.version(3),
                      when: "사흘 전", duration: 31, sceneCount: 6,
                      thumbnail: resultFrame("nCshtY04NiY_12_4s.jpg")),
        ]),
        ResultGroup(shotTitle: shotsThisWeek[0].title, items: [
            ResultRef(id: "o_11", platform: .shorts, planLabel: Copy.Plan.version(2),
                      when: "이틀 전", duration: 48, sceneCount: 8,
                      thumbnail: resultFrame("nCshtY04NiY_3_8s.jpg")),
            ResultRef(id: "o_12", platform: .shorts, planLabel: Copy.Plan.version(1),
                      when: "이틀 전", duration: 58, sceneCount: 9,
                      thumbnail: resultFrame("nCshtY04NiY_9_5s.jpg")),
        ]),
        ResultGroup(shotTitle: shotsThisWeek[1].title, items: [
            ResultRef(id: "o_13", platform: .reels, planLabel: Copy.Plan.version(1),
                      when: "이틀 전", duration: 44, sceneCount: 7,
                      thumbnail: resultFrame("59HP4jxLFeA_11_4s.jpg")),
        ]),
        ResultGroup(shotTitle: shotsThisWeek[4].title, items: [
            ResultRef(id: "o_15", platform: .shorts, planLabel: Copy.Plan.version(1),
                      when: "나흘 전", duration: 29, sceneCount: 5,
                      thumbnail: resultFrame("RnP7b0JFWj4_13_3s.jpg")),
        ]),
    ]

    /// 지금 고른 결과물. 이전 버전과 나란히 본다.
    public static let resultDetail = ResultDetail(
        shotTitle: shotsToday[0].title,
        current: results[0],
        previous: results[2],
        // 합이 맞아야 한다: 0:35 → 0:27 이면 −8초다.
        changes: [
            .init(label: "쉬는 구간 2곳을 뺐어요", value: "−5초"),
            .init(label: "짧은 장면 2개를 앞 장면에 붙였어요", value: "−3초"),
            .init(label: "앉아서 말하는 영상이라 자막을 상반신 자리로 옮겼어요", value: ""),
            .init(label: "인스타 규격으로 화면을 잡았어요", value: "세로"),
        ]
    )

    /// 첫 결과물이라 견줄 이전 버전이 없는 경우.
    public static let resultDetailFirst = ResultDetail(
        shotTitle: shotsThisWeek[3].title,
        current: resultGroups[1].items[0]
    )

    public static let exportTargets: [ExportTarget] = [
        ExportTarget(title: Copy.Results.Export.photos,
                     detail: Copy.Results.Export.photosDetail, symbol: "photo.on.rectangle"),
        ExportTarget(title: Copy.Results.Export.files,
                     detail: Copy.Results.Export.filesDetail, symbol: "folder"),
        ExportTarget(title: Copy.Results.Export.airdrop,
                     detail: Copy.Results.Export.airdropDetail, symbol: "wifi"),
    ]

    // MARK: 만드는 중

    public static let makingJobs: [MakingJob] = [
        MakingJob(
            id: "j1", shotTitle: shotsToday[0].title, platform: .reels,
            planLabel: Copy.Plan.version(2), duration: planDuration,
            thumbnail: resultFrame("yt_11s.png"),
            state: .running(makingProgress)
        ),
        MakingJob(
            id: "j2", shotTitle: shotsToday[0].title, platform: .shorts,
            planLabel: Copy.Plan.version(2), duration: planDuration,
            thumbnail: resultFrame("yt_13s.png"),
            state: .queued(note: Copy.MakingScreen.queuedNote("앞 영상"))
        ),
        MakingJob(
            id: "j3", shotTitle: shotsThisWeek[0].title, platform: .reels,
            planLabel: Copy.Plan.version(1), duration: 48,
            thumbnail: shotFrame("v_04"),
            // 사람이 손대야 진행된다. 이유와 다음 행동을 같이 준다 (AGENTS.md §1-6).
            state: .stopped(
                reason: "Mac 저장 공간이 모자라서 만들다 멈췄어요. "
                    + "2GB 정도만 비워주시면 멈춘 곳부터 이어서 만들게요.",
                actions: [
                    ChatChoice(title: "이어서 만들기", isPrimary: true),
                    ChatChoice(title: "저장 공간 확인하기"),
                ]
            )
        ),
    ]

    public static let doneToday: [DoneItem] = [
        DoneItem(id: "d1", shotTitle: shotsThisWeek[3].title, platform: .reels,
                 when: "오후 1:12", thumbnail: resultFrame("nCshtY04NiY_12_4s.jpg")),
        DoneItem(id: "d2", shotTitle: shotsToday[1].title, platform: .shorts,
                 when: "오전 11:40", thumbnail: resultFrame("lzDW-9ITfWU_4_6s.jpg")),
    ]
}

// MARK: - 첫 실행 · 설정

extension SampleData {

    public static let onboardingStudio = OnboardingState(
        step: .studio, photos: .granted,
        ai: .connected(.claude, account: sampleAccount),
        studioName: studio.studioName
    )

    /// 샘플 계정. **실제 주소를 쓰지 않는다** (`AGENTS.md §1-7`).
    public static let sampleAccount = "creator@example.com"

    public static let settings = SettingsValues(
        ai: .connected(.claude, account: sampleAccount),
        activeAI: .claude,
        studioName: studio.studioName,
        keepDays: 90,
        albumName: nil,
        photos: .granted
    )

    public static let settingsDisconnected = SettingsValues(
        ai: .notPicked,
        activeAI: .claude,
        studioName: Copy.Onboarding.Studio.defaultName,
        keepDays: 90,
        albumName: nil,
        photos: .denied
    )
}

// MARK: - 막힌 것

extension SampleData {

    /// 말을 못 보낸 경우. **쓴 말은 지우지 않는다.**
    /// 붉은색 없이, 왜 안 갔는지와 다음 행동을 준다.
    public static let chatNotSent: [ChatMessage] = chat + [
        ChatMessage(id: "ns1", kind: .userNotSent("30초로 줄여줘"), stamp: "오늘 오후 2:47"),
        ChatMessage(id: "ns2", kind: .assistant(Copy.Chat.NotSent.reason)),
        ChatMessage(id: "ns3", kind: .choices([
            ChatChoice(title: Copy.Chat.NotSent.reconnect,
                       detail: Copy.Chat.NotSent.reconnectDetail, isPrimary: true),
            ChatChoice(title: Copy.Chat.NotSent.later,
                       detail: Copy.Chat.NotSent.laterDetail),
        ])),
    ]

    /// 내보내다 막힌 경우. 결과물 화면에는 채팅이 없어서 화면 위 한 줄로 말한다.
    public static let exportFailedNotice = ScreenNotice(
        message: Copy.Results.Export.failed(Copy.Results.Export.photos)
            + " — " + Copy.Results.Export.failedReason,
        symbol: "exclamationmark.triangle",
        actions: [
            ChatChoice(title: Copy.Results.Export.retry, isPrimary: true),
            ChatChoice(title: Copy.Results.Export.saveToMac),
        ]
    )
}
