import SwiftUI

@main
@MainActor
struct HermesVoiceApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var controller: VoiceController

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: VoiceController(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(controller)
        }
    }
}
