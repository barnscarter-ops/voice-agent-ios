import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: TurnController
    @Environment(\.dismiss) private var dismiss

    /// Edited locally and applied on Save. Binding straight to `settings.token`
    /// would write a half-typed token to the Keychain on every keystroke.
    @State private var urlDraft = ""
    @State private var tokenDraft = ""
    @State private var revealToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://100.x.y.z:8751", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Bridge address")
                } footer: {
                    Text("Your PC's Tailscale address and the bridge port. Reachable only over the tailnet — there is no public endpoint.")
                }

                Section {
                    HStack {
                        if revealToken {
                            TextField("token", text: $tokenDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("token", text: $tokenDraft)
                        }
                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Token")
                } footer: {
                    Text("The value of VOICE_BRIDGE_TOKEN from .env.bridge on the PC. Stored in the iOS Keychain, not in preferences, and excluded from backups.")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        statusText
                    }
                    Button("Test connection") {
                        applyDrafts()
                        Task { await controller.checkBridge() }
                    }
                    .disabled(urlDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Checks GET /health, which needs no token — so this tells you whether the machine is reachable, separately from whether the token is right.")
                }

                Section {
                    TextField("hermes", text: Binding(
                        get: { settings.target },
                        set: { settings.target = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("Target")
                } footer: {
                    Text("Which backend the bridge should talk to. Leave this as hermes unless you have added another target to the bridge's config.")
                }

                Section {
                    Text(settings.sessionID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Start a new conversation") {
                        controller.startNewConversation()
                    }
                } header: {
                    Text("Conversation")
                } footer: {
                    Text("Scopes history on the bridge. Starting a new one clears what the bridge remembers of this chat — it does not clear anything the backend keeps on its own.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        applyDrafts()
                        Task { await controller.checkBridge() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                urlDraft = settings.bridgeURLString
                tokenDraft = settings.token
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch controller.bridgeStatus {
        case .unknown:
            Text("not checked").foregroundStyle(.secondary)
        case .checking:
            Text("checking…").foregroundStyle(.secondary)
        case .reachable:
            Label("reachable", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unreachable:
            Label("unreachable", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        }
    }

    private func applyDrafts() {
        settings.bridgeURLString = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
