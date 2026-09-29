import Testing
import Foundation
@testable import MadiKit

/// 앱이 자막을 채운다 (docs/stage-4.spec.md). 분절은 CaptionSplitter, 여기는 장면 · 배속 · 영문 나누기.
struct CaptionFillerTests {

    private let words: [Word] = [
        Word(text: "오늘은", start: 10.0, end: 10.4), Word(text: "골반", start: 10.4, end: 10.8),
        Word(text: "스트레칭을", start: 10.8, end: 11.4), Word(text: "알려드릴게요.", start: 11.4, end: 12.2),
    ]

    private func comp(start: Double, end: Double, speed: Double = 1) -> Composition {
        Composition(
            id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 5), captionSlot: .fullBody,
            scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v", start: start, end: end), speed: speed)]
        )
    }

    private var style: StyleValues.CaptionValues { get throws { try StyleStore.load().values.caption } }

    @Test("배속 장면은 자막 시각도 배속으로 줄어든다")
    func speedScalesTimes() throws {
        var c = comp(start: 10.0, end: 12.4, speed: 2)
        #expect(CaptionFiller.fill(&c, words: words, style: try style, translations: []).isEmpty)
        let caps = c.scenes[0].captions
        #expect(abs(caps.last!.end - 1.1) < 0.001)   // (12.2 - 10.0) / 2
        try validate(c)
    }

    @Test("컷에 걸린 낱말은 자막을 달지 않는다")
    func dropsCutWords() throws {
        var c = comp(start: 10.0, end: 11.0)   // "스트레칭을"(10.8~11.4) 이 걸린다
        _ = CaptionFiller.fill(&c, words: words, style: try style, translations: [])
        #expect(c.scenes[0].captions.map(\.text).joined(separator: " ") == "오늘은 골반")
        try validate(c)
    }

    @Test("영문 나누기 — 순서를 지키고, 낱말 안에서 끊지 않고, 한글이 긴 덩어리가 더 받는다")
    func distributes() {
        let out = CaptionFiller.distribute("your hip and ankle, are the middle joints", over: ["중간 관절이라서", "고관절과 발목 사이"])
        #expect(out.compactMap { $0 }.joined(separator: " ") == "your hip and ankle, are the middle joints")
        #expect(out.allSatisfy { $0 != nil })
    }

    @Test("영문 낱말이 덩어리보다 적으면 뒤쪽은 비운다")
    func fewerWords() {
        #expect(CaptionFiller.distribute("me!", over: ["잘", "들어?"]) == ["me!", nil])
    }
}

extension CaptionFillerTests {
    @Test("낱말 안에 떨어진 장면 경계는 가까운 낱말 경계로 옮긴다")
    func snaps() throws {
        // in 10.5 는 "골반"(10.4~10.8) 앞쪽 → 10.4 (넣는다). out 11.3 은 "스트레칭을"(10.8~11.4) 뒤쪽 → 11.4 (넣는다)
        var c = comp(start: 10.5, end: 11.3)
        #expect(CaptionFiller.snapToWords(&c, words: words) == 1)
        #expect(c.scenes[0].source.start == 10.4 && c.scenes[0].source.end == 11.4)
        // out 10.9 는 "스트레칭을" 앞쪽 → 10.8 (뺀다)
        var d = comp(start: 10.0, end: 10.9)
        CaptionFiller.snapToWords(&d, words: words)
        #expect(d.scenes[0].source.end == 10.8)
        // 낱말 경계에 있으면 그대로
        var e = comp(start: 10.0, end: 12.2)
        #expect(CaptionFiller.snapToWords(&e, words: words) == 0)
    }

    @Test("낱말 끝으로 밀어도 영상 길이를 넘지 않는다 — 전사 마지막 낱말 끝이 영상보다 길게 나온다 (60.00초 영상에 60.08)")
    func snapStopsAtVideoEnd() throws {
        // out 11.3 은 "스트레칭을"(10.8~11.4) 뒤쪽이라 11.4 로 밀리지만, 영상이 11.35초에서 끝난다
        var c = comp(start: 10.4, end: 11.3)
        CaptionFiller.snapToWords(&c, words: words, limit: 11.35)
        #expect(c.scenes[0].source.end == 11.35)
    }

