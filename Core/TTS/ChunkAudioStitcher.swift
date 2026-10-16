import AVFoundation
import Foundation

/// Concatenates per-chunk CAFs (engine 24 kHz Int16, or an Apple-TTS fallback chunk in whatever
/// format AVSpeechSynthesizer produced) into one 24 kHz mono Int16 paragraph CAF, written by
/// `LocalPCMWriter`.
enum ChunkAudioStitcher {
    static let sampleRate: Double = 24_000

    struct Result {
        var duration: TimeInterval
        var chunkDurations: [TimeInterval]
    }

    static func stitch(_ chunkURLs: [URL], to destination: URL) throws -> Result {
        var all: [Float] = []
        var durations: [TimeInterval] = []
        for url in chunkURLs {
            let samples = try readMono24k(url)
            durations.append(Double(samples.count) / sampleRate)
            all.append(contentsOf: samples)
        }
        try LocalPCMWriter.write(all, sampleRate: Int(sampleRate), to: destination)
        return Result(duration: Double(all.count) / sampleRate, chunkDurations: durations)
    }

    /// Read any PCM audio file → mono Float32 @ 24 kHz.
    static func readMono24k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames)
        else { return [] }
        try file.read(into: inBuffer)

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        else { throw stitchError("Could not build 24 kHz mono format") }

        if inFormat.sampleRate == sampleRate, inFormat.channelCount == 1,
           inFormat.commonFormat == .pcmFormatFloat32, let data = inBuffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(inBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw stitchError("No converter \(inFormat) → 24 kHz mono")
        }
        let ratio = sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw stitchError("Could not allocate output buffer")
        }
        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if status == .error { throw convError ?? stitchError("Conversion failed") }
        guard let data = outBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength)))
    }

    private static func stitchError(_ message: String) -> NSError {
        NSError(domain: "ChunkAudioStitcher", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
