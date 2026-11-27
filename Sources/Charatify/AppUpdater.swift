import AppKit
import Combine
import Sparkle
import AppConfiguration

/// Sparkle owns scheduling and automatic update preferences.
@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation, SPUUpdaterDelegate {
    private static let nightlyPreference = "includeNightlyUpdates"
    private static let nightlyVersion = Bundle.main.object(forInfoDictionaryKey: "CharatifyNightlyVersion") as? String

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var includesNightlyUpdates =
        UserDefaults.standard.object(forKey: nightlyPreference) as? Bool ?? (nightlyVersion != nil)
    @Published private(set) var unavailableReason: String?
    private var controller: SPUStandardUpdaterController?

    var versionLabel: String {
        Self.nightlyVersion ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? String(localized: "開発版")
    }

    func start() {
        guard controller == nil else { return }
        guard !AppIdentity.current.isDevelopment else {
            unavailableReason = String(localized: "Dev版ではアップデートの確認は行いません。")
            return
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = String(localized: "このビルドでは更新確認が設定されていません。")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .assign(to: &$automaticallyChecksForUpdates)
        } catch {
            unavailableReason = String(localized: "更新確認を開始できません: \(error.localizedDescription)")
        }
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setIncludesNightlyUpdates(_ enabled: Bool) {
        guard includesNightlyUpdates != enabled else { return }
        includesNightlyUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.nightlyPreference)
        controller?.updater.resetUpdateCycleAfterShortDelay()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        includesNightlyUpdates ? ["nightly"] : []
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }
}
