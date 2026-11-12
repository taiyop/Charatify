import AppKit
// AX handles predate Swift concurrency. IPC reads are serialized on readQueue;
// observable state and observer registration remain on the main actor.
@preconcurrency import ApplicationServices
import NotificationCore

/// Only reads Notification Center's accessibility tree. No notification DB, hooks,
/// private frameworks, screenshot capture, or content logging.
@MainActor
final class NotificationMonitor: ObservableObject {
    @Published private(set) var status = "権限を確認中"
    @Published private(set) var trusted = false
    @Published private(set) var receivedCount = 0
    @Published private(set) var visibleBannerCount = 0
    var onNotice: ((Notice) -> Void)?
    var isEnabled: () -> Bool = { true }
    private var timer: Timer?
    private var tracker = ArrivalTracker()
    private var wasEnabled = false
    private var pid: pid_t?
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var watchedWindows: [AXUIElement] = []
    private var scanScheduled = false
    private var blockedReasons: Set<String> = []
    private var sessionBlocked: Bool { !blockedReasons.isEmpty }
    private var scanInFlight = false
    private var generation = 0
    private let readQueue = DispatchQueue(label: "dev.local.Charatify.ax", qos: .utility)
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    func start() {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens = [(NSWorkspace.screensDidSleepNotification, "sleep"), (NSWorkspace.sessionDidResignActiveNotification, "session")].map { name, reason in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blockSession(true, reason: reason) }
            }
        }
        workspaceTokens += [(NSWorkspace.screensDidWakeNotification, "sleep"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")].map { name, reason in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blockSession(false, reason: reason) }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, blocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedTokens.append(distributed.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.blockSession(blocked, reason: "lock") }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scan()
    }

    var onSessionBlocked: (() -> Void)?

    private func blockSession(_ blocked: Bool, reason: String) {
        if blocked { blockedReasons.insert(reason) } else { blockedReasons.remove(reason) }
        generation += 1
        tracker.reset()
        if blocked { onSessionBlocked?() }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func attach(to running: NSRunningApplication) {
        detach()
        pid = running.processIdentifier
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        application = app
        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(context).takeUnretainedValue()
            // All AX sources are registered on the main run loop.
            MainActor.assumeIsolated { monitor.scheduleScan() }
        }
        if AXObserverCreate(running.processIdentifier, callback, &newObserver) == .success, let newObserver {
            observer = newObserver
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowCreatedNotification, "AXLayoutChanged", "AXChildrenChanged"] {
                AXObserverAddNotification(newObserver, app, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        }
        tracker.reset()
    }

    private func detach() {
        generation += 1
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; pid = nil; application = nil; watchedWindows = []
    }

    private func scheduleScan() {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scanScheduled = false
            self?.scan()
        }
    }

    func scan() {
        let hadPermission = trusted
        trusted = AXIsProcessTrusted()
        guard trusted else {
            status = "アクセシビリティ権限が必要です"
            detach(); tracker.reset()
            if hadPermission { onSessionBlocked?() }
            return
        }
        guard !sessionBlocked else { status = "画面ロック・スリープ中"; return }
        let enabled = isEnabled()
        guard enabled else {
            if wasEnabled { generation += 1 }
            status = "一時停止中"; tracker.reset(); wasEnabled = false
            return
        }
        if !wasEnabled { tracker.reset() }
        wasEnabled = true
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            status = "通知センターの起動を待っています"; detach(); tracker.reset()
            return
        }
        if pid != running.processIdentifier { attach(to: running) }
        guard let application, !scanInFlight else { return }
        scanInFlight = true
        let ticket = generation
        // IPC can stall if Notification Center is busy. Keep it off the UI thread,
        // serialize reads, and discard results from before lock/pause/restart.
        readQueue.async { [weak self] in
            let result = AXTreeReader.read(application)
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanInFlight = false
                guard self.generation == ticket, !self.sessionBlocked, self.isEnabled(), AXIsProcessTrusted() else { return }
                self.consume(result)
            }
        }
    }

    private func consume(_ result: AXReadResult) {
        if let error = result.error { status = error; return }
        updateWindowObservers(result.windows)
        let roots = result.roots
        // History lists must never be mistaken for new incoming notifications.
        if roots.contains(where: containsHistory) {
            status = "通知センターを閉じると監視を再開します"
            tracker.reset()
            return
        }
        let notices = roots.flatMap { BannerParser.notices(in: $0) }
        visibleBannerCount = notices.count
        let arrivals = tracker.arrivals(notices)
        for notice in arrivals {
            receivedCount += 1
            onNotice?(notice)
        }
        if notices.isEmpty && roots.contains(where: containsUnparsedStack) {
            status = "この通知の形式は未対応です（バナーを個別に読み取れません）"
        } else {
            status = "監視中 · \(receivedCount)件受信"
        }
    }

    private func updateWindowObservers(_ windows: [AXUIElement]) {
        guard let observer else { return }
        let names = ["AXLayoutChanged", "AXChildrenChanged", kAXUIElementDestroyedNotification]
        for old in watchedWindows where !windows.contains(where: { CFEqual($0, old) }) {
            for name in names { AXObserverRemoveNotification(observer, old, name as CFString) }
        }
        for window in windows where !watchedWindows.contains(where: { CFEqual($0, window) }) {
            for name in names { AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque()) }
        }
        watchedWindows = windows
    }

    private func containsHistory(_ node: AXNode) -> Bool {
        // AXNotificationListItems also occurs in live banners, so do not use that ID.
        if ["AXNotificationCenter", "AXNotificationCenterHistory", "AXNotificationCenterList"].contains(node.subrole) { return true }
        return node.children.contains(where: containsHistory)
    }

    private func containsUnparsedStack(_ node: AXNode) -> Bool {
        node.subrole == "AXNotificationCenterAlertStack" || node.children.contains(where: containsUnparsedStack)
    }
}

