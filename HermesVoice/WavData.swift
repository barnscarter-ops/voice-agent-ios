import Foundation

/// Wraps raw PCM in a WAV container.
///
/// The bridge returns signed 16-bit little-endian PCM with its sample rate,
/// deliberately not MP3, so nothing has to decode it. `AVAudioPlayer` still
/// wants a container, and a 44-byte RIFF header is the cheapest way to give it
/// one — no `AVAudioEngine`, no format conversion, no sample-rate guessing.
enum WavData {
    static func wrap(pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign

        var out = Data(capacity: 44 + pcm.count)
        out.append(contentsOf: Array("RIFF".utf8))
        out.appendUInt32LE(UInt32(36 + pcm.count))
        out.append(contentsOf: Array("WAVE".utf8))

        out.append(contentsOf: Array("fmt ".utf8))
        out.appendUInt32LE(16)                       // PCM fmt chunk size
        out.appendUInt16LE(1)                        // format: PCM
        out.appendUInt16LE(UInt16(channels))
        out.appendUInt32LE(UInt32(sampleRate))
        out.appendUInt32LE(UInt32(byteRate))
        out.appendUInt16LE(UInt16(blockAlign))
        out.appendUInt16LE(UInt16(bitsPerSample))

        out.append(contentsOf: Array("data".utf8))
        out.appendUInt32LE(UInt32(pcm.count))
        out.append(pcm)
        return out
    }
}

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ])
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
        ])
    }
}
