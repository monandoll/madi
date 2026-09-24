import Foundation
import CoreGraphics

/// 영상 편집의 코어 자료구조. AGENTS.md §5.
///
/// 전작(`legacy/v0.2`)의 `Edit` 은 트림 · 컷 · 정적 크롭 · ASS 자막만 표현할 수 있었다.
/// 줌 · BGM · 효과음 · 오버레이 · 훅카드가 **구조적으로** 불가능했고, 그게 결과물이 처참했던
/// 원인이다 (AGENTS.md §0-1). AI 가 똑똑해도 출력 어휘가 없으면 아무것도 못 한다.
///
/// 규칙: 렌더는 항상 `Composition` 으로부터 재현 가능해야 한다 (AGENTS.md §1-8).
///
/// ★ 스타일 값(폰트 · 색 · 글자 크기 · 자막 절대 좌표 · 애니메이션 곡선 · 외곽선 두께)은
///   이 타입에 **없다**. 전부 `templateID` 가 가리키는 템플릿이 정한다 (AGENTS.md §1-2, §9).
///   그런 필드를 추가하자는 제안은 거절한다. 전작 §0-4 가 그렇게 망했다.

// MARK: - 정규화 좌표

/// 0..1 정규화 사각형. 원본 해상도와 무관하게 쓴다.
public struct NormRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    /// 주어진 픽셀 크기 안에서의 실제 사각형.
    public func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }
}

public struct NormPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

// MARK: - 자막

/// 자막 한 덩어리. **문장을 통째로 넣지 않는다.**
/// whisper 문장 세그먼트를 그대로 그린 게 전작이 "자동 생성 자막"처럼 보인 이유다 (AGENTS.md §0-3).
/// 품질 게이트 G5: 한 덩어리 13자 이내, 2줄 이내.
public struct Caption: Codable, Hashable, Sendable {
    public enum Slot: String, Codable, Sendable {
        /// 하단 본문. 대부분의 자막.
        case main
        /// 상단 라벨 (`Before` / `After`). 조사 5편 중 2편에서 관측됐다.
        case top
    }

    /// `text` 안에서 강조할 문자 구간 (반개구간 `[from, to)`).
    /// **색과 굵기는 템플릿이 정한다.** 여기는 "어디를" 만 말한다.
    public struct EmphasisRange: Codable, Hashable, Sendable {
        public var from: Int
        public var to: Int
        public init(from: Int, to: Int) { self.from = from; self.to = to }
    }

    public var id: String
    /// 장면 로컬 초 (`Scene.source.in` 기준 0).
    public var start: Double
    public var end: Double
    /// 2~7자 분절된 한 덩어리.
    public var text: String
    /// 영문 번역 등 보조 문구. 템플릿이 본문 아래에 작게 그린다.
    public var secondary: String?
    public var emphasis: [EmphasisRange]
    public var slot: Slot

    public init(
        id: String,
        start: Double,
        end: Double,
        text: String,
        secondary: String? = nil,
        emphasis: [EmphasisRange] = [],
        slot: Slot = .main
    ) {
        self.id = id; self.start = start; self.end = end
        self.text = text; self.secondary = secondary
        self.emphasis = emphasis; self.slot = slot
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        text = try c.decode(String.self, forKey: .text)
        secondary = try c.decodeIfPresent(String.self, forKey: .secondary)
        emphasis = try c.decodeIfPresent([EmphasisRange].self, forKey: .emphasis) ?? []
        slot = try c.decodeIfPresent(Slot.self, forKey: .slot) ?? .main
    }
}

// MARK: - 오버레이