private struct AXReadResult {
    var windows: [AXUIElement] = []
    var roots: [AXNode] = []
    var error: String?
}

private enum AXTreeReader {
    static func read(_ application: AXUIElement) -> AXReadResult {
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowValue)
        guard result == .success, let windows = windowValue as? [AXUIElement] else {
            return AXReadResult(error: "通知センターを読み取れません（\(result.rawValue)）")
        }
        var budget = 500
        var complete = true
        let deadline = Date().addingTimeInterval(1.5)
        let roots = windows.map { snapshot($0, depth: 0, budget: &budget, complete: &complete, deadline: deadline) }
        guard budget > 0, complete else {
            return AXReadResult(error: "通知の読み取りを再試行中です。通知センターを閉じてください。")
        }
        return AXReadResult(windows: windows, roots: roots)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func snapshot(_ element: AXUIElement, depth: Int, budget: inout Int, complete: inout Bool, deadline: Date) -> AXNode {
        guard depth < 18, budget > 0, Date() < deadline else { complete = false; return AXNode() }
        budget -= 1
        guard let role = attribute(element, kAXRoleAttribute) as? String else { complete = false; return AXNode() }
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        var identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
        if BannerParser.bannerRoles.contains(subrole), identifier.isEmpty {
            // The AX object's stable hash distinguishes simultaneous identical messages.
            identifier = "element-\(CFHash(element))"
        }
        let text: String
        if role == kAXStaticTextRole {
            text = attribute(element, kAXValueAttribute) as? String ?? attribute(element, kAXTitleAttribute) as? String ?? ""
        } else { text = "" }
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if children.count > 150 { complete = false }
        return AXNode(role: role, subrole: subrole, identifier: identifier, text: text,
                      children: children.prefix(150).map { snapshot($0, depth: depth + 1, budget: &budget, complete: &complete, deadline: deadline) })
    }
}
