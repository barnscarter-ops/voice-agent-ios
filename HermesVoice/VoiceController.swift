import Foundation
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
    private var services: [RTVIServiceOption] = []

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
            enableCam: false,
            params: RTVIClientParams(
                config: [
                    .init(
                        service: SmallWebRTCTransport.SERVICE_NAME,
                        options: [
                            .init(name: "endpoint", value: .string(url.absoluteString)),
                        ]
                    ),
                ]
            ),
            callbacks: nil
        )

        let client = PipecatClient(options: options)
        self.pipecatClient = client

        // Register delegates for state updates
        client.delegate = self

        // Start the connection — the SDK does the SDP offer/answer dance
        let apiRequest = APIRequest(endpoint: url)
        client.startBotAndConnect(startBotParams: apiRequest) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.phase = .listening
                case .failure(let error):
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

    // MARK: - Interrupt

    /// Interrupt the bot while it's speaking (barge-in).
    func interrupt() {
        // Pipecat SDK 1.3.0 doesn't expose interrupt directly; handled by VAD internally
    }
}

// MARK: - PipecatClient Delegate

extension VoiceController: PipecatClientDelegate {

    nonisolated func didStartListening(client: PipecatClient) {
        Task { @MainActor in phase = .listening }
    }

    nonisolated func didStopListening(client: PipecatClient) {
        Task { @MainActor in if phase == .listening { phase = .thinking } }
    }

    nonisolated func didStartSpeaking(client: PipecatClient) {
        Task { @MainActor in phase = .speaking }
    }

    nonisolated func didStopSpeaking(client: PipecatClient) {
        Task { @MainActor in if phase == .speaking { phase = .listening } }
    }

    nonisolated func didDisconnect(client: PipecatClient) {
        Task { @MainActor in phase = .disconnected }
    }

    nonisolated func didReceiveUserTranscription(client: PipecatClient, text: String, isFinal: Bool) {
        Task { @MainActor in
            if isFinal {
                userTranscript = text
            }
        }
    }

    nonisolated func didReceiveBotTranscription(client: PipecatClient, text: String, isFinal: Bool) {
        Task { @MainActor in
            if isFinal {
                botTranscript = text
            } else {
                botTranscript += text
            }
        }
    }

    nonisolated func didReceiveError(client: PipecatClient, error: String) {
        Task { @MainActor in
            errorMessage = error
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