/// 화면 위에 얹는 것. 물리치료 콘텐츠는 해부학 그림 · 화살표 · 횟수 카운터가 핵심이라
/// 전작처럼 이게 불가능하면 크리에이터 스타일을 절대 못 따라간다.
///
/// `payload` 의 구체 스키마는 템플릿의 `Spec.json` 이 정의한다.
/// 여기서는 kind 별 최소 계약만 강제한다.
public struct Overlay: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case titleCard   // 훅 타이틀
        case arrow       // 방향 지시 (조사 5편 중 2편)
        case circle      // 부위 강조 (조사 5편 중 3편)
        case image       // 해부학 그림 등
        case counter     // 횟수
        case progress    // 진행 바
    }

    public var id: String
    public var kind: Kind
    /// 장면 로컬 초.
    public var start: Double
    public var end: Double
    /// 0..1 정규화.
    public var anchor: NormPoint
    /// kind 별 내용. 스타일 값은 넣지 않는다 (`assertNoStyleValues()` 가 막는다).
    public var payload: [String: JSONValue]

    public init(
        id: String, kind: Kind, start: Double, end: Double,
        anchor: NormPoint, payload: [String: JSONValue] = [:]
    ) {
        self.id = id; self.kind = kind; self.start = start; self.end = end
        self.anchor = anchor; self.payload = payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        anchor = try c.decode(NormPoint.self, forKey: .anchor)
        payload = try c.decodeIfPresent([String: JSONValue].self, forKey: .payload) ?? [:]
    }
}

// MARK: - 리프레이밍

/// 세로(9:16) 변환에서 원본의 어디를 잡을지, **시간에 따라**.
/// 전작은 `cropFocus: Double` 하나로 x 좌표만 고정해서 인물이 화면 구석에 작게 박혔다
/// (AGENTS.md §0-2). 숏폼에서 피사체가 작으면 그 시점에 끝난 영상이다.
public struct ReframeTrack: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// 렌더가 subject 트랙을 보고 키프레임을 채운 뒤 **이 필드에 다시 적는다**
        /// (렌더는 항상 Composition 으로부터 재현 가능해야 하므로). 1단계.
        case auto
        /// `keyframes` 의 첫 항목을 전 구간 고정.
        case fixed
        case keyframes
    }

    public struct Keyframe: Codable, Hashable, Sendable {
        /// 장면 로컬 초.
        public var t: Double
        public var rect: NormRect
        public init(t: Double, rect: NormRect) { self.t = t; self.rect = rect }
    }

    public var mode: Mode
    public var keyframes: [Keyframe]
    /// 피사체 주변 여백 비율. 템플릿의 목표 점유율과 함께 쓴다.
    public var padding: Double

    public init(mode: Mode = .auto, keyframes: [Keyframe] = [], padding: Double = 0.08) {
        self.mode = mode; self.keyframes = keyframes; self.padding = padding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .auto
        keyframes = try c.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 0.08
    }

    /// 시각 `t` 에서 잡을 원본 영역. 키프레임 사이는 선형 보간한다.
    /// (스무딩은 1단계에서 키프레임을 채울 때 하고, 여기서는 하지 않는다 — G3)
    public func rect(at t: Double) -> NormRect? {
        guard !keyframes.isEmpty else { return nil }
        if mode == .fixed { return keyframes[0].rect }
        let sorted = keyframes.sorted { $0.t < $1.t }
        if t <= sorted[0].t { return sorted[0].rect }
        if t >= sorted[sorted.count - 1].t { return sorted[sorted.count - 1].rect }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            guard t >= a.t, t <= b.t else { continue }
            let span = b.t - a.t
            let u = span > 0 ? (t - a.t) / span : 0
            return NormRect(
                x: a.rect.x + (b.rect.x - a.rect.x) * u,
                y: a.rect.y + (b.rect.y - a.rect.y) * u,
                w: a.rect.w + (b.rect.w - a.rect.w) * u,
                h: a.rect.h + (b.rect.h - a.rect.h) * u
            )
        }
        return sorted[sorted.count - 1].rect
    }
}

// MARK: - 장면

/// `role` 은 템플릿이 "어떻게 그릴지"를 고르는 키다. 좌표나 스타일이 아니다.
/// 품질 게이트 G8 은 0~1.5초에 `role == .hook` 장면 또는 titleCard 를 요구한다.
public enum SceneRole: String, Codable, Sendable {
    case hook, demo, explain, cta, filler
}

public enum Transition: String, Codable, Sendable {
    case cut, fade, whip, zoom
}

public struct Scene: Codable, Hashable, Sendable {
    /// 원본 파일의 초.
    ///
    /// ⚠ AGENTS.md §5 미결 1순위: 조사 5편 중 2편이 **이미지가 장면 자체**였다
    /// (검은 배경 + 해부학 그림 + 원 · 화살표). `case image(assetID:duration:)` 가 필요하다.
    /// `docs/findings/2026-09-23-layout-survey.md` 는 **10편까지 세고 나서** 스키마를
    /// 고치라고 적었다. 그 전에 먼저 넣지 않는다 — 1편 보고 고쳤다가 우선순위가 뒤집힌 게
    /// 그 문서가 남긴 교훈이다.
    public struct Source: Codable, Hashable, Sendable {
        public var videoID: String
        /// 원본 초. `in`
        public var start: Double
        /// 원본 초. `out`
        public var end: Double

