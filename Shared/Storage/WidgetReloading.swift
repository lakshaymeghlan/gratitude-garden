import Foundation

/// Abstraction over "tell the home-screen widget to refresh."
///
/// Kept as a protocol in `Shared/` so the app's view model can depend on it without `Shared/`
/// importing WidgetKit, and so tests can inject a spy to assert that a reload was requested after
/// a data change. The concrete WidgetKit-backed implementation lives in the app target
/// (`WidgetCenterReloader`).
protocol WidgetReloading {
    func reloadGardenWidget()
}

/// The widget's `kind` string. Shared so the widget declaration and the reloader agree on which
/// timeline to refresh. Must match the `kind:` passed to the widget's `StaticConfiguration`.
enum GardenWidget {
    static let kind = "GratitudeGardenWidget"
}
