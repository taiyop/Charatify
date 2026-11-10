import Foundation

/// An app that might have posted a notification. Names are every label macOS may show
/// in a banner header: localized display name, bundle name, Finder name, file name.
public struct AppCandidate: Equatable {
    public let path: String
    public let bundleID: String
    public let names: [String]
    public let isRunning: Bool

    public init(path: String, bundleID: String, names: [String], isRunning: Bool) {
        self.path = path; self.bundleID = bundleID; self.names = names; self.isRunning = isRunning
    }
}

/// Banners expose only the sender's display name, never its bundle ID, so the source app
/// is inferred by name. An ambiguous name resolves to nothing rather than a wrong icon.
public enum AppMatcher {
    public static func normalize(_ name: String) -> String {
        var s = name.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasSuffix(".app") { s = String(s.dropLast(4)) }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func match(source: String, in candidates: [AppCandidate]) -> AppCandidate? {
        let key = normalize(source)
        guard !key.isEmpty else { return nil }
        let hits = candidates.filter { $0.names.contains { normalize($0) == key } }
        // Running apps are the likeliest senders; only fall back to installed ones when none run.
        for group in [hits.filter(\.isRunning), hits] where !group.isEmpty {
            let ids = Set(group.map { $0.bundleID.isEmpty ? $0.path : $0.bundleID.lowercased() })
            // Copies of the same app share an icon; different apps sharing a name do not.
            return ids.count == 1 ? group[0] : nil
        }
        return nil
    }
}
