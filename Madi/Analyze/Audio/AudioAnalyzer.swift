import Foundation
import AVFoundation

/// 다이제스트 `AUDIO` (AGENTS.md §6). 무음 구간과 소리 크기 곡선.
///
/// 원본 오디오를 모노 float 로 읽어 **창(window)마다 RMS(dBFS)** 를 낸다. 무음은 RMS 가
/// 기준 아래로 일정 시간 이상 이어진 구간이다. G9(무음 + 저모션 1.2초)가 이 값을 쓴다.
///
/// ⚠ **기준값 두 개가 잠정이다** — `silenceDB` −40 · `minSilenceSec` 0.5.
///   크리에이터 **촬영 원본**이 있어야 잴 수 있다 (공개본은 BGM 이 깔려 무음이 없다).
///   3단계 5번(아이폰 촬영본)에서 잰다. 그 전에는 게이트로 걸지 않는다.
public enum AudioAnalyzer {

    public struct Result: Codable, Hashable, Sendable {
        public var windowSec: Double
        /// 창마다 RMS dBFS. 소리가 없으면 −120.
        public var rmsDB: [Double]
        public var silences: [ClosedRange<Double>]
        /// 오디오 트랙이 없으면 true. 무음 스톡 영상 · 그림 장면 (`vertical-substitutes.md §4`).
        public var noAudioTrack: Bool
    }

    public static let windowSec = 0.05
    public static let silenceDB = -40.0
    public static let minSilenceSec = 0.5

    public static func analyze(_ url: URL) async throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return Result(windowSec: windowSec, rmsDB: [], silences: [], noAudioTrack: true)
        }
        let sampleRate = 16_000.0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            // ★ 명시해야 한다. 빼면 빅엔디언 원본(AIFF 등)이 뒤집힌 float 로 나온다 — 최댓값 3.4e38 이었다.
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadCorruptFile)
        }

        let perWindow = Int(sampleRate * windowSec)
        var rms: [Double] = []
        var sumSquares = 0.0, count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            let n = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: n) { samples in
                for i in 0..<n {
                    let s = Double(samples[i])
                    sumSquares += s * s
                    count += 1
                    if count == perWindow {
                        rms.append(decibels(sumSquares / Double(count)))
                        sumSquares = 0; count = 0
                    }
                }
            }
        }
        if count > perWindow / 2 { rms.append(decibels(sumSquares / Double(count))) }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        return Result(windowSec: windowSec, rmsDB: rms, silences: silences(in: rms), noAudioTrack: false)
    }

    /// 16kHz 모노 float 샘플 전부. whisper.cpp 입력 형식이다 (`WhisperCppProvider`).
    /// 오디오 트랙이 없으면 빈 배열.
    public static func mono16k(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            // ★ 명시해야 한다. 빼면 빅엔디언 원본(AIFF 등)이 뒤집힌 float 로 나온다 — 최댓값 3.4e38 이었다.
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        var out: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            let n = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: n) { out.append(contentsOf: UnsafeBufferPointer(start: $0, count: n)) }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return out
    }

    /// 무음 구간. 창 단위 RMS 에서 기준 아래가 `minSilenceSec` 이상 이어진 곳.
    public static func silences(
        in rms: [Double], windowSec: Double = windowSec,
        thresholdDB: Double = silenceDB, minSec: Double = minSilenceSec
    ) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        var start: Int?
        for (i, db) in (rms + [0]).enumerated() {   // 끝에 소리를 하나 붙여 마지막 구간을 닫는다
            if db < thresholdDB {
                if start == nil { start = i }
            } else if let s = start {
                if Double(i - s) * windowSec >= minSec {
                    out.append(Double(s) * windowSec ... Double(i) * windowSec)
                }
                start = nil
            }
        }
        return out
    }

    private static func decibels(_ meanSquare: Double) -> Double {
        meanSquare > 0 ? max(10 * log10(meanSquare), -120) : -120
    }
}
