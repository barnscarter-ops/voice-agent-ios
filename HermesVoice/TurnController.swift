import Foundation
import SwiftUI

/// Drives one turn: record, send, play. Owns the phase the UI renders.
@MainActor
final class TurnController: ObservableObject {
    /// Result of the cheap `GET /health` probe, shown as a banner. Separate from
    /// `phase` because it is about the connection, not about a turn — you want to
    /// know Tailscale is off *before* you talk for thirty seconds.
    enum BridgeStatus: Equatable {
        case unknown
        case checking
        case reachable
        case unreachable(String)
    }

    @Published private(set) var phase: TurnPhase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var reply = ""
    /// Set when a turn worked but something degraded — speech synthesis failing,
    /// for instance, where the text is still worth showing.
    @Published private(set) var notice: String?
    @Published private(set) var lastTurnSeconds: Double?
    @Published private(set) var recordingSeconds: Double = 0
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var bridgeStatus: BridgeStatus = .unknown

    private let settings: AppSettings
    private let recorder = AudioRecorder()
    private let playback = AudioPlayback()
    private var turnTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?

    /// The bridge rejects clips over 120 s. Stopping at 110 s means a forgotten
    /// recording ends in an answer instead of a two-megabyte upload that is
    /// guaranteed to come back 413.
    private let maxRecordingSeconds: Double = 110

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isRecording: Bool { phase == .recording }

    // MARK: - Reachability

    /// Probe the bridge. Safe to call on every appearance and foreground: it is a
    /// 5-second-timeout GET that needs no token.
    func checkBridge() async {
        guard let url = settings.bridgeURL else {
            bridgeStatus = .unknown
            return
        }
        bridgeStatus = .checking
        let client = BridgeClient(baseURL: url, token: settings.token)
        do {
            try await client.checkHealth()
            bridgeStatus = .reachable
        } catch let failure as TurnFailure {
            switch failure {
            case .unreachable(let detail):
                bridgeStatus = .unreachable(detail)
            default:
                // It answered something, so it is reachable — whatever it said is
                // a problem for an actual turn to report, not for this banner.
                bridgeStatus = .reachable
            }
        } catch {
            bridgeStatus = .unreachable(error.localizedDescription)
        }
    }

    // MARK: - The turn

    func toggle() {
        if isRecording {
            finishRecording()
        } else if !phase.isBusy {
            beginRecording()
        }
    }

    private func beginRecording() {
        turnTask?.cancel()
        turnTask = Task { [weak self] in
            guard let self else { return }
            await self.startRecording()
        }
    }

    private func startRecording() async {
        guard settings.bridgeURL != nil else {
            phase = .problem(.from(.notConfigured("No bridge address yet.")))
            return
        }
        guard !settings.token.isEmpty else {
            phase = .problem(.from(.notConfigured("No token yet.")))
            return
        }
        guard await recorder.requestPermission() else {
            phase = .problem(.from(.microphoneDenied))
            return
        }

        transcript = ""
        reply = ""
        notice = nil
        recordingSeconds = 0

        do {
            try recorder.start()
        } catch let failure as TurnFailure {
            phase = .problem(.from(failure))
            return
        } catch {
            phase = .problem(.from(.recordingFailed(error.localizedDescription)))
            return
        }

        phase = .recording
        startMetering()
    }

    /// Stop recording and run the rest of the turn.
    private func finishRecording() {
        stopMetering()
        let clip: (data: Data, filename: String)
        do {
            clip = try recorder.stopAndRead()
        } catch let failure as TurnFailure {
            phase = .problem(.from(failure))
            return
        } catch {
            phase = .problem(.from(.recordingFailed(error.localizedDescription)))
            return
        }

        phase = .thinking
        turnTask?.cancel()
        turnTask = Task { [weak self] in
            guard let self else { return }
            await self.send(clip: clip)
        }
    }

    private func send(clip: (data: Data, filename: String)) async {
        guard let url = settings.bridgeURL else {
            phase = .problem(.from(.notConfigured("No bridge address yet.")))
            return
        }
        let client = BridgeClient(baseURL: url, token: settings.token)
        let started = Date()

        // Every exit from here on has to hand the audio session back. `defer`
        // rather than a call per branch: playback is awaited inside this
        // function, so this still fires after the reply finishes, and a failed
        // turn can no longer leave the session active — which would keep other
        // apps' audio ducked until the app is force-quit.
        defer { AudioSession.release() }

        let response: ConverseResponse
        do {
            response = try await client.converse(
                clip: clip.data,
                filename: clip.filename,
                sessionID: settings.sessionID,
                target: settings.target
            )
        } catch is CancellationError {
            phase = .idle
            return
        } catch let failure as TurnFailure {
            if case .unreachable(let detail) = failure {
                bridgeStatus = .unreachable(detail)
            }
            phase = .problem(.from(failure))
            return
        } catch {
            phase = .problem(.from(.badResponse(error.localizedDescription)))
            return
        }

        if Task.isCancelled {
            phase = .idle
            return
        }

        bridgeStatus = .reachable
        transcript = response.transcript
        reply = response.reply
        notice = response.notice
        lastTurnSeconds = Date().timeIntervalSince(started)

        // A reply with no audio is a *success* with a degraded leg — the bridge
        // returns the text even when speech synthesis fails, so show it rather
        // than reporting a failed turn.
        guard response.ttsOk,
              let pcm = Data(base64Encoded: response.audioB64 ?? ""),
              !pcm.isEmpty else {
            phase = .idle
            return
        }

        phase = .speaking
        do {
            try await playback.play(
                pcm: pcm,
                sampleRate: response.sampleRate,
                channels: response.channels
            )
            phase = .idle
        } catch let failure as TurnFailure {
            phase = .problem(.from(failure))
        } catch {
            phase = .problem(.from(.playbackFailed(error.localizedDescription)))
        }
    }

    /// Abandon whatever is happening. Never leaves a recording on disk or the
    /// audio session held.
    func cancel() {
        stopMetering()
        turnTask?.cancel()
        turnTask = nil
        recorder.cancel()
        playback.stop()
        AudioSession.release()
        phase = .idle
    }

    func startNewConversation() {
        cancel()
        transcript = ""
        reply = ""
        notice = nil
        lastTurnSeconds = nil
        settings.startNewConversation()
    }

    // MARK: - Metering

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isRecording else { return }
                self.inputLevel = self.recorder.meterLevel()
                self.recordingSeconds += 0.1
                if self.recordingSeconds >= self.maxRecordingSeconds {
                    self.finishRecording()
                    return
                }
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        inputLevel = 0
    }
}
