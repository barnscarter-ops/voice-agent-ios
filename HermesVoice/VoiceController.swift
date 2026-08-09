import Foundation
import SwiftUI
import PipecatClientIOS
import PipecatClientIOSSmallWebrtc

/// Manages a Pipecat realtime voice session over SmallWebRTC.
///
/// The SDK owns mic capture, audio playback, and the WebRTC transport. This
/// controller configures the client, connects it to the Pipecat server, and
/// surfaces state changes (transcript, connection, errors) to SwiftUI via
/// @Published properties.
@MainActor
final class VoiceController: ObservableObject {

    // MARK: - Published State

    @Published private(set) var phase: VoicePhase = .disconnected
    @Published private(set) var userTranscript = ""
    @Published private(set) var botTranscript = ""
    @Published private(set) var errorMessage: String?

    // MARK: - Private

    private let settings: AppSettings
    private var pipecatClient: PipecatClient?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Connection

    var isConnected: Bool {
        phase == .listening || phase == .thinking || phase == .speaking
    }

    func connect() {
        guard phase == .disconnected else { return }

        guard let url = settings.pipecatServerURL else {
            errorMessage = "No server URL. Add it in Settings."
            return
        }

        phase = .connecting
        errorMessage = nil
        userTranscript = ""
        botTranscript = ""

        let options = PipecatClientOptions(
            transport: SmallWebRTCTransport(),
            enableMic: true,
            enableCam: false
        )

        let client = PipecatClient(options: options)
        client.delegate = self
        self.pipecatClient = client

        let apiRequest = APIRequest(endpoint: url)
        Task {
            do {
                let _ = try await client.startBotAndConnect(startBotParams: apiRequest)
                await MainActor.run { self.phase = .listening }
            } catch {
                await MainActor.run {
                    self.phase = .disconnected
                    self.errorMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func disconnect() {
        let client = pipecatClient
        pipecatClient = nil
        phase = .disconnected
        userTranscript = ""
        botTranscript = ""
        Task {
            try? await client?.disconnect()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Interrupt the bot while it's speaking (barge-in).
    /// Pipecat SDK 1.3.0 handles VAD-based interruption internally;
    /// no explicit interrupt method is exposed.
    func interrupt() {
        // VAD handles barge-in automatically in the server pipeline
    }
}

// MARK: - PipecatClientDelegate

extension VoiceController: PipecatClientDelegate {

    func onConnected() {
        Task { @MainActor in phase = .listening }
    }

    func onDisconnected() {
        Task { @MainActor in phase = .disconnected }
    }

    func onBotStartedSpeaking() {
        Task { @MainActor in phase = .speaking }
    }

    func onBotStoppedSpeaking() {
        Task { @MainActor in if phase == .speaking { phase = .listening } }
    }

    func onUserStartedSpeaking() {
        Task { @MainActor in phase = .listening }
    }

    func onUserStoppedSpeaking() {
        Task { @MainActor in if phase == .listening { phase = .thinking } }
    }

    func onUserTranscript(data: Transcript) {
        Task { @MainActor in
            let text = data.text
            if data.final == true {
                userTranscript = text
            }
        }
    }

    func onBotLlmText(data: BotLLMText) {
        Task { @MainActor in
            let text = data.text
            botTranscript = text
        }
    }

    func onError(message: RTVIMessageInbound) {
        Task { @MainActor in
            errorMessage = "Error: \(message.data ?? "unknown")"
        }
    }
}

// MARK: - Phase

enum VoicePhase: Equatable {
    case disconnected
    case connecting
    case listening
    case thinking
    case speaking

    var isBusy: Bool {
        switch self {
        case .connecting, .listening, .thinking, .speaking: return true
        case .disconnected: return false
        }
    }

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        }
    }

    var symbol: String {
        switch self {
        case .disconnected: return "mic.slash"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .listening: return "waveform"
        case .thinking: return "ellipsis.circle"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .listening: return .accentColor
        case .thinking: return .purple
        case .speaking: return .green
        }
    }
}
