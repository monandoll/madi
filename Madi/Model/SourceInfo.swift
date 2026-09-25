import Foundation
import CoreGraphics

/// 원본 영상의 기본 정보. **가져올 때 읽어서 저장한다.**
///
/// `AGENTS.md §6` 다이제스트 머리줄이 이미 이걸 적는다:
/// `# VIDEO v_01   duration 182.4s   1920x1080   30fps`
///
/// ★ 해상도가 여기 있어야 하는 이유: **확대 상한이 원본 해상도로 정해진다.**
///   세로 4K 는 2.5배까지 확대할 수 있고 1080p 는 1.25배까지다
///   (`docs/findings/2026-09-25-zoom-design.md §2`).
///   렌더 때 파일을 다시 열어 재지 않고 저장된 값을 쓴다.
public struct SourceInfo: Codable, Hashable, Sendable {
    public let videoID: String
    /// 회전 변환을 적용한 **보이는** 크기. 세로 촬영본은 여기서 세로가 된다.
    public let width: Int
    public let height: Int
    public let durationSec: Double
    public let fps: Double

    public init(videoID: String, width: Int, height: Int, durationSec: Double, fps: Double) {
        self.videoID = videoID; self.width = width; self.height = height
        self.durationSec = durationSec; self.fps = fps
    }

    public var size: CGSize { CGSize(width: width, height: height) }
    public var isPortrait: Bool { height > width }
}

/// 확대 상한 계산. **여기 한 곳에만 둔다** — 키프레임 계산도 게이트 측정도 이걸 부른다.
///
/// 상한 값 자체(`maxUpscale`)는 스타일에 있다 (`Resources/styles/short.v1.json`).
/// 코드에 박지 않는다 — 1.0 으로 조이거나 1.5 로 풀 때 JSON 만 고치면 된다.
public enum ReframeLimits {

    /// 배율 1 에서 잘라낼 수 있는 가로 폭(원본 픽셀).
    ///
    /// 출력과 같은 세로 비율을 원본에서 잘라내므로, 원본이 가로로 길면 **높이가 한계**가 된다.
    /// 가로 1920x1080 에서 9:16 을 잘라내면 608px 뿐이다 — 출력 1080px 보다 작다.
    public static func baseCropWidth(source: CGSize, output: CGSize) -> Double {
        let outputAspect = output.width / output.height
        return min(source.width, source.height * outputAspect)
    }

    /// 배율 1 에서 잘라낼 크롭 **크기**(원본 픽셀). 출력과 같은 비율이다.
    public static func baseCropSize(source: CGSize, output: CGSize) -> CGSize {
        let w = baseCropWidth(source: source, output: output)
        return CGSize(width: w, height: w * output.height / output.width)
    }

    /// 원본 상자 높이(원본 높이로 정규화)를 **배율 1 크롭 안에서 보이는 높이**로 바꾼다.
    ///
    /// 가로 원본은 크롭 높이가 원본 높이와 같아 값이 그대로지만,
    /// 9:16 보다 세로로 긴 원본(예: 4:5)은 크롭이 더 짧아 상자가 더 크게 보인다.
    /// 목표 점유율(`targetSubjectHeightRatio`)은 **출력 화면 기준**이므로 이 변환이 필요하다.
    public static func normalizedSubjectHeight(
        boxHeight: Double, source: CGSize, output: CGSize
    ) -> Double {
        let cropHeight = baseCropSize(source: source, output: output).height
        guard cropHeight > 0 else { return boxHeight }
        return boxHeight * source.height / cropHeight
    }

    /// 배율과 중심에서 크롭 사각형(원본 정규화, y 는 위로)을 만든다.
    /// 중심이 가장자리에 붙으면 **크롭을 원본 안으로 밀어 넣는다** — 레터박스를 만들지 않는다.
    public static func cropRect(
        zoom: Double, center: CGPoint, source: CGSize, output: CGSize
    ) -> NormRect {
        let base = baseCropSize(source: source, output: output)
        let z = max(zoom, 0.0001)
        let w = min(base.width / z / source.width, 1)
        let h = min(base.height / z / source.height, 1)
        let x = min(max(center.x - w / 2, 0), 1 - w)
        let y = min(max(center.y - h / 2, 0), 1 - h)
        return NormRect(x: x, y: y, w: w, h: h)
    }

    /// 이 배율로 확대했을 때 출력이 원본 픽셀을 얼마나 늘려 쓰는가.
    /// 1 이하면 원본 픽셀로 충분하고, 넘으면 보간이다.
    public static func upscale(zoom: Double, source: CGSize, output: CGSize) -> Double {
        let cropPx = baseCropWidth(source: source, output: output) / max(zoom, 0.0001)
        return output.width / cropPx
    }

    /// 스타일이 허용한 업스케일 안에서 쓸 수 있는 최대 배율.
    ///
    /// ★ **1 보다 작을 수 있다.** 가로 1080p 는 배율 1 에서 이미 1.78배 업스케일이라
    ///   `maxUpscale` 1.25 로는 0.70 이 나온다 — 확대할 수 없다는 뜻이다.
    ///   그 경우에도 배율 1(= 확대 없음)은 써야 하므로 부르는 쪽에서 `max(1, ...)` 한다.
    public static func maxZoom(source: CGSize, output: CGSize, maxUpscale: Double) -> Double {
        baseCropWidth(source: source, output: output) / output.width * maxUpscale
    }

    /// 목표 인물 높이에 닿는 데 필요한 배율. 상한을 넘으면 상한에서 자른다.
    ///
    /// - Returns: 실제로 쓸 배율과, 목표에 못 닿았는지.
    ///   못 닿으면 `G1` 은 `원본 한계` 로 기록한다 (`AGENTS.md §8`) — 실패가 아니다.
    public static func plan(
        subjectHeight: Double,
        target: Double,
        source: CGSize,
        output: CGSize,
        maxUpscale: Double
    ) -> (zoom: Double, reachedTarget: Bool, resultingHeight: Double) {
        guard subjectHeight > 0 else { return (1, false, 0) }
        let needed = target / subjectHeight
        let allowed = max(1, maxZoom(source: source, output: output, maxUpscale: maxUpscale))
        let zoom = min(max(needed, 1), allowed)
        let height = subjectHeight * zoom
        return (zoom, height + 0.0001 >= target, height)
    }
}
