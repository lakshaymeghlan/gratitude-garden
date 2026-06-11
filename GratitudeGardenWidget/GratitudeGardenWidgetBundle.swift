import WidgetKit
import SwiftUI

/// The widget extension's entry point. A bundle can host multiple widgets later (e.g. a lock-screen
/// variant); for now it contains the single garden widget.
@main
struct GratitudeGardenWidgetBundle: WidgetBundle {
    var body: some Widget {
        GratitudeGardenWidget()
    }
}
