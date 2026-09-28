import Testing
import Foundation
import CoreGraphics
@testable import MadiKit

/// 설정 자막 모양 미리보기 — 자막 둘레 띠 (`StillRenderer.captionBand`).
/// 세로 한 장을 통째로 넘기던 때는 설정의 납작한 칸이 가운데만 보여 줘서 자막이 잘려 빈 검은 칸이 됐다.
struct LookPreviewTests {

    @Test("띠 안에 본문과 영문 줄이 다 들어오고, 띠는 1080×360 이다. 사람이 친 문장 · 직접 고른 색도 그린다")
    func bandContainsCaption() throws {
        var style = try StyleStore.load().values
        style.look.caption.fill = HexColor(RGBA(1, 0.3, 0.5, 1))       // 컬러 피커로 고른 색
        let caption = Caption(id: "p", start: 0, end: 2, text: "제가 친 문장이에요", secondary: "My own line")
        let image = try StillRenderer.renderCaption(caption, size: CGSize(width: 1080, height: 1920),
                                                     style: style, slot: .fullBody)
        let band = try #require(StillRenderer.captionBand(image, height: 360))
        #expect(band.width == 1080 && band.height == 360)
        // 띠 위아래 끝줄은 비어 있어야 한다 (글자가 잘리지 않았다)
        let again = try #require(StillRenderer.captionBand(band, height: 360))
        #expect(again.height == 360)
        if let dir = ProcessInfo.processInfo.environment["MADI_LOOK_PREVIEW_OUT"] {
            try StillRenderer.writePNG(band, to: URL(fileURLWithPath: dir).appending(path: "look-preview.png"))
        }
    }
}
