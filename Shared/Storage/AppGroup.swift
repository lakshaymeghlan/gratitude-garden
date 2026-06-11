import Foundation

/// The single source of truth for the App Group identifier.
///
/// This MUST be identical in three places or the shared container silently resolves to `nil`
/// (no crash — everything just reads as empty/zero):
///   1. This constant.
///   2. The App Group capability on the **app** target.
///   3. The App Group capability on the **widget extension** target.
/// Both targets' `.entitlements` files list the same string under
/// `com.apple.security.application-groups`.
///
/// Convention: `group.` + a reverse-DNS bundle prefix. Change it here once if you use a
/// different team/bundle prefix, then update both entitlements files to match.
enum AppGroup {
    static let identifier = "group.ai.sofsuite.gratitudegarden"
}
