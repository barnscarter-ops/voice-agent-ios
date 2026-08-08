import SwiftUI

/// `@MainActor` on the whole entry point: `AppSettings` and `TurnController` are
/// both main-actor types, and building them in `init()` below is only legal if
/// `init()` is isolated too. Swift 6 makes `App` conformances main-actor
/// implicitly; saying so here means the same source builds either way.
@main
@MainActor
struct HermesVoiceApp: App {
    /// One settings store and one turn controller for the whole app. Both are
    /// built here rather than inside a view, so a view rebuild can never discard
    /// an in-flight turn or a live audio session.
    @StateObject private var settings: AppSettings
    @StateObject private var controller: TurnController

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: TurnController(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(controller)
        }
    }
}
