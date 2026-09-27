import Foundation

/// 사람이 장면 카드에서 직접 고친 것 (ViewData `UIAction.scene` · `.plan(.moveScenes)`, docs/stage-6.spec.md).
///
/// - 고친 편집안은 **항상 새 편집안**이다 (`revisionOf`, §5 · §10). 출처는 `chat`(사람이 고친 판)
/// - 원본 구간이 바뀐 장면은 자막을 전사에서 **다시 채운다** (분절은 템플릿 값, `CaptionFiller`). 그 장면의 영문은 비운다 —
///   문장 번역을 덩어리에 나눈 것이라 구간이 바뀌면 맞지 않는다. 다음 채팅 수정에서 AI 가 다시 맞춘다
/// - 사람이 고친 자막 글자는 그대로 둔다 (전사 오타 고치기)
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
        public var description: String {
            switch self {
            case .noScene(let id): "장면이 없다: \(id)"
            case .lastScene: "장면이 하나뿐이라 뺄 수 없다"
            case .tooShort: "장면이 너무 짧아진다"
            }
        }
    }

    /// 장면 최소 길이 (초). 이보다 짧아지는 줄이기는 거절한다.
    public static let minSceneSec = 0.5

    /// 고친 새 편집안. `newID` 로 저장한다 — 저장은 부르는 쪽이 한다 (`origin: .chat`).
    public static func apply(
        _ edit: SceneEdit, to comp: Composition, newID: String, words: [Word],
        style: StyleValues.CaptionValues, sourceDuration: Double?
    ) throws -> Composition {
        var c = comp
        c.revisionOf = comp.id
        c.createdAt = Date()
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
            let limit = sourceDuration ?? .infinity
            c.scenes[i].source.end = min(c.scenes[i].source.end + sec, limit)
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
                  c.scenes[i + 1].source.start > c.scenes[i].source.end else { return c }
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
            guard !c.scenes[i].captions.isEmpty else { return c }
            c.scenes[i].captions[0].text = text
            c.scenes[i].captions[0].secondary = secondary
        }
        c = Composition(
            id: newID, videoID: c.videoID, templateID: c.templateID, templateVersion: c.templateVersion,
            style: c.style, size: c.size, fps: c.fps, meta: c.meta, captionSlot: c.captionSlot,
            scenes: c.scenes, audio: c.audio, revisionOf: comp.id, createdAt: Date()
        )
        if !refill.isEmpty {
            // 바뀐 장면만 다시 채운다. 다른 장면의 자막 · 영문은 그대로
            var only = c
            only.scenes = c.scenes.filter { refill.contains($0.id) }
            CaptionFiller.snapToWords(&only, words: words)
            _ = CaptionFiller.fill(&only, words: words, style: style, translations: [])
            for s in only.scenes {
                if let i = c.scenes.firstIndex(where: { $0.id == s.id }) {
                    c.scenes[i].source = s.source
                    c.scenes[i].captions = s.captions
                    c.scenes[i].reframe = ReframeTrack()      // 구간이 바뀌면 화면 잡기도 다시
                }
            }
        }
        return c
    }
}
