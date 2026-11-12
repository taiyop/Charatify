import SwiftUI
import AVFoundation
import CharacterMediaKit

/// No playback controls or hit testing: notifications remain draggable and clickable.
struct LoopingCharacterVideo: NSViewRepresentable {
    let url: URL
    let fit: CharacterFit

    func makeNSView(context: Context) -> CharacterVideoSurface { CharacterVideoSurface() }
    func updateNSView(_ view: CharacterVideoSurface, context: Context) { view.configure(url: url, fit: fit) }
    static func dismantleNSView(_ view: CharacterVideoSurface, coordinator: ()) { view.stop() }
}

@MainActor
final class CharacterVideoSurface: NSView {
    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var preparation: Task<Void, Never>?
    private var url: URL?
    private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.player = player
        layer?.addSublayer(playerLayer)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func configure(url: URL, fit: CharacterFit) {
        playerLayer.videoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
        guard self.url != url else { return }
        stop()
        self.url = url
        preparation = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            do {
                // AVPlayerLooper requires duration to be loaded first to avoid blocking the UI.
                _ = try await asset.load(.duration)
                try Task.checkCancellation()
                guard let self, self.url == url else { return }
                self.looper = AVPlayerLooper(player: self.player, templateItem: AVPlayerItem(asset: asset))
                self.updatePlayback()
            } catch { /* The still poster underneath remains visible if playback fails. */ }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    Task { @MainActor in
                        if notification.name == NSWindow.willCloseNotification { self?.player.pause() }
                        else { self?.updatePlayback() }
                    }
                })
            }
        }
        updatePlayback()
    }

    private func updatePlayback() {
        if let window, window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) {
            player.play()
        } else { player.pause() }
    }

    func stop() {
        preparation?.cancel(); preparation = nil
        player.pause(); looper?.disableLooping(); looper = nil
        player.removeAllItems(); url = nil
    }

    deinit {
        preparation?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
