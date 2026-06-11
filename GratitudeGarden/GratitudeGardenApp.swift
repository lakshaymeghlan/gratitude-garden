import SwiftUI

/// App entry point. Owns the `AppRouter` and `NotificationManager`, injects them into the
/// environment, and routes incoming deep links (e.g. `gratitudegarden://compose` from the widget).
@main
struct GratitudeGardenApp: App {
    @State private var router = AppRouter()
    @State private var notifications = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(notifications)
                .onOpenURL { url in router.handle(url: url) }
        }
    }
}
