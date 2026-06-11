import SwiftUI

/// App entry point. Owns the long-lived app objects, injects them into the environment, and routes
/// incoming deep links (e.g. `gratitudegarden://compose` from the widget).
@main
struct GratitudeGardenApp: App {
    @State private var router = AppRouter()
    @State private var notifications = NotificationManager()
    @State private var preferences = AppPreferencesModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(notifications)
                .environment(preferences)
                .onOpenURL { url in router.handle(url: url) }
        }
    }
}
