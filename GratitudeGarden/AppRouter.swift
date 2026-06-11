import Foundation
import Observation

/// Lightweight app navigation state. Today it just tracks whether the entry composer should be
/// shown — driven by the in-app buttons and by the `gratitudegarden://compose` deep link from the
/// widget. Injected through the environment so any view can request composing.
@MainActor
@Observable
final class AppRouter {
    var isComposing = false

    func requestCompose() { isComposing = true }

    /// Handles an incoming URL (e.g. a widget tap). Returns `true` if it was one of ours.
    @discardableResult
    func handle(url: URL) -> Bool {
        switch GardenDeepLink.route(for: url) {
        case .compose:
            requestCompose()
            return true
        case nil:
            return false
        }
    }
}
