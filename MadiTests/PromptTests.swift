import Testing
import Foundation
@testable import MadiKit

/// 프롬프트 조립 (AGENTS.md §10 — 순서 · 빠진 칸 없음).
struct PromptTests {

    @Test("§10 순서대로 여섯 칸이 붙는다")
    func order() throws {
        let p = try PromptAssembler.assemble(videoID: "v1")
        let heads = ["# 1. 제작 지침", "# 2. 템플릿이 지원하는 것", "# 3. 품질 기준", "# 4. 크리에이터 규칙", "# 5. 영상", "# 6. 대화"]
        let positions = try heads.map { try #require(p.range(of: $0)?.lowerBound, "\($0) 가 없다") }
        #expect(positions == positions.sorted())
    }

    @Test("세기 순서가 맨 위에 있다")
    func priorityFirst() throws {
        let p = try PromptAssembler.assemble(videoID: "v1")
        #expect(p.hasPrefix("규칙이 서로 부딪히면"))
        #expect(p.contains("4. 크리에이터 규칙 > 2. 템플릿 Spec > 3. 품질 기준 > 1. 제작 지침"))
    }

    @Test("제작 지침 · Spec.json 이 번들에서 통째로 들어간다")
    func bundled() throws {
        let p = try PromptAssembler.assemble(videoID: "v1")
        #expect(p.contains("## 길이"))                  // playbook.md
        #expect(p.contains(#""captionSlot""#))          // Spec.json
        #expect(p.contains("`v1`"))
    }

    @Test("크리에이터 편집 문법(30편 실측)이 지침에 있고, 품질 기준이 그와 부딪히지 않는다")
    func creatorStyle() throws {
        let p = try PromptAssembler.assemble(videoID: "v1")
        #expect(p.contains("## 구성 — 크리에이터의 틀"))
        #expect(p.contains("## 끝맺음") && p.contains("꼭 따라해보세요"))
        #expect(p.contains("1.25초"))                                     // 장면 호흡
        // 품질 기준 칸이 지침보다 세다(§10) — 옛 컷 리듬 "1.5~4.0초" 가 있으면 AI 가 장면을 길게 묶는다
        #expect(!PromptAssembler.gateSummary.contains("1.5~4"))
        #expect(!p.contains("1.5~4"))
    }

    @Test("크리에이터 규칙 · 대화 · 요청")
    func rulesAndTalk() throws {
        let empty = try PromptAssembler.assemble(videoID: "v1")
        #expect(empty.contains("(아직 없음)"))
        #expect(empty.hasSuffix("크리에이터: \(PromptAssembler.firstDraftRequest)\n"))

        let p = try PromptAssembler.assemble(
            videoID: "v1", userRules: ["  훅은 질문으로 시작한다 ", ""],
            history: [.init(.creator, "초안 만들어 줘"), .init(.assistant, "훅을 앞으로 옮겼어요")],
            request: "마무리를 짧게"
        )
        #expect(p.contains("- 훅은 질문으로 시작한다\n") || p.contains("- 훅은 질문으로 시작한다\n\n"))
        #expect(!p.contains("(아직 없음)"))
        #expect(p.contains("크리에이터: 초안 만들어 줘\n너: 훅을 앞으로 옮겼어요\n크리에이터: 마무리를 짧게"))
    }

    @Test("아직 그리지 못하는 것은 저장 전에 걸러진다")
    func unsupported() {
        var c = Composition(
            id: "c", videoID: "v", templateID: "short", style: StyleRef(id: "short.v1", version: 1),
            meta: Composition.Meta(targetDurationSec: 5), captionSlot: .fullBody,
            scenes: [Scene(id: "s1", role: .hook, source: Scene.Source(videoID: "v", start: 0, end: 3))]
        )
        #expect(Renderer.unsupported(c).isEmpty)
        c.scenes[0].transitionIn = .fade
        c.audio.sfx = [AudioTracks.SFX(assetID: "pop", at: 1)]
        #expect(Renderer.unsupported(c).count == 2)
    }
}
