import AVFoundation
import Foundation

/// Plays the reply and returns when it has finished.
///
/// `AVAudioPlayer` reports completion through a delegate callback, so the async
/// method below bridges that to a continuation. The continuation is resumed
/// exactly once — by the delegate, by a decode error, or by `stop()` — and
/// `finish(_:)` is the only thing that touches it, so an early stop during
/// playback cannot crash on a double resume.
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    /// Set when playback ended before the caller reached its `await`. Without
    /// it, a clip short enough to finish inside that window would leave the
    /// caller suspended forever — the one bug in here that would look like the
    /// app hanging rather than failing.
    private var finishedBeforeWaiting = false

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Play signed 16-bit PCM. Returns as soon as playback ends or is stopped.
    ///
    /// Pinned to the main actor, and so is `stop()`. `AVAudioPlayer` delivers its
    /// delegate callbacks on the thread that created it, so keeping creation on
    /// the main thread means the callbacks arrive there too — which is what makes
    /// `continuation` safe to touch from both sides without a lock.
    @MainActor
    func play(pcm: Data, sampleRate: Int, channels: Int) async throws {
        guard !pcm.isEmpty else { return }
        finishedBeforeWaiting = false
        let wav = WavData.wrap(pcm: pcm, sampleRate: sampleRate, channels: channels)

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: wav)
        } catch {
            throw TurnFailure.playbackFailed("couldn't open the reply audio: \(error.localizedDescription)")
        }
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw TurnFailure.playbackFailed("the player wouldn't start")
        }
        self.player = player

        await withCheckedContinuation { continuation in
            if finishedBeforeWaiting {
                finishedBeforeWaiting = false
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    @MainActor
    func stop() {
        player?.stop()
        finish()
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish()
    }

    private func finish() {
        player = nil
        guard let pending = continuation else {
            finishedBeforeWaiting = true
            return
        }
        continuation = nil
        pending.resume()
    }
}
