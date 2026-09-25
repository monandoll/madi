import Foundation
import Vision
import CoreGraphics

/// 프레임에 **번인된 자막**을 읽는다. 공개본 실측 전용이다.
///
/// ★ 제품 경로가 아니다. 우리가 그리는 자막은 `Composition` 이 이미 알고 있다.
///   이건 크리에이터가 실제로 어떻게 분절하는지를 재려고 쓴다 (`AGENTS.md §0-5` — 학습 말고 측정).
///
/// Vision 의 `VNRecognizeTextRequest` 는 온디바이스다. 외부 바이너리가 없다 (`§2`).
public enum CaptionReader {

    public struct Read: Sendable {
        /// 줄을 개행으로 이은 자막 한 덩어리.
        public let text: String
        public let lines: Int
        /// 가장 큰 줄의 글자 높이 ÷ 프레임 높이. G4 가 보는 값과 같은 단위다.
        public let inkHeightRatio: Double
        /// 자막 블록 아래끝, **아래에서** 잰 비율.
        public let inkBottomRatio: Double
        /// 본문 줄들을 감싸는 상자 (정규화, y 는 위로). G7 이 보는 "자막 박스" 다.
        public let box: NormRect
    }

    /// - Parameter minHeightRatio: 이보다 작은 글자는 자막이 아니라고 본다.
    ///   워터마크 · 채널명 · 배경 간판을 걸러낸다. 원본 실측 본문 높이는 0.0359 다.
    public static func read(
        _ image: CGImage, minHeightRatio: Double = 0.02, searchBottom: Double = 0.75
    ) throws -> Read {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 크리에이터 자막은 한국어 + 영문 보조 문구다.
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let observations = (request.results ?? []).filter { o in
            // Vision 좌표는 아래가 0 이다. 화면 아래쪽 구간만 본다.
            o.boundingBox.height >= minHeightRatio
                && o.boundingBox.minY <= searchBottom
                && (o.topCandidates(1).first?.confidence ?? 0) >= 0.3
        }
        guard !observations.isEmpty else {
            return Read(
                text: "", lines: 0, inkHeightRatio: 0, inkBottomRatio: 0,
                box: NormRect(x: 0, y: 0, w: 0, h: 0)
            )
        }

        // 본문은 **가장 큰 글자**다. 보조 문구(0.44배)와 워터마크를 여기서 가른다.
        let tallest: CGFloat = observations.map(\.boundingBox.height).max() ?? 0
        let body = observations.filter { $0.boundingBox.height >= tallest * 0.75 }
        // 위에서 아래로 읽는다.
        let ordered = body.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        let text = ordered
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let boxes = ordered.map(\.boundingBox)
        let minX = boxes.map(\.minX).min() ?? 0, maxX = boxes.map(\.maxX).max() ?? 0
        let minY = boxes.map(\.minY).min() ?? 0, maxY = boxes.map(\.maxY).max() ?? 0
        return Read(
            text: text,
            lines: ordered.count,
            inkHeightRatio: Double(tallest),
            inkBottomRatio: Double(minY),
            box: NormRect(
                x: Double(minX), y: Double(minY),
                w: Double(maxX - minX), h: Double(maxY - minY)
            )
        )
    }
}
