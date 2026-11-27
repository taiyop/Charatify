import AppKit
import Combine
import SwiftUI
import AppConfiguration
import CharacterIconKit
import NotificationCore

@main
struct CharatifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = SettingsStore()
    private let monitor = NotificationMonitor()
    private let notificationTest = NotificationTest()
    private let updater = AppUpdater()
    private var overlay: OverlayController!
    private var characterIcon: CharacterIconController!
    private var statusItem: NSStatusItem!
    private var menuBarIconSubscription: AnyCancellable?
    private var dockPresentationSubscription: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var classifier = ExpressionClassifier()
    /// Serializes sender lookups so notices keep their arrival order.
    private var lastDelivery: Task<Void, Never>?
    private var deliveryGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Do not run two readers/overlays when the user opens the app again.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }
        updater.start()
        characterIcon = CharacterIconController(settings: settings)
        characterIcon.start()
        overlay = OverlayController(settings: settings)
        monitor.onNotice = { [weak self] in self?.deliver($0) }
        monitor.isEnabled = { [weak self] in self?.settings.enabled ?? false }
        monitor.onMonitoringSuspended = { [weak self] in self?.clearOverlay() }
        overlay.onOpen = { [weak self] in self?.open($0) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = AppIdentity.current.displayName
        let defaultIcon = Bundle.main.url(forResource: "Charatify", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        menuBarIconSubscription = settings.$useCharacterMenuBarIcon.combineLatest(characterIcon.$currentIcon).sink { [weak self] useCharacter, image in
            // Use the published values: @Published emits before storage changes.
            self?.statusItem.button?.image = IconImageAssembler.menuBarIcon(
                useCharacter: useCharacter,
                characterIcon: image,
                defaultIcon: defaultIcon,
                accessibilityDescription: AppIdentity.current.displayName
            )
        }
        let menu = NSMenu()
        if AppIdentity.current.isDevelopment {
            let label = NSMenuItem(title: AppIdentity.current.displayName, action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            menu.addItem(.separator())
        }
        for (title, action, key) in [(String(localized: "設定…"), #selector(openSettings), ","), (String(localized: "表示をテスト"), #selector(testOverlay), "t"), (String(localized: "表示を一時停止／再開"), #selector(toggleEnabled), "p"), (String(localized: "通知をすべて閉じる"), #selector(clearOverlay), "")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let dockVisibility = NSMenuItem(title: String(localized: "Dockに表示"), action: #selector(toggleDockVisibility), keyEquivalent: "")
        dockVisibility.target = self
        menu.addItem(dockVisibility)
        menu.addItem(.separator())
        let checkForUpdates = NSMenuItem(title: String(localized: "アップデートを確認…"), action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdates.target = updater
        menu.addItem(checkForUpdates)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "終了"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        dockPresentationSubscription = settings.$showInDock
            .combineLatest(settings.$useCharacterDockIcon, characterIcon.$currentIcon)
            .sink { showInDock, useCharacter, icon in
                let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
                if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
                guard showInDock else { return }
                NSApp.applicationIconImage = useCharacter ? icon : nil
                NSApp.dockTile.badgeLabel = AppIdentity.current.isDevelopment ? "DEV" : nil
            }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.settings.refreshScreens()
                self?.overlay.reposition()
            }
        }
        monitor.start()
        AppIconResolver.shared.prepare()
        // A normal relaunch opens settings; a login launch stays unobtrusive.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !isLogin { openSettings() }
        if CommandLine.arguments.contains("--preview") { overlay.preview(positioning: true) }
    }

    /// Picks the expression, then hands the notice to the overlay. The sender lookup is
    /// usually a cache hit; notices that arrive meanwhile wait their turn.
    private func deliver(_ notice: Notice) {
        let arrival = Date()
        let generation = deliveryGeneration
        let previous = lastDelivery
        lastDelivery = Task { [weak self] in
            await previous?.value
            guard self?.deliveryGeneration == generation else { return }
            let app = await AppIconResolver.shared.app(for: notice.source)
            guard let self, generation == deliveryGeneration else { return }
            let expressions = classifier.classify(notice, bundleID: app?.bundleID, at: arrival)
            overlay.receive(notice, expressions: expressions)
        }
    }

    /// Clicking the live macOS banner opens the exact conversation/window; once it has
    /// slid away, the best public fallback is to bring the sender app forward.
    private func open(_ notice: Notice) {
        Task {
            if await monitor.openBanner(for: notice) { return }
            _ = await AppIconResolver.shared.activate(source: notice.source)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return false
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = AppIdentity.current.displayName
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, monitor: monitor, overlay: overlay, notificationTest: notificationTest, characterIcon: characterIcon, updater: updater))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settings.refreshScreens()
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func testOverlay() { overlay.preview() }
    @objc private func clearOverlay() {
        deliveryGeneration += 1
        classifier.reset()
        overlay.clear()
    }
    @objc private func toggleDockVisibility() { settings.showInDock.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleDockVisibility) {
            menuItem.state = settings.showInDock ? .on : .off
        }
        return true
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled { overlay.clear() }
        monitor.scan()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
