import Testing
import Foundation
import CoreGraphics
@testable import MadiKit

/// 2단계 — 자막 분절과 게이트 G4 · G5 · G6 · G7.
///
/// 분절 규칙은 공개본 10편 190덩어리 실측에서 나왔다
/// (`docs/findings/2026-09-26-caption-segmentation-10.md`).
struct CaptionGateTests {

    private let frame = CGSize(width: 1080, height: 1920)

    private func style() throws -> StyleValues {
        try StyleStore.load(StyleStore.defaultID).values
    }

    /// 0.4초짜리 낱말을 이어 붙인다.
    private func words(_ texts: [String], gapAfter: [Int: Double] = [:]) -> [Word] {
        var t = 0.0
        return texts.enumerated().map { i, text in
            let w = Word(text: text, start: t, end: t + 0.4)
            t += 0.4 + (gapAfter[i] ?? 0.05)
            return w
        }
    }

    // MARK: - 분절

    @Test("낱말 안에서는 절대 끊지 않는다")
    func neverSplitsInsideAWord() throws {
        let style = try style()
        let source = ["골반교정을", "할", "때는", "허벅지", "안쪽을", "천천히", "눌러주세요"]
        let captions = CaptionSplitter.split(words(source), style: style.caption)
        let rejoined = captions.map(\.text).joined(separator: " ").split(separator: " ")
        #expect(rejoined.map(String.init) == source)
    }

