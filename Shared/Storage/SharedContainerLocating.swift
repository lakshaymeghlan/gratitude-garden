import Foundation

/// Resolves the on-disk directory that the app and widget share.
///
/// This is the key dependency-injection seam for storage: production code uses
/// `AppGroupContainerLocator` (the real App Group container), while tests inject a locator that
/// points at a throwaway temp directory — so the persistence layer can be tested fully without
/// any entitlement or simulator.
protocol SharedContainerLocating {
    /// The shared directory. Throws if it cannot be reached (e.g. the App Group capability is
    /// missing or the identifier doesn't match the entitlement).
    func containerURL() throws -> URL
}

enum SharedContainerError: Error, LocalizedError {
    case appGroupUnavailable(identifier: String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let id):
            return """
            Could not access the App Group container for "\(id)". Verify the App Group capability \
            is enabled on this target and its identifier exactly matches AppGroup.identifier.
            """
        }
    }
}

/// Production locator: asks the system for the real App Group container URL.
struct AppGroupContainerLocator: SharedContainerLocating {
    let identifier: String
    let fileManager: FileManager

    init(identifier: String = AppGroup.identifier, fileManager: FileManager = .default) {
        self.identifier = identifier
        self.fileManager = fileManager
    }

    func containerURL() throws -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // App Group unavailable (e.g. an unsigned simulator build with no provisioned group). Fall
        // back to the app's own Application Support so the app still works standalone. Real
        // app↔widget data sharing requires the App Group (a signed build with the capability).
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("GratitudeGarden", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
