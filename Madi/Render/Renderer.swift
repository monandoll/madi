import Foundation
import AVFoundation
import CoreGraphics
import QuartzCore
import os

/// `Composition` → mp4. AGENTS.md §7.
///
/// ```
/// 1. plan      장면별 원본 구간 계산
/// 2. compose   AVMutableComposition — 컷 · 순서 · 배속
/// 3. layers    CALayer 트리 — 리프레임 변환 · 자막 · 오버레이
/// 4. write     mp4
/// ```
///
/// **프리뷰와 최종 렌더가 같은 `videoComposition` 과 같은 레이어 코드를 쓴다** (AGENTS.md §7).
/// `makeVideoComposition` 이 둘 다에 쓰이는 유일한 입구다.
///
/// actor 가 아니다. AVFoundation 객체는 Sendable 이 아니라서 actor 경계를 넘길 수 없고,
/// 넘길 이유도 없다 — 한 번의 렌더는 한 호출 안에서 끝난다.
/// 동시성 제어는 큐가 한다 (AGENTS.md §2: 렌더 1 · 분석 1).
public struct Renderer {

    private static let log = Logger(subsystem: "app.madi", category: "render")

    public enum Failure: Error, CustomStringConvertible {
        case missingSource(String)
        case noVideoTrack(String)
        case sourceTooShort(String, asked: Double, actual: Double)
        case exportFailed(String)
        case cannotCreateExporter

        public var description: String {
            switch self {
            case .missingSource(let id):
                "원본 영상 \(id) 을 찾지 못했습니다"
            case .noVideoTrack(let id):
                "원본 영상 \(id) 에 비디오 트랙이 없습니다"
            case .sourceTooShort(let id, let asked, let actual):
                "원본 영상 \(id) 은 \(String(format: "%.2f", actual))초인데 "
                + "\(String(format: "%.2f", asked))초 지점을 달라고 했습니다"
            case .exportFailed(let reason):
                "영상을 만들지 못했습니다: \(reason)"
            case .cannotCreateExporter:
                "내보내기를 시작하지 못했습니다"
            }
        }
    }

    public init() {}

    /// - Parameters:
    ///   - sources: `Scene.source.videoID` → 원본 파일.
    ///   - style: 자막 스타일 값. `Composition` 이 아니라 여기로 들어온다 (AGENTS.md §9).
    public func render(
        _ comp: Composition,
        sources: [String: URL],
        style: StyleValues,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        progress?(0)
        let plan = try await plan(comp, sources: sources)
        let (composition, instructions) = try await compose(comp, plan: plan)
        let videoComposition = makeVideoComposition(
            comp, instructions: instructions, style: style
        )

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // ★ `AVVideoCompositionCoreAnimationTool` 은 **내보내기에서만** 적용된다.
        //   AVAssetReader/AVPlayer 는 무시한다. AGENTS.md §3 은 인코딩을 AVAssetWriter 로
        //   적었는데, AssetWriter 경로로는 이 도구가 붙지 않아 자막이 사라진다.
        //   지금은 도구가 동작하는 쪽을 쓴다 — 둘 중 하나를 고르는 문제이고,
        //   `docs/findings/` 에 적어 두었다.
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else { throw Failure.cannotCreateExporter }
        export.videoComposition = videoComposition
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        // 진행률은 0 과 1 만 알린다. `AVAssetExportSession.progress` 를 폴링하려면
        // 별도 Task 가 필요한데 `AVAssetExportSession` 이 Sendable 이 아니라 넘길 수 없다.
        // 스파이크에 진행 막대는 필요 없고, 3단계 큐에서 제대로 붙인다.
        await export.export()

        switch export.status {
        case .completed:
            progress?(1)
            Self.log.info("렌더 완료 \(comp.id, privacy: .public)")
        case .cancelled:
            throw Failure.exportFailed("취소됨")
        default:
            throw Failure.exportFailed(export.error?.localizedDescription ?? "알 수 없는 이유")
        }
    }

