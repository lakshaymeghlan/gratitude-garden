import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Production `WidgetReloading`: asks WidgetKit to rebuild the garden widget's timeline.
///
/// Lives in the app target (not `Shared/`) so the WidgetKit dependency stays out of the shared,
/// unit-tested storage layer. Reloading by `kind` (rather than all timelines) is a small courtesy
/// that scopes the refresh to just our widget.
struct WidgetCenterReloader: WidgetReloading {
    func reloadGardenWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: GardenWidget.kind)
        #endif
    }
}
