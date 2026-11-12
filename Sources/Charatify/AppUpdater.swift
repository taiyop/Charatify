import AppKit
import Combine
import Sparkle
import AppConfiguration

/// Sparkle owns scheduling and saved preferences. Notification content never enters it.
@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var unavailableReason: String?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        guard !AppIdentity.current.isDevelopment else {
            unavailableReason = "Dev版ではアップデートの確認は行いません。"
            return
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = "このビルドでは更新確認が設定されていません。"
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .assign(to: &$automaticallyChecksForUpdates)
        } catch {
            unavailableReason = "更新確認を開始できません: \(error.localizedDescription)"
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }
}