    @Test("글자 수 상한을 넘지 않는다")
    func staysUnderMaxChars() throws {
        let style = try style()
        let captions = CaptionSplitter.split(
            words(["천천히", "일어나주시고", "다시", "천천히", "앉아주세요", "매일", "서른번씩"]),
            style: style.caption
        )
        for c in captions { #expect(c.text.count <= style.caption.maxChars) }
    }

    @Test("상한까지 눌러 담지 않는다 — 중앙값이 목표 근처다")
    func aimsAtTargetNotMax() throws {
        let style = try style()
        // 공개본 실측: 중앙 9자 · p90 13자 · 상한 15자.
        let source = ["골반이", "틀어지면", "한쪽", "다리가", "짧아지고", "허리에",
                      "부담이", "갑니다", "그래서", "매일", "스트레칭을", "해야해요"]
        let captions = CaptionSplitter.split(words(source), style: style.caption)
        let counts = captions.map(\.text.count).sorted()
        let median = counts[counts.count / 2]
        #expect(median <= style.caption.maxChars)
        // 상한(15)이 아니라 목표(9) 쪽에 붙어야 한다.
        #expect(median < style.caption.maxChars)
    }

    @Test("목표를 채운 뒤 말이 쉬면 거기서 끊는다")
    func breaksOnPauseAfterTarget() throws {
        let style = try style()
        // 세 번째 낱말 뒤에 큰 쉼.
        let ws = words(["골반이", "틀어지면", "아픕니다", "그래서", "스트레칭"],
                       gapAfter: [2: style.caption.pauseSec + 0.2])
        let captions = CaptionSplitter.split(ws, style: style.caption)
        #expect(captions.count >= 2)
        #expect(captions[0].text == "골반이 틀어지면 아픕니다")
    }

    @Test("장면 오프셋을 빼서 장면 로컬 시각으로 만든다")
    func subtractsSceneOffset() throws {
        let style = try style()
        let ws = [Word(text: "안녕", start: 10.0, end: 10.4)]
        let captions = CaptionSplitter.split(ws, style: style.caption, offset: 9.5)
        #expect(abs((captions.first?.start ?? 0) - 0.5) < 1e-9)
    }

    // MARK: - G4

    @Test("세 슬롯 모두 G4 를 통과한다")
    func g4PassesForEverySlot() throws {
        let style = try style()
        for slot in CaptionSlot.allCases {
            let (result, m) = Gate.g4(frameSize: frame, style: style, slot: slot)
            #expect(result == .pass)
            // 원본 실측 3.59% 근처여야 한다. 하한 3.2% 를 겨우 넘기는 게 아니다.
            #expect(abs(m.inkHeightRatio - style.caption.inkHeightRatio) < 0.001)
        }
    }

    @Test("글자를 줄이면 G4 가 실패한다")
    func g4FailsWhenTooSmall() throws {
        var style = try style()
        style.caption.inkHeightRatio = 0.02
        let (result, _) = Gate.g4(frameSize: frame, style: style, slot: .upperBody)
        #expect(result == .fail)
    }

    // MARK: - G5

    private func comp(captions: [Caption]) -> Composition {
        Composition(
            id: "c", videoID: "v", templateID: "short",
            meta: Composition.Meta(title: "t", targetDurationSec: 10),
            captionSlot: .upperBody,
            scenes: [Scene(
                id: "s1", role: .demo,
                source: Scene.Source(videoID: "v", start: 0, end: 10),
                captions: captions
            )]
        )
    }

    @Test("15자까지는 통과, 넘으면 실패")
    func g5ChecksCharLimit() throws {
        let style = try style()
        let ok = comp(captions: [
            Caption(id: "a", start: 0, end: 1, text: "반대쪽도 똑같이 진행해주세요"),  // 15자
        ])
        #expect(Gate.g5(ok, frameSize: frame, style: style).0 == .pass)

        let tooLong = comp(captions: [
            Caption(id: "a", start: 0, end: 1, text: "반대쪽도 똑같이 천천히 진행해주세요"),
        ])
        let (result, m) = Gate.g5(tooLong, frameSize: frame, style: style)
        #expect(result == .fail)
        #expect(m.overChars == ["a"])
    }

    @Test("자막이 없으면 통과가 아니라 판정 불가")
    func g5WithoutCaptionsCannotBeJudged() throws {
        let style = try style()
        let (result, _) = Gate.g5(comp(captions: []), frameSize: frame, style: style)
        #expect(result == .cannotJudge(.noCaptions))
        #expect(result.shouldRetry == false)
    }

    // MARK: - G6

    @Test("싱크가 맞으면 통과, 어긋나면 실패")
    func g6ChecksSync() throws {
        let transcript = Transcript(videoID: "v", words: [
            Word(text: "골반이", start: 2.00, end: 2.40),
            Word(text: "틀어지면", start: 2.45, end: 2.90),
        ])
        let ok = comp(captions: [
            Caption(id: "a", start: 2.05, end: 2.9, text: "골반이 틀어지면"),
        ])
        #expect(Gate.g6(ok, transcript: transcript).0 == .pass)

        let late = comp(captions: [
            Caption(id: "a", start: 2.50, end: 3.2, text: "골반이 틀어지면"),
        ])
        let (result, m) = Gate.g6(late, transcript: transcript)
        #expect(result == .fail)
        #expect(m.worstError > Gate.maxSyncErrorSec)
    }

    @Test("전사가 없으면 통과가 아니라 판정 불가")
    func g6WithoutTranscriptCannotBeJudged() throws {
        let empty = Transcript(videoID: "v", words: [])
        let c = comp(captions: [Caption(id: "a", start: 0, end: 1, text: "안녕")])
        let (result, _) = Gate.g6(c, transcript: empty)
        #expect(result == .cannotJudge(.noTranscript))
        #expect(result.shouldRetry == false)
    }

    // MARK: - G7

    @Test("자막 상자 안에 든 어깨선 위 관절을 찾아낸다")
    func g7FindsCoveredJoints() {
        let box = NormRect(x: 0.1, y: 0.2, w: 0.8, h: 0.1)
        let inside = Gate.g7(
            captionBox: box,
            joints: [.nose: (CGPoint(x: 0.5, y: 0.25), 0.9)]
        )
        #expect(inside.covered)
        #expect(inside.hits == ["nose"])

        let outside = Gate.g7(
            captionBox: box,
            joints: [.nose: (CGPoint(x: 0.5, y: 0.8), 0.9)]
        )
        #expect(outside.covered == false)
    }

    @Test("확신이 낮은 관절은 세지 않는다")
    func g7IgnoresLowConfidenceJoints() {
        let box = NormRect(x: 0, y: 0, w: 1, h: 1)
        let result = Gate.g7(
            captionBox: box, joints: [.nose: (CGPoint(x: 0.5, y: 0.5), 0.1)]
        )
        #expect(result.covered == false)
    }
}