        public init(videoID: String, start: Double, end: Double) {
            self.videoID = videoID; self.start = start; self.end = end
        }

        private enum CodingKeys: String, CodingKey {
            case videoID = "videoId"
            case start = "in"
            case end = "out"
        }
    }

    public var id: String
    public var role: SceneRole
    public var source: Source
    /// 1 = 원속, 0.5 = 슬로우, 1.5 = 빠르게. 결과 길이는 `(end - start) / speed`.
    public var speed: Double
    public var reframe: ReframeTrack
    public var captions: [Caption]
    public var overlays: [Overlay]
    public var transitionIn: Transition

    public init(
        id: String, role: SceneRole, source: Source,
        speed: Double = 1,
        reframe: ReframeTrack = ReframeTrack(),
        captions: [Caption] = [], overlays: [Overlay] = [],
        transitionIn: Transition = .cut
    ) {
        self.id = id; self.role = role; self.source = source; self.speed = speed
        self.reframe = reframe; self.captions = captions; self.overlays = overlays
        self.transitionIn = transitionIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = try c.decode(SceneRole.self, forKey: .role)
        source = try c.decode(Source.self, forKey: .source)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        reframe = try c.decodeIfPresent(ReframeTrack.self, forKey: .reframe) ?? ReframeTrack()
        captions = try c.decodeIfPresent([Caption].self, forKey: .captions) ?? []
        overlays = try c.decodeIfPresent([Overlay].self, forKey: .overlays) ?? []
        transitionIn = try c.decodeIfPresent(Transition.self, forKey: .transitionIn) ?? .cut
    }

    /// 장면의 결과물 길이(초). `speed` 반영.
    public var duration: Double { (source.end - source.start) / speed }
}

// MARK: - 오디오

public struct AudioTracks: Codable, Hashable, Sendable {
    public struct BGM: Codable, Hashable, Sendable {
        public var assetID: String
        public var gainDb: Double
        /// 말하는 구간에서 추가로 낮출 양. 품질 게이트 G12.
        public var duckDb: Double

        public init(assetID: String, gainDb: Double = -22, duckDb: Double = -6) {
            self.assetID = assetID; self.gainDb = gainDb; self.duckDb = duckDb
        }

        private enum CodingKeys: String, CodingKey {
            case assetID = "assetId", gainDb, duckDb
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            assetID = try c.decode(String.self, forKey: .assetID)
            gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb) ?? -22
            duckDb = try c.decodeIfPresent(Double.self, forKey: .duckDb) ?? -6
        }
    }

    public struct SFX: Codable, Hashable, Sendable {
        public var assetID: String
        /// 컴포지션 전체 타임라인 기준 초.
        public var at: Double
        public var gainDb: Double

        public init(assetID: String, at: Double, gainDb: Double = -8) {
            self.assetID = assetID; self.at = at; self.gainDb = gainDb
        }

        private enum CodingKeys: String, CodingKey {
            case assetID = "assetId", at, gainDb
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            assetID = try c.decode(String.self, forKey: .assetID)
            at = try c.decode(Double.self, forKey: .at)
            gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb) ?? -8
        }
    }

    public var bgm: BGM?
    public var sfx: [SFX]

    public init(bgm: BGM? = nil, sfx: [SFX] = []) { self.bgm = bgm; self.sfx = sfx }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bgm = try c.decodeIfPresent(BGM.self, forKey: .bgm)
        sfx = try c.decodeIfPresent([SFX].self, forKey: .sfx) ?? []
    }
}

// MARK: - 컴포지션

public enum Platform: String, Codable, Sendable {
    case reels, shorts, tiktok
}

public struct Composition: Codable, Hashable, Sendable {
    public struct Size: Codable, Hashable, Sendable {
        public var w: Int
        public var h: Int
        public init(w: Int = 1080, h: Int = 1920) { self.w = w; self.h = h }
        public var cgSize: CGSize { CGSize(width: w, height: h) }
    }

