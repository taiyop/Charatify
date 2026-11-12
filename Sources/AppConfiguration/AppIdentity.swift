import Foundation

/// The release identity and storage name remain compatible with existing installs.
public enum AppIdentity: Sendable {
    case development
    case release

    public static func resolve(bundleIdentifier: String?) -> AppIdentity {
        bundleIdentifier == AppIdentity.release.bundleIdentifier ? .release : .development
    }

    public static let current = resolve(bundleIdentifier: Bundle.main.bundleIdentifier)

    public var isDevelopment: Bool { self == .development }
    public var bundleIdentifier: String {
        isDevelopment ? "dev.local.CharacterNotification.dev" : "dev.local.CharacterNotification"
    }
    public var displayName: String { isDevelopment ? "Charatify Dev" : "Charatify" }

    public func mediaRoot(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(
            isDevelopment ? "CharacterNotification-Dev" : "CharacterNotification",
            isDirectory: true
        )
    }
}
