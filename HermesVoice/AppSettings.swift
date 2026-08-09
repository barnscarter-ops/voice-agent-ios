import Foundation

/// User-visible configuration for the Pipecat realtime server.
///
/// The server URL points at the Pipecat FastAPI server (e.g.
/// `http://100.124.216.11:7860`) running on the PC. No token is needed —
/// the Pipecat server has no auth layer (tailnet-only).
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let serverURL = "pipecatServerURL"
    }

    /// The Pipecat server address (e.g. `http://100.124.216.11:7860`).
    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Key.serverURL) }
    }

    init() {
        let defaults = UserDefaults.standard
        serverURLString = defaults.string(forKey: Key.serverURL) ?? ""
    }

    /// Parsed URL or nil. Tolerates a bare `host:port` by prepending `http://`.
    /// The Pipecat iOS SDK handles internal routing (/start → /api/offer).
    var pipecatServerURL: URL? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url.appendingPathComponent("start")
    }

    var isConfigured: Bool { pipecatServerURL != nil }
}
