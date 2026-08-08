import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: TurnController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if case .unreachable = controller.bridgeStatus {
                    unreachableBanner
                }

                Spacer(minLength: 0)

                statusBlock

                talkButton

                transcriptBlock

                Spacer(minLength: 0)

                footer
            }
            .padding()
            .navigationTitle("Hermes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .task {
            await controller.checkBridge()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Coming back from the background is exactly when Tailscale may have
            // dropped, so re-probe rather than trusting a stale banner.
            if newPhase == .active {
                Task { await controller.checkBridge() }
            }
        }
    }

    // MARK: - Pieces

    private var unreachableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text("Bridge unreachable").font(.subheadline.weight(.semibold))
                Text("Check Tailscale is on and the PC is awake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") {
                Task { await controller.checkBridge() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: needsSetup ? "gearshape" : controller.phase.symbol)
                Text(needsSetup ? "Not set up yet" : controller.phase.label)
            }
            .font(.headline)
            .foregroundStyle(needsSetup ? .orange : controller.phase.tint)

            // Say so up front rather than letting the talk button sit there
            // disabled and unexplained.
            if needsSetup {
                VStack(spacing: 4) {
                    Text(settings.bridgeURL == nil
                         ? "Add the bridge address and token."
                         : "Add the bridge token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { showingSettings = true }
                        .font(.caption.weight(.semibold))
                }
            }

            if case .problem(let problem) = controller.phase {
                VStack(spacing: 4) {
                    Text(problem.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let hint = problem.hint {
                        Text(hint).font(.caption.weight(.medium))
                    }
                    if problem.kind == .notConfigured || problem.kind == .unauthorized {
                        Button("Open Settings") { showingSettings = true }
                            .font(.caption.weight(.semibold))
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.center)
            }

            if controller.phase == .recording {
                Text(String(format: "%.0fs", controller.recordingSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 90)
    }

    private var talkButton: some View {
        Button {
            controller.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(controller.phase.tint.opacity(0.15))
                    .frame(width: 180, height: 180)
                // Grows with the microphone level so it is obvious the mic is
                // actually hearing something, not just that recording started.
                Circle()
                    .stroke(controller.phase.tint.opacity(0.5), lineWidth: 3)
                    .frame(
                        width: 180 + CGFloat(controller.inputLevel) * 40,
                        height: 180 + CGFloat(controller.inputLevel) * 40
                    )
                Image(systemName: controller.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(controller.phase.tint)
            }
        }
        .buttonStyle(.plain)
        .disabled(disableTalkButton)
        .animation(.easeOut(duration: 0.15), value: controller.inputLevel)
        .accessibilityLabel(controller.isRecording ? "Stop and send" : "Start talking")
    }

    private var needsSetup: Bool {
        !settings.isConfigured && !controller.phase.isBusy
    }

    /// Only the two phases where the app is genuinely mid-turn block the button.
    /// A problem state must stay tappable — otherwise a single failure leaves the
    /// app looking dead until it is force-quit.
    private var disableTalkButton: Bool {
        controller.phase == .thinking || controller.phase == .speaking || !settings.isConfigured
    }

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !controller.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You said").font(.caption).foregroundStyle(.secondary)
                    Text(controller.transcript).font(.body)
                }
            }
            if !controller.reply.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("hermes").font(.caption).foregroundStyle(.secondary)
                    Text(controller.reply).font(.body)
                }
            }
            if let notice = controller.notice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("New conversation") { controller.startNewConversation() }
                .font(.caption)
            Spacer()
            if let seconds = controller.lastTurnSeconds {
                Text(String(format: "%.1fs", seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if controller.phase.isBusy {
                Button("Cancel") { controller.cancel() }
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

/// Wrapper so the preview can build the two objects it needs. A `#Preview`
/// closure is a view builder, not a function body, so the `let` has to live
/// somewhere with a real initializer.
@MainActor
private struct PreviewHost: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        ContentView()
            .environmentObject(settings)
            .environmentObject(TurnController(settings: settings))
    }
}

#Preview {
    PreviewHost()
}
