import Foundation

/// User-visible configuration: where the bridge is, and the token to reach it.
///
/// The URL and session id are ordinary preferences and live in `UserDefaults`.
/// The token does not — see `KeychainStore`.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let bridgeURL = "bridgeURL"
        static let sessionID = "sessionID"
        static let target = "target"
    }

    /// No default URL on purpose. A tailnet address is specific to one machine
    /// and this repository is cloned by a build service, so the address is
    /// something Carter types once on the device, not something baked in.
    @Published var bridgeURLString: String {
        didSet { UserDefaults.standard.set(bridgeURLString, forKey: Key.bridgeURL) }
    }

    /// Which bridge target to converse with. The bridge defaults to `hermes`.
    @Published var target: String {
        didSet { UserDefaults.standard.set(target, forKey: Key.target) }
    }

    /// Held in memory so the UI can bind to it; persisted only to the Keychain.
    @Published var token: String {
        didSet { KeychainStore.saveToken(token) }
    }

    /// Scopes conversation history on the bridge. Stable across launches so a
    /// conversation survives backgrounding; rotate it to start fresh.
    @Published private(set) var sessionID: String

    init() {
        let defaults = UserDefaults.standard
        bridgeURLString = defaults.string(forKey: Key.bridgeURL) ?? ""
        target = defaults.string(forKey: Key.target) ?? "hermes"
        token = KeychainStore.loadToken() ?? ""

        if let existing = defaults.string(forKey: Key.sessionID), !existing.isEmpty {
            sessionID = existing
        } else {
            let fresh = "ios-" + UUID().uuidString
            sessionID = fresh
            defaults.set(fresh, forKey: Key.sessionID)
        }
    }

    /// Parsed form of `bridgeURLString`, or nil while it is unusable.
    var bridgeURL: URL? {
        let trimmed = bridgeURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A bare host is the likeliest thing to be typed on a phone; a URL with
        // no scheme parses with a nil host, which fails much later and less
        // clearly, so fill the scheme in here.
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    var isConfigured: Bool { bridgeURL != nil && !token.isEmpty }

    /// Forget the conversation. The bridge keys history by session id, so a new
    /// id means the next turn starts with no history — note this does not clear
    /// whatever memory the backend keeps on its own side.
    func startNewConversation() {
        let fresh = "ios-" + UUID().uuidString
        sessionID = fresh
        UserDefaults.standard.set(fresh, forKey: Key.sessionID)
    }
}
