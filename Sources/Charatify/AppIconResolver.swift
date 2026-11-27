import AppKit
import NotificationCore

/// Finds the sender app (and its icon) from the banner's app name. Uses only public
/// LaunchServices / bundle metadata — no screen capture. Unknown or ambiguous names yield nil.
@MainActor
final class AppIconResolver {
    static let shared = AppIconResolver()

    private var installed: [AppCandidate] = []
    private var indexedAt: Date?
    private var indexing: Task<[AppCandidate], Never>?
    private var cache: [String: AppCandidate?] = [:]
    private var icons: [String: NSImage] = [:]

    func icon(for source: String) async -> NSImage? {
        guard let app = await app(for: source) else { return nil }
        if let icon = icons[app.path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icons[app.path] = icon
        return icon
    }

    func app(for source: String) async -> AppCandidate? {
        let key = AppMatcher.normalize(source)
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] { return hit }
        if let app = AppMatcher.match(source: source, in: running() + installed) {
            cache[key] = app
            return app
        }
        // Unknown name: the app may have been installed after the last index.
        if indexedAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            await reindex()
            if let app = AppMatcher.match(source: source, in: running() + installed) {
                cache[key] = app
                return app
            }
        }
        cache[key] = .some(nil)
        return nil
    }

    /// Brings the sender app to the front. Used when its banner is no longer on screen.
    func activate(source: String) async -> Bool {
        guard let app = await app(for: source), app.path != Bundle.main.bundlePath else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return (try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)) != nil
    }

    /// Warm the index at launch so the first notification does not wait on disk.
    func prepare() { Task { await reindex() } }

    private func reindex() async {
        if let indexing { _ = await indexing.value; return }
        let task = Task.detached(priority: .utility) { Self.scanInstalled() }
        indexing = task
        installed = await task.value
        indexedAt = Date()
        indexing = nil
        cache = cache.filter { $0.value != nil }
    }

    private func running() -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let url = app.bundleURL, app.processIdentifier != getpid() else { return nil }
            var names = [app.localizedName].compactMap { $0 }
            names += Self.names(for: url)
            return AppCandidate(path: url.path, bundleID: app.bundleIdentifier ?? "", names: names, isRunning: true)
        }
    }

    nonisolated private static func scanInstalled() -> [AppCandidate] {
        let fm = FileManager.default
        let roots = [
            "/Applications", "/System/Applications", "/System/Library/CoreServices",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        var result: [AppCandidate] = []
        for root in roots {
            guard let walker = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                             options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in walker {
                // Top level plus one folder (e.g. Utilities); never inside .app bundles.
                if walker.level >= 2 { walker.skipDescendants() }
                guard url.pathExtension == "app" else { continue }
                let id = Bundle(url: url)?.bundleIdentifier ?? ""
                result.append(AppCandidate(path: url.path, bundleID: id, names: names(for: url), isRunning: false))
            }
        }
        return result
    }

    nonisolated private static func names(for url: URL) -> [String] {
        var names = [FileManager.default.displayName(atPath: url.path), url.deletingPathExtension().lastPathComponent]
        if let bundle = Bundle(url: url) {
            for info in [bundle.localizedInfoDictionary, bundle.infoDictionary].compactMap({ $0 }) {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let name = info[key] as? String { names.append(name) }
                }
            }
            names += userLocalizedNames(bundle)
        }
        return Array(Set(names.filter { !$0.isEmpty }))
    }

    /// Banners use the *user's* language (e.g. 「メッセージ」), but this process may resolve
    /// bundles in English. Read the app's own localized names for the preferred languages.
    nonisolated private static func userLocalizedNames(_ bundle: Bundle) -> [String] {
        let languages = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages)
        guard !languages.isEmpty else { return [] }
        var tables: [[String: Any]] = []
        if let url = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
           let data = try? Data(contentsOf: url),
           let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            tables += languages.compactMap { table[$0] as? [String: Any] }
        }
        for language in languages {
            if let url = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: language),
               let strings = NSDictionary(contentsOf: url) as? [String: Any] {
                tables.append(strings)
            }
        }
        return tables.flatMap { table in ["CFBundleDisplayName", "CFBundleName"].compactMap { table[$0] as? String } }
    }
}
