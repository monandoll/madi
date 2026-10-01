import Foundation

/// 사람이 장면 카드에서 직접 고친 것 (ViewData `UIAction.scene` · `.plan(.moveScenes)`, docs/stage-6.spec.md).
///
/// - 고친 편집안은 새 편집안이다 (`revisionOf`, §5 · §10). 출처는 `chat`(사람이 고친 판). 예외는 아래 "한 판"
/// - 원본 구간이 바뀐 장면은 자막을 전사에서 **다시 채운다** (분절은 템플릿 값, `CaptionFiller`). 글자가 그대로인 덩어리는
///   영문도 그대로 둔다 — 새로 들어온 말의 덩어리만 영문이 빈다 (다음 채팅 수정에서 AI 가 채운다).
///   전에는 1초만 늘려도 그 장면의 영문이 **전부** 지워졌다 (2026-09-30 실제 앱)
/// - 자막 고치기에서 영문을 주지 않으면(nil) 영문은 그대로다. 카드에는 영문 칸이 없고, 목록도 영문을 안 건드리면 nil 을 준다 —
///   전에는 nil 이 "지운다" 여서 본문만 고쳐도 영문이 사라졌다
/// - 사람이 고친 자막 글자는 그대로 둔다 (전사 오타 고치기)
/// - **바뀌는 것이 없으면 새 편집안을 만들지 않는다** (`Failure.noChange`) — 영상 끝에 붙은 장면을 "늘리기" 할 때마다
///   똑같은 "편집안 N" 이 쌓였다 (2026-09-30 실제 앱 DB: 내용이 같은 판 28개)
/// - **만들기 전까지 손으로 고친 것은 한 판이다** (2026-10-02 사용자 결정) — 손으로 고친 판을 또 고치면 같은 id 로 제자리에서 고친다
///   (`newID == comp.id`, 언제 되는지는 `AppDatabase.canEditInPlace`). 전에는 "+ 늘리기" 를 연달아 누르자 9초에 편집안이 7개 생겼다
public enum SceneEdit: Hashable, Sendable {
    case remove(sceneID: String)
    case extend(sceneID: String, seconds: Double)
    case shorten(sceneID: String, seconds: Double)
    /// 이 장면 뒤에 뺀 쉬는 구간을 되살린다 — 끝을 다음 장면 시작까지 늘린다 (원본에서 이어진 두 장면일 때만)
    case restoreGap(sceneID: String)
    case move(from: IndexSet, to: Int)
    case editCaption(sceneID: String, text: String, secondary: String?)
}

