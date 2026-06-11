import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Subtle haptic feedback, only at the moments that carry emotional weight: saving an entry, the
/// revival ("welcome back"), and reaching the first bloom. Deliberately minimal — no feedback on
/// taps, scrolls, or navigation.
@MainActor
protocol HapticsPlaying {
    func entrySaved()
    func revival()
    func firstBloom()
}

/// Real implementation. Each call is gentle; the heavier `revival`/`firstBloom` are reserved for
/// genuinely rare, meaningful moments.
@MainActor
struct SystemHaptics: HapticsPlaying {
    func entrySaved() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
    func revival() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    func firstBloom() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

/// No-op (used when haptics are disabled, or in previews/tests).
@MainActor
struct NoHaptics: HapticsPlaying {
    func entrySaved() {}
    func revival() {}
    func firstBloom() {}
}
