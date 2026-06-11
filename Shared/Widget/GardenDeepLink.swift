import Foundation

/// The app's custom URL scheme and the routes the widget can open. Shared so the widget (which
/// *builds* the URL) and the app (which *parses* it) agree on exactly one definition.
///
/// Registered in the app's Info.plist under `CFBundleURLTypes` (see Phase 4 setup steps).
enum GardenDeepLink {
    static let scheme = "gratitudegarden"

    enum Route: Equatable {
        case compose   // open the daily entry composer
    }

    /// `gratitudegarden://compose`
    static var composeURL: URL { URL(string: "\(scheme)://compose")! }

    /// Parses an incoming URL into a known route, or `nil` if it isn't one of ours.
    static func route(for url: URL) -> Route? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "compose": return .compose
        default:        return nil
        }
    }
}
