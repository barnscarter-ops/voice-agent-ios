import AVFoundation
import Foundation

/// Records one utterance to an `.m4a` file and hands back its bytes.
///
/// AAC in an m4a container, not WAV: the bridge decodes uploads with ffmpeg and
/// accepts `.m4a`, and a 60-second clip is tens of kilobytes instead of two
/// megabytes — which matters on a phone uplink far more than the encode cost.
@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Ask for the microphone. Returns false if the user has said no, now or
    /// previously — the caller then has to send them to Settings.
    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func start() throws {
        try AudioSession.activateForVoice()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utterance-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            // 24 kHz: the bridge downsamples to 16 kHz for speech-to-text
            // anyway, so anything higher is bytes uploaded and then discarded.
            AVSampleRateKey: 24_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        // The session is live from here, so a failure below has to give it back
        // rather than leaving other apps' audio ducked.
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            AudioSession.release()
            throw TurnFailure.recordingFailed("couldn't open the recorder: \(error.localizedDescription)")
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            AudioSession.release()
            throw TurnFailure.recordingFailed("the recorder wouldn't start")
        }
        self.recorder = recorder
        self.fileURL = url
    }

    /// Stop and return the recorded bytes. The temporary file is always removed,
    /// so a clip never lingers in the container after it has been sent.
    func stopAndRead() throws -> (data: Data, filename: String) {
        guard let recorder, let fileURL else {
            throw TurnFailure.recordingFailed("stop called with nothing recording")
        }
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil

        defer { try? FileManager.default.removeItem(at: fileURL) }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw TurnFailure.recordingFailed("couldn't read the recording: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            throw TurnFailure.recordingFailed("the recording came out empty")
        }
        return (data, fileURL.lastPathComponent)
    }

    /// Throw the recording away — used when a turn is abandoned.
    func cancel() {
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }
    }

    /// Current input level, 0...1, for the recording indicator.
    func meterLevel() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        // averagePower is in dBFS: -160 (silence) to 0 (peak). Below -50 dB is
        // room noise, so treat that as the floor rather than mapping the full
        // range and getting a bar that never moves.
        let db = Double(recorder.averagePower(forChannel: 0))
        let floor = -50.0
        guard db > floor else { return 0 }
        return min(1, (db - floor) / -floor)
    }
}