    public struct Meta: Codable, Hashable, Sendable {
        public var title: String
        public var platform: Platform
        /// 품질 게이트 G11 이 ±15% 로 검사한다.
        public var targetDurationSec: Double

        public init(title: String = "", platform: Platform = .reels, targetDurationSec: Double) {
            self.title = title; self.platform = platform; self.targetDurationSec = targetDurationSec
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            platform = try c.decodeIfPresent(Platform.self, forKey: .platform) ?? .reels
            targetDurationSec = try c.decode(Double.self, forKey: .targetDurationSec)
        }
    }

    public var id: String
    public var videoID: String
    /// `Madi/Templates/<templateID>`. 스타일은 전부 여기 있다.
    public var templateID: String
    public var templateVersion: Int
    public var size: Size
    public var fps: Int
    public var meta: Meta
    /// 배열 순서 = 결과물 순서. 원본 순서와 달라도 된다.
    public var scenes: [Scene]
    public var audio: AudioTracks
    /// 결과물이 있는 컴포지션은 제자리에서 고치지 않는다. 새 것을 만들고 여기에 이전 id 를 적는다.
    public var revisionOf: String?
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case videoID = "videoId"
        case templateID = "templateId"
        case templateVersion, size, fps, meta, scenes, audio, revisionOf, createdAt
    }

    public init(
        id: String, videoID: String, templateID: String, templateVersion: Int = 1,
        size: Size = Size(), fps: Int = 30, meta: Meta, scenes: [Scene],
        audio: AudioTracks = AudioTracks(), revisionOf: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id; self.videoID = videoID; self.templateID = templateID
        self.templateVersion = templateVersion; self.size = size; self.fps = fps
        self.meta = meta; self.scenes = scenes; self.audio = audio
        self.revisionOf = revisionOf; self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        videoID = try c.decode(String.self, forKey: .videoID)
        templateID = try c.decode(String.self, forKey: .templateID)
        templateVersion = try c.decodeIfPresent(Int.self, forKey: .templateVersion) ?? 1
        size = try c.decodeIfPresent(Size.self, forKey: .size) ?? Size()
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        meta = try c.decode(Meta.self, forKey: .meta)
        scenes = try c.decode([Scene].self, forKey: .scenes)
        audio = try c.decodeIfPresent(AudioTracks.self, forKey: .audio) ?? AudioTracks()
        revisionOf = try c.decodeIfPresent(String.self, forKey: .revisionOf)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// 결과물 전체 길이(초).
    public var duration: Double { scenes.reduce(0) { $0 + $1.duration } }

    /// 각 장면이 결과물 타임라인에서 시작하는 초.
    public var sceneOffsets: [Double] {
        var out: [Double] = []
        var t = 0.0
        for s in scenes { out.append(t); t += s.duration }
        return out
    }
}

// MARK: - 검증

public struct CompositionError: Error, CustomStringConvertible {
    public let problems: [String]
    public var description: String {
        "컴포지션이 올바르지 않습니다:\n" + problems.map { "  - \($0)" }.joined(separator: "\n")
    }
}

/// AI 가 스타일 값을 밀어 넣으려는 시도를 잡는다 (AGENTS.md §5).
///
/// 타입만으로는 `payload` 안쪽을 못 막으므로 한 번 더 훑는다. 중첩된 오브젝트·배열도 들어간다.
/// 전작 §0-4 는 "스타일을 자연어로 두고 AI 가 매번 해석"해서 같은 요청에 매번 다른 결과가 나왔다.
/// 이 함수가 그 길을 물리적으로 막는다.
private let forbiddenStyleKeys: Set<String> = [
    "font", "fontfamily", "fontsize", "fontweight", "weight",
    "color", "colour", "background", "backgroundcolor", "boxcolor",
    "outline", "outlinecolor", "outlinewidth", "stroke", "strokecolor", "strokewidth",
    "bold", "italic", "opacity", "easing", "shadow",
    "x", "y", "top", "bottom", "left", "right",
]

