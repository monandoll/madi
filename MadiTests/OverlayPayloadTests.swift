import Testing
import Foundation
@testable import MadiKit

/// 오버레이 payload 는 **뜻만** 받는다. 모르는 키 · 빠진 키는 저장 전에 거절한다.
/// 근거: `docs/findings/2026-09-27-overlay-payload.md` (공개본 10편 · 오버레이 55개).
struct OverlayPayloadTests {

    private func parse(_ overlay: String) throws -> Composition {
        try parseComposition(Data("""
        {
          "id": "c1", "videoId": "v1", "templateId": "short",
          "style": { "id": "short.v1", "version": 1 },
          "meta": { "targetDurationSec": 30 }, "captionSlot": "upperBody",
          "scenes": [{ "id": "s1", "role": "demo", "source": { "videoId": "v1", "in": 0, "out": 3 },
                       "overlays": [\(overlay)] }]
        }
        """.utf8))
    }

    private func problems(_ overlay: String) -> [String] {
        do { _ = try parse(overlay); return [] } catch let e as CompositionError {
            return e.problems
        } catch { return ["\(error)"] }
    }

    @Test("원본에 나온 네 가지 오버레이가 저장된다", arguments: [
        #"{ "id": "a", "kind": "arrow", "start": 0, "end": 1, "anchor": { "x": 0.6, "y": 0.4 }, "to": { "x": 0.4, "y": 0.4 }, "payload": { "tone": "neutral", "path": "curved", "bend": "right" } }"#,
        #"{ "id": "r", "kind": "circle", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.7 }, "payload": { "form": "ring", "tone": "problem", "covers": "part" } }"#,
        #"{ "id": "p", "kind": "circle", "start": 0, "end": 1, "anchor": { "x": 0.7, "y": 0.47 }, "payload": { "form": "pulse" } }"#,
        #"{ "id": "i", "kind": "image", "start": 0, "end": 2, "anchor": { "x": 0.5, "y": 0.7 }, "payload": { "assetId": "legs-flow", "placement": "under" } }"#,
        #"{ "id": "m", "kind": "mark", "start": 0, "end": 2, "anchor": { "x": 0.1, "y": 0.2 }, "payload": { "symbol": "o" } }"#,
    ])
    func acceptsObservedOverlays(overlay: String) {
        #expect(problems(overlay).isEmpty, "\(problems(overlay))")
    }

    @Test("화살표는 끝점(to)이 있어야 한다")
    func arrowNeedsTo() {
        let p = problems(#"{ "id": "a", "kind": "arrow", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 }, "payload": { "tone": "problem", "path": "straight" } }"#)
        #expect(p.contains { $0.contains(".to 가 필요하다") })
    }

    @Test("곡선 화살표는 휘는 쪽(bend)이 있어야 한다")
    func curvedArrowNeedsBend() {
        let p = problems(#"{ "id": "a", "kind": "arrow", "start": 0, "end": 1, "anchor": { "x": 0.6, "y": 0.4 }, "to": { "x": 0.4, "y": 0.4 }, "payload": { "tone": "neutral", "path": "curved" } }"#)
        #expect(p.contains { $0.contains("payload.bend 가 필요하다") })
    }

    @Test("모르는 키는 거절하고, 쓸 수 있는 키를 알려 준다")
    func rejectsUnknownKeys() {
        // 느슨하게 받으면 AI 가 매번 다른 키를 지어내고 렌더가 조용히 무시한다.
        let p = problems(#"{ "id": "m", "kind": "mark", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 }, "payload": { "symbol": "x", "part": "knee" } }"#)
        #expect(p.contains { $0.contains("payload.part") && $0.contains("symbol") })
    }

    @Test("뜻이 아닌 값은 거절한다")
    func rejectsUnknownValues() {
        // 색 이름을 tone 자리에 넣어도 안 된다. 색은 스타일이 정한다.
        let p = problems(#"{ "id": "r", "kind": "circle", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 }, "payload": { "form": "ring", "tone": "red", "covers": "joint" } }"#)
        #expect(p.contains { $0.contains("\"red\"") })
    }

    @Test("pulse · tap 은 모양이 뜻이라 tone 을 받지 않는다")
    func pulseTakesNoTone() {
        let p = problems(#"{ "id": "p", "kind": "circle", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 }, "payload": { "form": "tap", "tone": "problem" } }"#)
        #expect(!p.isEmpty)
    }

    @Test("to 는 화살표에만 쓴다")
    func toOnlyOnArrow() {
        let p = problems(#"{ "id": "m", "kind": "mark", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 }, "to": { "x": 0.2, "y": 0.2 }, "payload": { "symbol": "x" } }"#)
        #expect(p.contains { $0.contains(".to 는 arrow 에만") })
    }

    @Test("공개본에 없던 kind 는 읽히지 않는다", arguments: ["titleCard", "counter", "progress"])
    func removedKindsFail(kind: String) {
        #expect(throws: (any Error).self) {
            try parse(#"{ "id": "o", "kind": "\#(kind)", "start": 0, "end": 1, "anchor": { "x": 0.5, "y": 0.5 } }"#)
        }
    }

    @Test("Spec.json 이 AI 에게 알려 주는 kind 와 코드가 받는 kind 가 같다")
    func specMatchesCode() throws {
        // 어긋나면 AI 가 Spec 대로 쓴 편집안이 저장되지 않거나, 코드가 받는 걸 AI 가 모른다.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Madi/Templates/Spec.json")
        let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let kinds = ((spec?["overlay"] as? [String: Any])?["kind"] as? [String: Any])?.keys
        let specKinds = Set(kinds.map(Array.init) ?? [])
        let codeKinds: Set<String> = ["arrow", "circle", "image", "mark"]
        #expect(specKinds == codeKinds)
        for k in codeKinds { #expect(Overlay.Kind(rawValue: k) != nil) }
    }
}