public enum SceneEdits {

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case noScene(String)
        case lastScene
        case tooShort
        case noChange
        public var description: String {
            switch self {
            case .noScene(let id): "장면이 없다: \(id)"
            case .lastScene: "장면이 하나뿐이라 뺄 수 없다"
            case .tooShort: "장면이 너무 짧아진다"
            case .noChange: "바뀌는 것이 없다"
            }
        }
    }

    /// 장면 최소 길이 (초). 이보다 짧아지는 줄이기는 거절한다.
    public static let minSceneSec = 0.5

    /// 사람이 고친 판의 id. 손으로 고친 판인지는 이 앞머리로 가린다 — AI 판(`draft_` …)과 출처(`chat`)가 같다.
    public static func newID(videoID: String) -> String { "edit_\(videoID)_\(UUID().uuidString.prefix(8))" }
    public static func isHandEdit(_ compositionID: String) -> Bool { compositionID.hasPrefix("edit_") }

    /// 고친 편집안. `newID` 로 저장한다 — 저장은 부르는 쪽이 한다 (`origin: .chat`).
    /// `newID` 가 `comp.id` 와 같으면 제자리 고치기다 — 이전 판(`revisionOf`) · 만든 때를 그대로 둔다 (판 번호가 바뀌지 않게).
    public static func apply(
        _ edit: SceneEdit, to comp: Composition, newID: String, words: [Word],
        style: StyleValues.CaptionValues, sourceDuration: Double?
    ) throws -> Composition {
        var c = comp
        let inPlace = newID == comp.id
        func index(_ id: String) throws -> Int {
            guard let i = c.scenes.firstIndex(where: { $0.id == id }) else { throw Failure.noScene(id) }
            return i
        }
        var refill: Set<String> = []
        switch edit {
        case .remove(let id):
            guard c.scenes.count > 1 else { throw Failure.lastScene }
            c.scenes.remove(at: try index(id))
        case .extend(let id, let sec):
            let i = try index(id)
            // 다른 장면이 쓰는 원본 구간에서 멈춘다 — 넘으면 같은 말이 두 장면에 두 번 나온다 (2026-09-30 실제 앱:
            // 첫 장면을 늘리자 다음 장면의 "두 날개뼈" 가 겹쳤다. 크리에이터 30편은 같은 말을 두 번 쓴 편이 0편)
            let me = c.scenes[i].source
            let nextStart = c.scenes.filter { $0.id != id && $0.source.videoID == me.videoID && $0.source.start >= me.end - 0.001 }
                .map(\.source.start).min() ?? .infinity
            let limit = min(sourceDuration ?? .infinity, nextStart)
            // 이미 원본 끝에 닿은 장면은 늘릴 수 없다. 끝이 원본보다 조금 넘어 있어도(60.08 / 60.00) 줄이지 않는다
            let end = min(c.scenes[i].source.end + sec, limit)
            guard end > c.scenes[i].source.end + 0.001 else { throw Failure.noChange }
            c.scenes[i].source.end = end
            refill.insert(id)
        case .shorten(let id, let sec):
            let i = try index(id)
            let end = c.scenes[i].source.end - sec
            guard end - c.scenes[i].source.start >= minSceneSec else { throw Failure.tooShort }
            c.scenes[i].source.end = end
            refill.insert(id)
        case .restoreGap(let id):
            let i = try index(id)
            guard i + 1 < c.scenes.count, c.scenes[i + 1].source.videoID == c.scenes[i].source.videoID,
                  c.scenes[i + 1].source.start > c.scenes[i].source.end else { throw Failure.noChange }
            c.scenes[i].source.end = c.scenes[i + 1].source.start
            refill.insert(id)
        case .move(let from, let to):
            var scenes = c.scenes
            let moving = from.sorted().map { scenes[$0] }
            for i in from.sorted(by: >) { scenes.remove(at: i) }
            let target = to - from.filter { $0 < to }.count
            scenes.insert(contentsOf: moving, at: min(max(target, 0), scenes.count))
            c.scenes = scenes
        case .editCaption(let id, let text, let secondary):
            let i = try index(id)
            guard !c.scenes[i].captions.isEmpty else { throw Failure.noChange }
            c.scenes[i].captions[0].text = text
            if let secondary { c.scenes[i].captions[0].secondary = secondary }
        }
        c = Composition(
            id: newID, videoID: c.videoID, templateID: c.templateID, templateVersion: c.templateVersion,
            style: c.style, size: c.size, fps: c.fps, meta: c.meta, captionSlot: c.captionSlot,
            scenes: c.scenes, audio: c.audio,
            revisionOf: inPlace ? comp.revisionOf : comp.id, createdAt: inPlace ? comp.createdAt : Date()
        )
        if !refill.isEmpty {
            // 바뀐 장면만 다시 채운다. 다른 장면의 자막 · 영문은 그대로
            var only = c
            only.scenes = c.scenes.filter { refill.contains($0.id) }
            CaptionFiller.snapToWords(&only, words: words)
            _ = CaptionFiller.fill(&only, words: words, style: style, translations: [])
            for s in only.scenes {
                if let i = c.scenes.firstIndex(where: { $0.id == s.id }) {
                    // 글자가 그대로인 덩어리는 영문을 지킨다 (같은 글자가 여럿이면 앞에서부터 차례로)
                    var old = c.scenes[i].captions.filter { $0.secondary != nil }
                    var refilled = s.captions
                    for k in refilled.indices {
                        if let j = old.firstIndex(where: { $0.text == refilled[k].text }) {
                            refilled[k].secondary = old[j].secondary
                            old.remove(at: j)
                        }
                    }
                    c.scenes[i].source = s.source
                    c.scenes[i].captions = refilled
                    c.scenes[i].reframe = ReframeTrack()      // 구간이 바뀌면 화면 잡기도 다시
                }
            }
            // 낱말 경계에 맞추고 나니 구간이 제자리로 돌아왔다 — 자막만 다시 채운 판을 만들지 않는다
            if refill.allSatisfy({ id in c.scenes.first { $0.id == id }?.source == comp.scenes.first { $0.id == id }?.source }) {
                throw Failure.noChange
            }
        }
        guard !sameContent(c, comp) else { throw Failure.noChange }
        return c
    }

    /// 보이는 것이 같은가 — 장면 순서 · 구간 · 역할 · 자막 · 자막 자리. 화면 잡기 좌표는 렌더가 다시 채우므로 보지 않는다.
    static func sameContent(_ a: Composition, _ b: Composition) -> Bool {
        func visible(_ scenes: [Scene]) -> [Scene] { scenes.map { var s = $0; s.reframe = ReframeTrack(); return s } }
        return a.captionSlot == b.captionSlot && visible(a.scenes) == visible(b.scenes)
    }
}