public func assertNoStyleValues(_ comp: Composition) throws {
    var bad: [String] = []

    func walk(_ value: JSONValue, path: String) {
        switch value {
        case .object(let dict):
            for (k, v) in dict {
                if forbiddenStyleKeys.contains(k.lowercased()) {
                    bad.append("\(path).\(k)")
                }
                walk(v, path: "\(path).\(k)")
            }
        case .array(let items):
            for (i, v) in items.enumerated() { walk(v, path: "\(path)[\(i)]") }
        default:
            break
        }
    }

    for (si, scene) in comp.scenes.enumerated() {
        for (oi, overlay) in scene.overlays.enumerated() {
            let base = "scenes[\(si)].overlays[\(oi)].payload"
            for (k, v) in overlay.payload {
                if forbiddenStyleKeys.contains(k.lowercased()) { bad.append("\(base).\(k)") }
                walk(v, path: "\(base).\(k)")
            }
        }
    }

    guard bad.isEmpty else {
        throw CompositionError(problems:
            ["스타일 값은 Composition 에 넣을 수 없습니다. 템플릿이 정합니다 (AGENTS.md §1-2)."]
            + bad.sorted()
        )
    }
}

/// 구조 검증. 파싱만으로는 못 잡는 것들.
public func validate(_ comp: Composition) throws {
    var problems: [String] = []

    if comp.templateID.isEmpty { problems.append("templateId 가 비어 있다") }
    if comp.scenes.isEmpty { problems.append("scenes 가 비어 있다") }
    if comp.size.w <= 0 || comp.size.h <= 0 { problems.append("size 가 0 이하다") }
    if comp.fps < 24 || comp.fps > 60 { problems.append("fps \(comp.fps) 는 24~60 밖이다") }
    if comp.meta.targetDurationSec <= 0 { problems.append("meta.targetDurationSec 가 0 이하다") }

    for (si, scene) in comp.scenes.enumerated() {
        let at = "scenes[\(si)]"
        if scene.source.end <= scene.source.start {
            problems.append("\(at).source: out(\(scene.source.end)) 이 in(\(scene.source.start)) 보다 뒤여야 한다")
        }
        if scene.source.start < 0 { problems.append("\(at).source.in 이 음수다") }
        if scene.speed < 0.25 || scene.speed > 4 {
            problems.append("\(at).speed \(scene.speed) 는 0.25~4 밖이다")
        }
        if scene.reframe.mode != .auto && scene.reframe.keyframes.isEmpty {
            problems.append("\(at).reframe: mode 가 auto 가 아니면 keyframes 가 있어야 한다")
        }
        if scene.reframe.padding < 0 || scene.reframe.padding > 0.5 {
            problems.append("\(at).reframe.padding 이 0~0.5 밖이다")
        }

        let sceneDuration = scene.duration
        for (ci, cap) in scene.captions.enumerated() {
            let cat = "\(at).captions[\(ci)]"
            if cap.end <= cap.start {
                problems.append("\(cat): end(\(cap.end)) 가 start(\(cap.start)) 보다 뒤여야 한다")
            }
            if cap.start < 0 { problems.append("\(cat).start 가 음수다") }
            if cap.end > sceneDuration + 0.001 {
                problems.append("\(cat).end(\(cap.end)) 가 장면 길이(\(sceneDuration)) 를 넘는다")
            }
            if cap.text.isEmpty { problems.append("\(cat).text 가 비어 있다") }
            let n = cap.text.count
            for (ei, e) in cap.emphasis.enumerated() {
                if e.to <= e.from || e.from < 0 || e.to > n {
                    problems.append("\(cat).emphasis[\(ei)] 구간 \(e.from)..<\(e.to) 가 text 범위(0..<\(n)) 밖이다")
                }
            }
        }

        for (oi, ov) in scene.overlays.enumerated() {
            let oat = "\(at).overlays[\(oi)]"
            if ov.end <= ov.start {
                problems.append("\(oat): end(\(ov.end)) 가 start(\(ov.start)) 보다 뒤여야 한다")
            }
            if ov.anchor.x < 0 || ov.anchor.x > 1 || ov.anchor.y < 0 || ov.anchor.y > 1 {
                problems.append("\(oat).anchor 가 0..1 밖이다")
            }
        }
    }

    guard problems.isEmpty else { throw CompositionError(problems: problems) }
}

/// 파싱 + 구조 검증 + 스타일 값 검사. 외부에서는 항상 이걸 쓴다.
public func parseComposition(_ data: Data) throws -> Composition {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let comp = try decoder.decode(Composition.self, from: data)
    try validate(comp)
    try assertNoStyleValues(comp)
    return comp
}
