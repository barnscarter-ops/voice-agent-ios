import SwiftUI

/// Where a turn is right now.
enum TurnPhase: Equatable {
    case idle
    case recording
    case thinking
    case speaking
    case problem(TurnProblem)

    var isBusy: Bool {
        switch self {
        case .recording, .thinking, .speaking: return true
        case .idle, .problem: return false
        }
    }
}

/// A failure the user can see, already translated out of error-speak.
///
/// `kind` exists so the UI can look different for a network problem than for a
/// backend fault. Those two are the ones most often confused, and confusing them
/// sends you debugging the wrong machine: "unreachable" means check Tailscale,
/// "backend" means the bridge is fine and hermes is not.
struct TurnProblem: Equatable {
    enum Kind: Equatable {
        /// Nothing answered. Tailscale off, PC asleep, wrong address.
        case unreachable
        /// The bridge answered and refused the token.
        case unauthorized
        /// No URL or no token entered yet.
        case notConfigured
        /// The bridge worked; the thing behind it did not.
        case backend
        /// Normal, expected, try-again: too quiet, no speech, busy.
        case retryable
        /// Microphone or speaker trouble on this device.
        case device
    }

    let kind: Kind
    let headline: String
    let detail: String
    /// What to actually do about it, when there is something to do.
    let hint: String?

    init(kind: Kind, headline: String, detail: String, hint: String? = nil) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.hint = hint
    }

    /// Translate a `TurnFailure` into something worth reading on a phone.
    static func from(_ failure: TurnFailure) -> TurnProblem {
        switch failure {
        case .notConfigured(let detail):
            return TurnProblem(
                kind: .notConfigured,
                headline: "Not set up yet",
                detail: detail,
                hint: "Add your bridge address and token in Settings."
            )

        case .unreachable(let detail):
            return TurnProblem(
                kind: .unreachable,
                headline: "Can't reach the bridge",
                detail: detail,
                hint: "Check Tailscale is on here and the PC is awake. Nothing was sent."
            )

        case .unauthorized:
            return TurnProblem(
                kind: .unauthorized,
                headline: "Token rejected",
                detail: "The bridge is up, but it turned down this token.",
                hint: "Re-enter the token from .env.bridge on the PC."
            )

        case .rejected(let failure):
            if failure.isUserRecoverable {
                return TurnProblem(
                    kind: .retryable,
                    headline: failure.spoken ?? "Didn't catch that",
                    detail: failure.message,
                    hint: failure.code == "busy" ? "A turn is still running. Give it a second." : "Try again."
                )
            }
            return TurnProblem(
                kind: .backend,
                headline: failure.spoken ?? "hermes couldn't answer",
                detail: "\(failure.code) (HTTP \(failure.status)): \(failure.message)",
                hint: "The bridge is reachable — this one is on the PC side."
            )

        case .badResponse(let detail):
            return TurnProblem(
                kind: .backend,
                headline: "Unexpected reply",
                detail: detail,
                hint: "The bridge answered with something this app can't read."
            )

        case .microphoneDenied:
            return TurnProblem(
                kind: .device,
                headline: "Microphone is off",
                detail: "This app doesn't have permission to record.",
                hint: "Turn the microphone on for Hermes in iOS Settings."
            )

        case .recordingFailed(let detail):
            return TurnProblem(kind: .device, headline: "Couldn't record", detail: detail)

        case .playbackFailed(let detail):
            return TurnProblem(
                kind: .device,
                headline: "Couldn't play the reply",
                detail: detail,
                hint: "The answer came back — you can read it above."
            )
        }
    }
}

/// How each phase looks. Kept next to the phase so a new state cannot be added
/// without deciding what it looks like.
extension TurnPhase {
    var label: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .problem(let problem): return problem.headline
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "mic.circle"
        case .recording: return "waveform"
        case .thinking: return "ellipsis.circle"
        case .speaking: return "speaker.wave.2.fill"
        case .problem(let problem):
            switch problem.kind {
            case .unreachable: return "wifi.slash"
            case .unauthorized: return "lock.trianglebadge.exclamationmark"
            case .notConfigured: return "gearshape"
            case .backend: return "exclamationmark.triangle.fill"
            case .retryable: return "arrow.clockwise"
            case .device: return "mic.slash"
            }
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .accentColor
        case .recording: return .red
        case .thinking: return .purple
        case .speaking: return .green
        case .problem(let problem):
            switch problem.kind {
            // Orange, not red: nothing is broken, something is switched off.
            case .unreachable, .notConfigured: return .orange
            case .unauthorized: return .yellow
            case .backend, .device: return .red
            case .retryable: return .secondary
            }
        }
    }
}
