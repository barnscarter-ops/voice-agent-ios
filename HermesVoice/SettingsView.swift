import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var urlDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://100.87.155.47:7860", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Pipecat server")
                } footer: {
                    Text("Your AIWA host's Tailscale address and the Pipecat server port (default 7860). Reachable only over the tailnet.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        settings.serverURLString = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                urlDraft = settings.serverURLString
            }
        }
    }
}
