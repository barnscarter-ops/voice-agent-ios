import Foundation

/// Successful `POST /converse` body. Snake-case keys are mapped by
/// `.convertFromSnakeCase` on the decoder, so the property names here are the
/// camel-case forms of the bridge's field names.
struct ConverseResponse: Decodable {
    let transcript: String
    let reply: String
    let sampleRate: Int
    let channels: Int
    let ttsOk: Bool

    /// Base64 signed 16-bit little-endian PCM — not a container format. Absent
    /// or empty when `ttsOk` is false; the reply text is still present.
    let audioB64: String?

    /// Set when the turn succeeded but something degraded, e.g. speech failed.
    let notice: String?

    // Metadata the app does not act on, so all optional. A required property
    // here would mean one renamed or omitted field on the bridge side turns a
    // perfectly good answer into "couldn't read the bridge's reply".
    let sessionId: String?
    let target: String?
    let audioFormat: String?
    let audioDurationMs: Double?
    let turnCount: Int?
    let timingsMs: [String: Double]?
}

/// The bridge's error envelope: a machine-readable code, a redacted message, and
/// a phrase safe to show or speak.
struct BridgeFailure {
    let status: Int
    let code: String
    let message: String
    let spoken: String?
    let retryable: Bool

    /// `code` values that mean the request never reached the backend and the
    /// user can simply try again — as opposed to a real backend fault.
    var isUserRecoverable: Bool {
        retryable || ["too_quiet", "too_short", "bad_utterance", "stt_fail", "busy"].contains(code)
    }

    /// Decode whatever the bridge returned. FastAPI puts an `HTTPException`
    /// detail under `detail`, but that key is a dict for our own errors, a
    /// *string* for the auth middleware's 401, and an *array* for FastAPI's own
    /// request-validation failures. All three have to land somewhere sensible or
    /// a real error turns into "couldn't decode the error".
    static func parse(status: Int, body: Data) -> BridgeFailure {
        let fallbackMessage = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return BridgeFailure(
                status: status,
                code: "http_\(status)",
                message: fallbackMessage.isEmpty ? "HTTP \(status)" : fallbackMessage,
                spoken: nil,
                retryable: false
            )
        }

        if let detail = root["detail"] as? [String: Any] {
            return BridgeFailure(
                status: status,
                code: detail["code"] as? String ?? "http_\(status)",
                message: detail["message"] as? String ?? "HTTP \(status)",
                spoken: detail["spoken"] as? String,
                retryable: detail["retryable"] as? Bool ?? false
            )
        }

        // Auth middleware: {"error": "unauthorized", "detail": "..."}
        if let error = root["error"] as? String {
            return BridgeFailure(
                status: status,
                code: error,
                message: root["detail"] as? String ?? error,
                spoken: nil,
                retryable: false
            )
        }

        // FastAPI validation: {"detail": [{"loc": [...], "msg": "..."}]}
        if let items = root["detail"] as? [[String: Any]] {
            let messages = items.compactMap { $0["msg"] as? String }
            return BridgeFailure(
                status: status,
                code: "bad_request",
                message: messages.isEmpty ? "request rejected" : messages.joined(separator: "; "),
                spoken: nil,
                retryable: false
            )
        }

        return BridgeFailure(
            status: status,
            code: "http_\(status)",
            message: root["detail"] as? String ?? fallbackMessage,
            spoken: nil,
            retryable: false
        )
    }
}

/// Everything that can go wrong in a turn, split by *who* has to fix it. The
/// split matters: "I can't reach the bridge" and "the backend broke" look
/// identical in a generic error alert and need completely different reactions.
enum TurnFailure: Error {
    /// No bridge URL or no token yet.
    case notConfigured(String)
    /// Transport never completed: no route, refused, timed out. Almost always
    /// Tailscale being off on one end.
    case unreachable(String)
    /// The bridge answered 401 — the token is wrong, not the network.
    case unauthorized
    /// The bridge answered, and said no. Includes backend/hermes faults.
    case rejected(BridgeFailure)
    /// The bridge answered with something unparseable.
    case badResponse(String)
    case microphoneDenied
    case recordingFailed(String)
    case playbackFailed(String)

    /// Map a `URLError` to either `unreachable` or a plain description. Only the
    /// transport-level cases become `unreachable`; a malformed URL is a config
    /// problem and would be a lie to blame on the network.
    static func from(urlError: URLError) -> TurnFailure {
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed,
             .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return .unreachable(urlError.localizedDescription)
        case .badURL, .unsupportedURL:
            return .notConfigured("That bridge URL isn't valid.")
        default:
            return .unreachable(urlError.localizedDescription)
        }
    }
}
