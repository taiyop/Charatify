import AppKit
import Combine
import SwiftUI
import AppConfiguration

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
    private var settingsWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Do not run two readers/overlays when the user opens the app again.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        updater.start()
        characterIcon = CharacterIconController(settings: settings)
        characterIcon.start()
        overlay = OverlayController(settings: settings)
        monitor.onNotice = { [weak self] in self?.overlay.receive($0) }
        monitor.isEnabled = { [weak self] in self?.settings.enabled ?? false }
        monitor.onSessionBlocked = { [weak self] in self?.overlay.clear() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = AppIdentity.current.displayName
        let defaultIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        menuBarIconSubscription = characterIcon.$currentIcon.sink { [weak self] image in
            // Resize a copy so the Dock keeps the full-size, multi-resolution image.
            guard let icon = (image ?? defaultIcon).copy() as? NSImage else { return }
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            icon.accessibilityDescription = AppIdentity.current.displayName
            self?.statusItem.button?.image = icon
        }
        let menu = NSMenu()
        if AppIdentity.current.isDevelopment {
            let label = NSMenuItem(title: AppIdentity.current.displayName, action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            menu.addItem(.separator())
        }
        for (title, action, key) in [("設定…", #selector(openSettings), ","), ("表示をテスト", #selector(testOverlay), "t"), ("表示を一時停止／再開", #selector(toggleEnabled), "p"), ("通知をすべて閉じる", #selector(clearOverlay), "")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let dockVisibility = NSMenuItem(title: "Dockに表示", action: #selector(toggleDockVisibility), keyEquivalent: "")
        dockVisibility.target = self
        menu.addItem(dockVisibility)
        menu.addItem(.separator())
        let checkForUpdates = NSMenuItem(title: "アップデートを確認…", action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdates.target = updater
        menu.addItem(checkForUpdates)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
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
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func testOverlay() { overlay.preview() }
    @objc private func clearOverlay() { overlay.clear() }
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
