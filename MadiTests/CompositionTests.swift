import Testing
import Foundation
@testable import MadiKit

/// `AGENTS.md §5` 코어 자료구조. 파싱 · 길이 · 오프셋 · 스타일값 차단 · 역구간.
///
/// 스타일값 차단 테스트가 여기 있는 이유: 전작은 스타일을 자연어 규칙으로 두고 AI 가 매번
/// 해석하게 했고, 같은 요청에 매번 다른 결과가 나왔다 (§0-4). 타입만으로는 `payload` 안쪽을
/// 못 막으므로 테스트로 못을 박는다.
struct CompositionTests {

    // MARK: - 픽스처

    private func minimalJSON(
        scenes: String = """
        [{
          "id": "s1", "role": "hook",
          "source": { "videoId": "v1", "in": 0, "out": 3 }
        }]
        """
    ) -> Data {
        Data("""
        {
          "id": "c1", "videoId": "v1",
          "templateId": "SuhyunShortV1",
          "meta": { "targetDurationSec": 30 },
          "captionSlot": "upperBody",
          "scenes": \(scenes)
        }
        """.utf8)
    }

    // MARK: - 파싱

    @Test("최소 JSON 이 기본값과 함께 파싱된다")
    func parsesMinimal() throws {
        let comp = try parseComposition(minimalJSON())
        #expect(comp.id == "c1")
        #expect(comp.templateID == "SuhyunShortV1")
        #expect(comp.templateVersion == 1)
        #expect(comp.size.w == 1080 && comp.size.h == 1920)
        #expect(comp.fps == 30)
        #expect(comp.meta.platform == .reels)
        #expect(comp.scenes[0].speed == 1)
        #expect(comp.scenes[0].reframe.mode == .auto)
        #expect(comp.scenes[0].transitionIn == .cut)
        #expect(comp.revisionOf == nil)
    }

    @Test("captionSlot 이 없으면 거절한다")
    func requiresCaptionSlot() {
        // 기본값을 두지 않는다. 안 적으면 조용히 아래에 붙는 게 아니라 에러가 나야 한다 —
        // 공개본 10편에서 자막 위치가 0.235~0.483 으로 갈렸고, 틀리면 화면 25% 아래에 찍힌다
        // (docs/findings/2026-09-25-caption-position-10.md).
        let json = Data("""
        {
          "id": "c1", "videoId": "v1", "templateId": "short",
          "meta": { "targetDurationSec": 30 },
          "scenes": [{ "id": "s1", "role": "hook",
                       "source": { "videoId": "v1", "in": 0, "out": 3 } }]
        }
        """.utf8)
        #expect(throws: (any Error).self) { try parseComposition(json) }
    }

    @Test("장면이 자막 위치를 덮어쓸 수 있다")
    func sceneOverridesCaptionSlot() throws {
        // 웬만하면 영상 단위로 하나다. 크리에이터는 한 영상 안에서 자막을 옮기지 않는다 —
        // 편당 12프레임이 전부 같은 위치였다. 장면이 완전히 다를 때만 덮어쓴다.
        let comp = try parseComposition(minimalJSON(scenes: """
        [{ "id": "a", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 2 } },
         { "id": "b", "role": "demo", "captionSlot": "lowerBody",
           "source": { "videoId": "v1", "in": 2, "out": 4 } }]
        """))
        #expect(comp.captionSlot == .upperBody)
        #expect(comp.captionSlot(for: comp.scenes[0]) == .upperBody)
        #expect(comp.captionSlot(for: comp.scenes[1]) == .lowerBody)
    }

