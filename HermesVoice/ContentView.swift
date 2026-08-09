import SwiftUI

/// Main view — a single Connect button starts the realtime voice session.
/// The SDK owns audio capture and playback, so there's no record/stop toggle.
/// State transitions (listening → thinking → speaking) come from the Pipecat
/// client callbacks and drive the UI automatically.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: VoiceController
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let error = controller.errorMessage {
                    errorBanner(error)
                }

                Spacer(minLength: 0)

                statusBlock
                connectButton
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
    }

    // MARK: - Pieces

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Error").font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { controller.errorMessage = nil }
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: controller.phase.symbol)
                Text(controller.phase.label)
            }
            .font(.headline)
            .foregroundStyle(controller.phase.tint)
        }
        .frame(minHeight: 60)
    }

    private var connectButton: some View {
        Button {
            if controller.isConnected {
                controller.disconnect()
            } else {
                controller.connect()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(controller.phase.tint.opacity(0.15))
                    .frame(width: 180, height: 180)
                Circle()
                    .stroke(controller.phase.tint.opacity(0.5), lineWidth: 3)
                    .frame(width: 180, height: 180)
                Image(systemName: controller.isConnected ? "phone.down.fill" : "phone.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(controller.phase.tint)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.3), value: controller.phase)
        .accessibilityLabel(controller.isConnected ? "Disconnect" : "Connect")
    }

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !controller.userTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You said").font(.caption).foregroundStyle(.secondary)
                    Text(controller.userTranscript).font(.body)
                }
            }
            if !controller.botTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hermes").font(.caption).foregroundStyle(.secondary)
                    Text(controller.botTranscript).font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if controller.phase.isBusy {
                Button("Disconnect") { controller.disconnect() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }
}

@MainActor
private struct PreviewHost: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        ContentView()
            .environmentObject(settings)
            .environmentObject(VoiceController(settings: settings))
    }
}

#Preview {
    PreviewHost()
}