    // 말 앞뒤 숨 쉴 틈 — 크리에이터 완성본 실측: 말 끝 뒤 0.14초 · 컷 뒤 첫 말 0.10초 (2026-09-29)
    private var spaced: [Word] {
        [Word(text: "하나", start: 1.0, end: 1.5), Word(text: "둘", start: 2.5, end: 3.0),
         Word(text: "셋", start: 3.05, end: 3.5), Word(text: "넷", start: 5.0, end: 5.5)]
    }

    private func scenes(_ ranges: [(Double, Double)]) -> Composition {
        Composition(
            id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 5), captionSlot: .fullBody,
            scenes: ranges.enumerated().map { i, r in
                Scene(id: "s\(i)", role: i == 0 ? .hook : .demo, source: Scene.Source(videoID: "v", start: r.0, end: r.1))
            }
        )
    }

    @Test("가운데 장면 — 낱말에 딱 붙은 경계에 말 앞 0.10초 · 말 끝 뒤 0.15초 (조용한 틈이 있으면)")
    func breathesIntoSilence() {
        var c = scenes([(1.0, 1.5), (2.5, 3.5), (5.0, 5.5)])
        CaptionFiller.breathe(&c, words: spaced)
        #expect(abs(c.scenes[1].source.start - 2.4) < 1e-9 && abs(c.scenes[1].source.end - 3.65) < 1e-9)
    }

    @Test("첫 장면 시작은 그대로(첫 말 0초 — G8), 마지막 장면 끝은 0.30초")
    func firstAndLast() {
        var c = scenes([(2.5, 3.5)])
        CaptionFiller.breathe(&c, words: spaced)
        #expect(c.scenes[0].source.start == 2.5)
        #expect(abs(c.scenes[0].source.end - 3.8) < 1e-9)
    }

    @Test("틈은 옆 낱말 · 영상 끝을 넘지 않는다")
    func breathStopsAtNeighbours() {
        // "둘" 만 쓰는 장면 — 바로 뒤 "셋"(3.05)이 붙어 있어 끝은 3.03 까지만
        var c = scenes([(2.5, 3.0), (5.0, 5.5)])
        CaptionFiller.breathe(&c, words: spaced)
        #expect(abs(c.scenes[0].source.end - 3.03) < 1e-9)
        // 영상이 5.6초에서 끝난다
        var d = scenes([(5.0, 5.5)])
        CaptionFiller.breathe(&d, words: spaced, limit: 5.6)
        #expect(abs(d.scenes[0].source.end - 5.6) < 1e-9)
    }

    @Test("원본이 그대로 이어지는 두 장면 사이는 컷이 아니라 건드리지 않고, 다른 장면 구간과 겹치지 않는다")
    func breathKeepsJoinsAndNeverOverlaps() {
        var c = scenes([(5.0, 5.5), (1.0, 1.5), (1.5, 3.5)])       // 뒤 둘은 1.5 에서 이어진다
        CaptionFiller.breathe(&c, words: spaced)
        #expect(c.scenes[1].source.end == 1.5 && c.scenes[2].source.start == 1.5)
        #expect(abs(c.scenes[1].source.start - 0.9) < 1e-9)          // 컷 뒤 첫 말 앞은 붙인다
        // 순서가 바뀐 두 장면 — 원본 앞쪽 장면의 끝이 다른 장면의 원본 시작을 넘지 않는다
        var d = scenes([(3.52, 5.5), (2.5, 3.5), (1.0, 1.5)])
        CaptionFiller.breathe(&d, words: spaced)
        #expect(d.scenes[1].source.end <= d.scenes[0].source.start + 1e-9)
    }
}