    // MARK: - 1. plan

    /// 장면별로 실제 쓸 원본 트랙과 구간을 확정한다.
    /// `AVAsset` 이 Sendable 이 아니라 이 타입도 actor 안에 머문다 — 밖으로 내보내지 않는다.
    struct ScenePlan {
        let scene: Scene
        let asset: AVAsset
        let sourceRange: CMTimeRange
        /// 결과물 타임라인에서 이 장면이 시작하는 시각.
        let outputStart: CMTime
        /// 배속 반영한 결과 길이.
        let outputDuration: CMTime
        /// 원본 프레임 크기 (preferredTransform 적용 후).
        let naturalSize: CGSize
    }

    private func plan(_ comp: Composition, sources: [String: URL]) async throws -> [ScenePlan] {
        var plans: [ScenePlan] = []
        var cursor = CMTime.zero
        let timescale: CMTimeScale = 600

        for scene in comp.scenes {
            guard let url = sources[scene.source.videoID] else {
                throw Failure.missingSource(scene.source.videoID)
            }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw Failure.noVideoTrack(scene.source.videoID)
            }
            let duration = try await asset.load(.duration).seconds
            guard scene.source.end <= duration + 0.05 else {
                throw Failure.sourceTooShort(
                    scene.source.videoID, asked: scene.source.end, actual: duration
                )
            }

            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            // 세로로 찍은 영상은 회전 변환이 붙어 있다. 실제로 보이는 크기로 바꾼다.
            let displaySize = naturalSize.applying(transform)
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: scene.source.start, preferredTimescale: timescale),
                end: CMTime(seconds: min(scene.source.end, duration), preferredTimescale: timescale)
            )
            let outputDuration = CMTime(
                seconds: scene.duration, preferredTimescale: timescale
            )

            plans.append(ScenePlan(
                scene: scene,
                asset: asset,
                sourceRange: sourceRange,
                outputStart: cursor,
                outputDuration: outputDuration,
                naturalSize: CGSize(width: abs(displaySize.width), height: abs(displaySize.height))
            ))
            cursor = cursor + outputDuration
        }
        return plans
    }

    // MARK: - 2. compose

    private func compose(
        _ comp: Composition, plan: [ScenePlan]
    ) async throws -> (AVMutableComposition, [AVMutableVideoCompositionInstruction]) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Failure.cannotCreateExporter }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let renderSize = comp.size.cgSize

        for p in plan {
            guard let sourceVideo = try await p.asset.loadTracks(withMediaType: .video).first else {
                throw Failure.noVideoTrack(p.scene.source.videoID)
            }
            let insertAt = p.outputStart
            try videoTrack.insertTimeRange(p.sourceRange, of: sourceVideo, at: insertAt)

            if let audioTrack,
               let sourceAudio = try await p.asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(p.sourceRange, of: sourceAudio, at: insertAt)
            }

            // 배속. 넣은 구간을 결과 길이로 늘리거나 줄인다.
            if p.scene.speed != 1 {
                let inserted = CMTimeRange(start: insertAt, duration: p.sourceRange.duration)
                videoTrack.scaleTimeRange(inserted, toDuration: p.outputDuration)
                audioTrack?.scaleTimeRange(inserted, toDuration: p.outputDuration)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: insertAt, duration: p.outputDuration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTrack
            )
            let preferred = try await sourceVideo.load(.preferredTransform)
            layerInstruction.setTransform(
                reframeTransform(
                    scene: p.scene,
                    sourceSize: p.naturalSize,
                    preferred: preferred,
                    renderSize: renderSize
                ),
                at: insertAt
            )
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)
        }

        return (composition, instructions)
    }

    /// 원본의 어느 영역을 9:16 화면에 채울지. `ReframeTrack` 이 시키는 대로 한다.
    ///
    /// 0단계에서는 **정적 변환만** 쓴다. 시간축 키프레임 보간은 1단계다 (AGENTS.md §12-1).
    /// 키프레임이 여러 개여도 첫 값만 쓰고, 그 사실을 로그에 남긴다.
    private func reframeTransform(
        scene: Scene, sourceSize: CGSize, preferred: CGAffineTransform, renderSize: CGSize
    ) -> CGAffineTransform {
        if scene.reframe.mode == .keyframes && scene.reframe.keyframes.count > 1 {
            Self.log.notice("""
            장면 \(scene.id, privacy: .public): 리프레임 키프레임이 여러 개지만 \
            0단계는 첫 값만 씁니다 (보간은 1단계).
            """)
        }

        // 잡을 원본 영역. 없으면 화면을 꽉 채우는 중앙 크롭.
        let crop = scene.reframe.rect(at: 0) ?? centerCrop(
            sourceSize: sourceSize, aspect: renderSize.width / renderSize.height
        )
        let cropRect = CGRect(
            x: crop.x * sourceSize.width,
            y: crop.y * sourceSize.height,
            width: max(crop.w * sourceSize.width, 1),
            height: max(crop.h * sourceSize.height, 1)
        )
        // 잘라낸 영역이 화면을 가득 채우도록 키운다 (레터박스를 만들지 않는다).
        let scale = max(renderSize.width / cropRect.width, renderSize.height / cropRect.height)

        return preferred
            .concatenating(CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (renderSize.width - cropRect.width * scale) / 2,
                y: (renderSize.height - cropRect.height * scale) / 2
            ))
    }

    private func centerCrop(sourceSize: CGSize, aspect: CGFloat) -> NormRect {
        let sourceAspect = sourceSize.width / sourceSize.height
        if sourceAspect > aspect {
            // 원본이 더 넓다 → 좌우를 자른다.
            let w = aspect / sourceAspect
            return NormRect(x: (1 - w) / 2, y: 0, w: w, h: 1)
        }
        let h = sourceAspect / aspect
        return NormRect(x: 0, y: (1 - h) / 2, w: 1, h: h)
    }

    // MARK: - 3. layers

    /// 프리뷰와 최종 렌더가 **이 함수 하나**를 같이 쓴다 (AGENTS.md §7).
    public func makeVideoComposition(
        _ comp: Composition,
        instructions: [AVMutableVideoCompositionInstruction],
        style: StyleValues
    ) -> AVMutableVideoComposition {
        let renderSize = comp.size.cgSize
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(comp.fps))
        videoComposition.instructions = instructions

        let bounds = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = bounds
        let parentLayer = CALayer()
        parentLayer.frame = bounds
        parentLayer.contentsScale = 1
        parentLayer.addSublayer(videoLayer)

        for layer in overlayLayers(comp, style: style) { parentLayer.addSublayer(layer) }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )
        return videoComposition
    }

    /// 자막 레이어들. 장면 로컬 시각을 결과물 타임라인으로 옮겨 붙인다.
    func overlayLayers(_ comp: Composition, style: StyleValues) -> [CALayer] {
        var layers: [CALayer] = []
        let offsets = comp.sceneOffsets
        for (i, scene) in comp.scenes.enumerated() {
            let offset = offsets[i]
            let slot = comp.captionSlot(for: scene)
            for caption in scene.captions {
                let layer = CaptionLayer(
                    caption: caption, frameSize: comp.size.cgSize, style: style, slot: slot
                )
                // `beginTime` 0 은 CoreAnimation 이 "지금" 으로 해석해서 무시한다.
                // `AVCoreAnimationBeginTimeAtZero` 가 타임라인의 0 이다.
                layer.applyTiming(
                    start: offset + caption.start,
                    end: offset + caption.end,
                    beginTimeAtZero: AVCoreAnimationBeginTimeAtZero
                )
                layers.append(layer)
            }
        }
        return layers
    }
}
