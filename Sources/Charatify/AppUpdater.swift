import AppKit
import Combine
import AppConfiguration

@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation {
    private static let automaticPreference = "automaticallyChecksForUpdates"
    private static let nightlyPreference = "includeNightlyUpdates"
    private static let nightlyVersion = Bundle.main.object(forInfoDictionaryKey: "CharatifyNightlyVersion") as? String

    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var includesNightlyUpdates =
        UserDefaults.standard.object(forKey: nightlyPreference) as? Bool ?? (nightlyVersion != nil)
    @Published private(set) var unavailableReason: String?
    @Published private(set) var activity: String?
    private let github = GitHubUpdates()
    private var currentVersion: UpdateVersion?
    private var schedule: Task<Void, Never>?

    var canCheckForUpdates: Bool { currentVersion != nil && activity == nil }

    var versionLabel: String {
        Self.nightlyVersion ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? String(localized: "開発版")
    }

    private var requiresDeveloperID: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CharatifyUpdateRequiresDeveloperID") as? Bool == true
    }

    func start() {
        guard !AppIdentity.current.isDevelopment else {
            unavailableReason = String(localized: "Dev版ではアップデートの確認は行いません。")
            return
        }
        guard let version = UpdateVersion(versionLabel) else {
            unavailableReason = String(localized: "このビルドでは更新確認が設定されていません。")
            return
        }
        currentVersion = version
        let defaults = UserDefaults.standard
        automaticallyChecksForUpdates = (defaults.object(forKey: Self.automaticPreference) as? Bool)
            ?? (defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool) ?? true
        scheduleChecks()
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        check(manual: true)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.automaticPreference)
        scheduleChecks()
    }

    func setIncludesNightlyUpdates(_ enabled: Bool) {
        includesNightlyUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.nightlyPreference)
        scheduleChecks()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }

    private func scheduleChecks() {
        schedule?.cancel()
        schedule = nil
        guard automaticallyChecksForUpdates else { return }
        schedule = Task { [weak self] in
            var delay: Duration = .seconds(8)
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay) }
                catch { return }
                self?.check(manual: false)
                delay = .seconds(86_400)
            }
        }
    }

    private func check(manual: Bool) {
        guard canCheckForUpdates, let currentVersion else { return }
        activity = String(localized: "アップデートを確認中…")
        let includesNightly = includesNightlyUpdates
        Task {
            defer { activity = nil }
            let candidate: GitHubUpdate?
            do {
                candidate = try await github.latest(after: currentVersion, includesNightly: includesNightly,
                                                    requiresDeveloperID: requiresDeveloperID)
            } catch {
                if manual {
                    showProblem(String(localized: "アップデートを確認できませんでした。"), error: error,
                                releaseURL: GitHubUpdates.releasesURL)
                }
                return
            }
            guard manual || automaticallyChecksForUpdates else { return }
            guard let candidate, candidate.version.nightly.isEmpty || includesNightlyUpdates else {
                if manual {
                    showMessage(String(localized: "利用できる新しいアップデートはありません。"))
                }
                return
            }
            guard confirm(candidate), let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
            activity = String(localized: "アップデートをインストール中…")
            do {
                try await AppUpdateInstaller(github: github).install(
                    candidate, over: Bundle.main.bundleURL, currentVersion: versionLabel,
                    bundleIdentifier: bundleIdentifier, requiresDeveloperID: requiresDeveloperID
                )
                NSApp.terminate(nil)
            } catch {
                showProblem(String(localized: "アップデートをインストールできませんでした。"), error: error,
                            releaseURL: candidate.releaseURL)
            }
        }
    }

    private func confirm(_ update: GitHubUpdate) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Charatify \(update.versionLabel) を利用できます。")
        alert.informativeText = String(localized: "インストール後にCharatifyを再起動します。")
        alert.addButton(withTitle: String(localized: "インストールして再起動"))
        alert.addButton(withTitle: String(localized: "あとで"))
        alert.addButton(withTitle: String(localized: "リリースを表示"))
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { NSWorkspace.shared.open(update.releaseURL) }
        return response == .alertFirstButtonReturn
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showProblem(_ message: String, error: Error, releaseURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "閉じる"))
        alert.addButton(withTitle: String(localized: "リリースを表示"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(releaseURL) }
    }
}
