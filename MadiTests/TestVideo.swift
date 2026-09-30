import Foundation
import AVFoundation
import CoreGraphics
import Testing

/// 테스트용 짧은 원본 영상.
enum TestVideo {
    /// 소리 없는 단색 mp4 를 만든다. 회색(90)이라 흰 자막 픽셀과 섞이지 않는다.
    static func makeSolid(
        at url: URL, seconds: Double = 0.5, size: CGSize = CGSize(width: 128, height: 128)
    ) async throws {
        try await make(at: url, seconds: seconds, size: size) { _ in 90 }
    }

    /// 밝기가 `switchAt` 초에 90 → 220 으로 바뀌는 영상. 장면 전환 검출용.
    static func makeTwoTone(
        at url: URL, seconds: Double = 2, switchAt: Double = 1,
        size: CGSize = CGSize(width: 128, height: 128)
    ) async throws {
        try await make(at: url, seconds: seconds, size: size) { t in t < switchAt ? 90 : 220 }
    }

    /// 단색 화면 + 440Hz 사인파 소리(AAC) — 여러 장면을 붙인 결과물의 소리를 볼 때.
    static func makeWithTone(at url: URL, seconds: Double = 3, size: CGSize = CGSize(width: 128, height: 224)) async throws {
        try await make(at: url, seconds: seconds, size: size, tone: true) { _ in 90 }
    }

    private static func make(
        at url: URL, seconds: Double, size: CGSize, tone: Bool = false, brightness: (Double) -> UInt8
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        writer.add(input)
        let sampleRate = 44_100.0
        let audioInput: AVAssetWriterInput? = tone ? AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ]) : nil
        if let audioInput { audioInput.expectsMediaDataInRealTime = false; writer.add(audioInput) }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        var audioWritten = 0
        for frame in 0..<Int(seconds * Double(fps)) {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault, Int(size.width), Int(size.height),
                kCVPixelFormatType_32BGRA, nil, &pixelBuffer
            )
            let buffer = try #require(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(brightness(Double(frame) / Double(fps))),
                       CVPixelBufferGetBytesPerRow(buffer) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            // 소리가 있으면 번갈아 쓴다 — 비디오만 먼저 다 쓰면 쓰기가 두 트랙을 맞추려고 기다리다 멈춘다
            if let audioInput {
                let upTo = Int((Double(frame + 1) / Double(fps)) * sampleRate)
                try await appendTone(audioInput, upTo: upTo, from: &audioWritten, sampleRate: sampleRate)
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(
                buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            )
        }
        input.markAsFinished()
        if let audioInput {
            try await appendTone(audioInput, upTo: Int(seconds * sampleRate), from: &audioWritten, sampleRate: sampleRate)
            audioInput.markAsFinished()
        }
        await writer.finishWriting()
    }

    /// 440Hz 사인파 PCM 을 `from` 부터 `upTo` 샘플까지 1024 샘플씩 붙인다 (AAC 로 인코딩된다).
    private static func appendTone(_ input: AVAssetWriterInput, upTo: Int, from written: inout Int, sampleRate: Double) async throws {
        while written < upTo {
            let n = min(1024, upTo - written)
            var asbd = AudioStreamBasicDescription(
                mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            var samples = [Int16](repeating: 0, count: n)
            for i in 0..<n { samples[i] = Int16(sin(2 * .pi * 440 * Double(written + i) / sampleRate) * 12_000) }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 2, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: n * 2, flags: 0, blockBufferOut: &block)
            let bb = try #require(block)
            samples.withUnsafeBytes { raw in _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: n * 2) }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: bb, formatDescription: try #require(format),
                sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &sample)
            var waited = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
                waited += 1
                if waited > 2_500 { throw CocoaError(.fileWriteUnknown) }   // 5초 — 멈추면 끝없이 기다리지 않는다
            }
            input.append(try #require(sample))
            written += n
        }
    }
}