    @Test("JSON 키 이름이 in/out/videoId/templateId 그대로다")
    func usesJSONKeyNames() throws {
        // 스파이크 컴포지션을 손으로 쓰는 사람이 있으므로 키 이름을 Swift 쪽 사정으로 바꾸지 않는다.
        let comp = try parseComposition(minimalJSON())
        let encoded = try JSONEncoder().encode(comp)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["videoId"] != nil)
        #expect(object?["templateId"] != nil)
        let scene = (object?["scenes"] as? [[String: Any]])?.first
        let source = scene?["source"] as? [String: Any]
        #expect(source?["in"] != nil)
        #expect(source?["out"] != nil)
    }

    @Test("라운드트립해도 값이 같다")
    func roundTrips() throws {
        let comp = try parseComposition(minimalJSON(scenes: """
        [{
          "id": "s1", "role": "demo", "speed": 0.5,
          "source": { "videoId": "v1", "in": 2, "out": 8 },
          "reframe": { "mode": "keyframes", "padding": 0.1,
                       "keyframes": [{ "t": 0, "rect": { "x": 0.1, "y": 0, "w": 0.5, "h": 1 } }] },
          "captions": [{ "id": "c", "start": 0, "end": 1, "text": "어깨가", "secondary": "shoulder" }],
          "overlays": [{ "id": "o", "kind": "circle", "start": 0, "end": 1,
                         "anchor": { "x": 0.5, "y": 0.4 }, "payload": { "part": "shoulder" } }]
        }]
        """))
        let data = try JSONEncoder().encode(comp)
        let again = try JSONDecoder().decode(Composition.self, from: data)
        #expect(again == comp)
    }

    // MARK: - 길이와 오프셋

    @Test("장면 길이는 speed 를 반영한다")
    func sceneDurationUsesSpeed() throws {
        let comp = try parseComposition(minimalJSON(scenes: """
        [{ "id": "s1", "role": "demo", "speed": 0.5,
           "source": { "videoId": "v1", "in": 2, "out": 8 } }]
        """))
        // (8 - 2) / 0.5 = 12
        #expect(comp.scenes[0].duration == 12)
        #expect(comp.duration == 12)
    }

    @Test("장면 오프셋은 앞 장면 길이의 누적이다")
    func sceneOffsetsAccumulate() throws {
        let comp = try parseComposition(minimalJSON(scenes: """
        [{ "id": "a", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 2 } },
         { "id": "b", "role": "demo", "speed": 2, "source": { "videoId": "v1", "in": 5, "out": 9 } },
         { "id": "c", "role": "cta", "source": { "videoId": "v1", "in": 0, "out": 1.5 } }]
        """))
        #expect(comp.sceneOffsets == [0, 2, 4])
        #expect(comp.duration == 5.5)
    }

    @Test("배열 순서가 결과물 순서다 — 원본 순서와 달라도 된다")
    func sceneOrderIsOutputOrder() throws {
        let comp = try parseComposition(minimalJSON(scenes: """
        [{ "id": "later", "role": "hook", "source": { "videoId": "v1", "in": 30, "out": 32 } },
         { "id": "earlier", "role": "demo", "source": { "videoId": "v1", "in": 5, "out": 7 } }]
        """))
        #expect(comp.scenes.map(\.id) == ["later", "earlier"])
    }

    // MARK: - 역구간 · 범위

    @Test("out 이 in 보다 앞이면 거절한다")
    func rejectsReversedSource() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 5, "out": 3 } }]
            """))
        }
    }

    @Test("자막 end 가 start 보다 앞이면 거절한다")
    func rejectsReversedCaption() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "captions": [{ "id": "c", "start": 2, "end": 1, "text": "어깨" }] }]
            """))
        }
    }

    @Test("자막이 장면 길이를 넘으면 거절한다")
    func rejectsCaptionPastSceneEnd() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "captions": [{ "id": "c", "start": 0, "end": 9, "text": "어깨" }] }]
            """))
        }
    }

    @Test("강조 구간이 텍스트 밖이면 거절한다")
    func rejectsOutOfBoundsEmphasis() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "captions": [{ "id": "c", "start": 0, "end": 1, "text": "어깨",
                              "emphasis": [{ "from": 0, "to": 9 }] }] }]
            """))
        }
    }

    @Test("auto 가 아닌 리프레임에 키프레임이 없으면 거절한다")
    func rejectsKeyframeModeWithoutKeyframes() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "reframe": { "mode": "keyframes", "keyframes": [] } }]
            """))
        }
    }

    @Test("장면이 없으면 거절한다")
    func rejectsEmptyScenes() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: "[]"))
        }
    }

    // MARK: - 스타일 값 차단 (AGENTS.md §5)

    @Test(
        "payload 에 스타일 키가 있으면 거절한다",
        arguments: [
            "\"fontSize\": 72",
            "\"color\": \"red\"",
            "\"strokeWidth\": 7",
            "\"x\": 0.5",
            "\"opacity\": 0.8",
            "\"easing\": \"easeOut\"",
        ]
    )
    func rejectsStyleValuesInPayload(entry: String) {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "overlays": [{ "id": "o", "kind": "circle", "start": 0, "end": 1,
                              "anchor": { "x": 0.5, "y": 0.5 },
                              "payload": { \(entry) } }] }]
            """))
        }
    }

    @Test("중첩된 payload 안쪽의 스타일 키도 거절한다")
    func rejectsNestedStyleValues() {
        // 타입만으로는 못 막는 자리다. AI 가 한 겹 감싸서 밀어 넣는 걸 막는다.
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "overlays": [{ "id": "o", "kind": "titleCard", "start": 0, "end": 1,
                              "anchor": { "x": 0.5, "y": 0.5 },
                              "payload": { "style": { "look": { "fontFamily": "Pretendard" } } } }] }]
            """))
        }
    }

    @Test("배열 안에 숨긴 스타일 키도 거절한다")
    func rejectsStyleValuesInsideArrays() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "overlays": [{ "id": "o", "kind": "counter", "start": 0, "end": 1,
                              "anchor": { "x": 0.5, "y": 0.5 },
                              "payload": { "steps": [{ "label": "1" }, { "strokeColor": "#000" }] } }] }]
            """))
        }
    }

    @Test("대소문자를 바꿔도 스타일 키는 거절한다")
    func rejectsStyleKeysCaseInsensitively() {
        #expect(throws: CompositionError.self) {
            try parseComposition(minimalJSON(scenes: """
            [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
               "overlays": [{ "id": "o", "kind": "circle", "start": 0, "end": 1,
                              "anchor": { "x": 0.5, "y": 0.5 },
                              "payload": { "FontSize": 72 } }] }]
            """))
        }
    }

    @Test("스타일이 아닌 payload 는 통과한다")
    func allowsContentPayload() throws {
        let comp = try parseComposition(minimalJSON(scenes: """
        [{ "id": "s1", "role": "hook", "source": { "videoId": "v1", "in": 0, "out": 3 },
           "overlays": [{ "id": "o", "kind": "circle", "start": 0, "end": 1,
                          "anchor": { "x": 0.5, "y": 0.5 },
                          "payload": { "part": "shoulder", "emphasis": "high", "count": 3 } }] }]
        """))
        #expect(comp.scenes[0].overlays[0].payload["part"]?.stringValue == "shoulder")
    }

    // MARK: - 리프레임 보간

    @Test("키프레임 사이를 선형 보간한다")
    func interpolatesReframeKeyframes() {
        let track = ReframeTrack(mode: .keyframes, keyframes: [
            .init(t: 0, rect: NormRect(x: 0, y: 0, w: 0.5, h: 1)),
            .init(t: 2, rect: NormRect(x: 0.5, y: 0, w: 0.5, h: 1)),
        ])
        #expect(track.rect(at: 1)?.x == 0.25)
        // 바깥은 끝 값으로 고정한다. 외삽하면 화면이 밖으로 나간다.
        #expect(track.rect(at: -1)?.x == 0)
        #expect(track.rect(at: 99)?.x == 0.5)
    }

    @Test("fixed 는 첫 키프레임을 전 구간 고정한다")
    func fixedModeHoldsFirstKeyframe() {
        let track = ReframeTrack(mode: .fixed, keyframes: [
            .init(t: 0, rect: NormRect(x: 0.2, y: 0, w: 0.5, h: 1)),
            .init(t: 2, rect: NormRect(x: 0.9, y: 0, w: 0.5, h: 1)),
        ])
        #expect(track.rect(at: 1.5)?.x == 0.2)
    }
}
