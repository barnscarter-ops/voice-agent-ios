import AVFoundation

/// One place that owns the shared `AVAudioSession`.
///
/// Recording and playback both need the same category, and each turn does both,
/// so re-declaring it in two files is how the two ends drift apart — a `.record`
/// category left active is the classic reason the reply plays silently.
enum AudioSession {
    /// `.playAndRecord` for the whole turn rather than switching category
    /// halfway: switching deactivates and reactivates the session, which on a
    /// device produces an audible gap and can drop the first syllable of the
    /// reply.
    static func activateForVoice() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                // Without .defaultToSpeaker a playAndRecord session routes
                // playback to the earpiece, so the reply sounds broken unless
                // the phone is held to your ear.
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: [])
        } catch {
            throw TurnFailure.recordingFailed("audio session unavailable: \(error.localizedDescription)")
        }
    }

    /// Hand audio back to whatever was playing before. Not called between the
    /// record and playback halves of a turn — only when the turn is over.
    static func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
