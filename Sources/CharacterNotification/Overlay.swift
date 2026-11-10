import AppKit
import SwiftUI
import NotificationCore
import CharacterMediaKit

struct CharacterFrameShape: Shape {
    let shape: CharacterShape
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        if shape == .circle { return Path(ellipseIn: rect) }
        return Path(roundedRect: rect, cornerRadius: radius)
    }
}

struct CharacterView: View {
    let image: NSImage?
    let size: Double
    var videoURL: URL? = nil
    var appearance = CharacterAppearance()

    var body: some View {
        if let image {
            let style = appearance.clamped
            let decorated = style.shape != .original && (style.shape != .automatic || image.isOpaque || videoURL != nil)
            let frame = style.frame(source: image.size, size: size)
            let radius = style.shape == .rounded ? size * style.cornerRadius : (style.shape == .automatic && decorated ? size * 0.12 : 0)
            let mask = CharacterFrameShape(shape: style.shape, radius: radius)
            ZStack {
                // Also provides a still fallback while AVFoundation prepares a video.
                Image(nsImage: image).resizable().interpolation(.high)
                    .aspectRatio(contentMode: style.shape.usesSquareFrame && style.fit == .fill ? .fill : .fit)
                    .frame(width: frame.width, height: frame.height).clipped()
                if let videoURL {
                    LoopingCharacterVideo(url: videoURL, fit: style.shape.usesSquareFrame ? style.fit : .fit)
                        .frame(width: frame.width, height: frame.height)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(mask)
            .overlay {
                if decorated && style.borderWidth > 0 {
                    let rgb = style.borderColor.rgb
                    mask.stroke(Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255), lineWidth: style.borderWidth * 2)
                        .clipShape(mask)
                }
            }
            .shadow(color: .black.opacity(style.shadow && decorated ? 0.15 : 0), radius: 4, y: 2)
            .padding(3)
            .accessibilityLabel(videoURL == nil ? "通知キャラクター" : "通知キャラクター動画・無音ループ")
        } else {
            Text("🐈").font(.system(size: size * 0.72))
                .frame(width: size, height: size)
                .accessibilityLabel("通知キャラクター")
        }
    }
}

private extension NSImage {
    /// True when the image has no alpha channel (JPEG/HEIC etc.), i.e. it is not a cut-out character.
    var isOpaque: Bool {
        guard let rep = representations.first else { return false }
        return !rep.hasAlpha
    }
}

@MainActor
final class OverlayController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var notice: Notice?
    @Published var positioning = false
    @Published var pendingCount = 0
    /// Bumped on every show so the entrance animation replays, even for a repeated id.
    @Published var showCount = 0
    /// Sized per notice so text wraps into a bigger bubble instead of scrolling.
    @Published var bubbleWidth = BubbleMetrics.baseWidth
    @Published var messageHeight: CGFloat = 0
    @Published var messageScrolls = false
    private var contentSize: CGSize?
    let settings: SettingsStore
    private var panel: NSPanel?
    private var queue: [Notice] = []
    private var hideTask: DispatchWorkItem?
    private var showing = false

    init(settings: SettingsStore) { self.settings = settings }

    /// Reference box for the saved position. The actual panel grows up from its bottom centre.
    var baseSize: CGSize { CGSize(width: 390, height: 262 + settings.characterSize) }

    func receive(_ notice: Notice) {
        guard settings.enabled else { return }
        if positioning { return }
        if showing {
            // Keep a bounded queue in memory, with the newest messages retained.
            if queue.count >= 20 { queue.removeFirst() }
            queue.append(notice)
            pendingCount = queue.count
        } else { show(notice) }
    }

    func preview(positioning: Bool = false) {
        clear()
        self.positioning = positioning
        show(Notice(id: "preview", source: positioning ? "表示位置の調整" : "表示テスト", title: positioning ? "通知の表示位置を決めましょう" : "新しい通知が届きました", body: positioning ? "上の「ここをつかんで移動」をドラッグ。\n好きな場所に移動したら「ここに保存」。" : "通知が届いたときだけ、ここに登場します。\nメッセージを確認したら閉じられます。"))
    }

    private func show(_ notice: Notice) {
        hideTask?.cancel()
        layoutBubble(for: notice)
        self.notice = notice
        showCount += 1
        showing = true
        if panel == nil {
            let newPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.hidesOnDeactivate = false
            newPanel.isReleasedWhenClosed = false
            newPanel.delegate = self
            newPanel.title = "Character Notification"
            newPanel.contentView = NSHostingView(rootView: OverlayView(controller: self, settings: settings))
            panel = newPanel
        }
        reposition()
        panel?.isMovableByWindowBackground = positioning
        panel?.orderFrontRegardless()
        if !positioning { startDismissTimer() }
    }

    func reposition() {
        guard showing, let screen = settings.selectedScreen else { return }
        let visible = screen.visibleFrame
        let base = Placement.frame(size: baseSize, visible: visible, x: settings.x, y: settings.y)
        panel?.setFrame(Placement.anchored(size: contentSize ?? baseSize, base: base, visible: visible), display: true)
    }

    /// Called by the SwiftUI content with its natural size, so the panel hugs the bubble.
    func contentSizeChanged(_ size: CGSize) {
        guard showing, size.width > 1, size.height > 1, size != contentSize else { return }
        contentSize = size
        // While positioning, keep the spot the user dragged to; only grow in place.
        if positioning, let panel {
            let base = Placement.base(of: panel.frame, baseSize: baseSize)
            let visible = (panel.screen ?? settings.selectedScreen)?.visibleFrame ?? panel.frame
            panel.setFrame(Placement.anchored(size: size, base: base, visible: visible), display: true)
        } else { reposition() }
    }

    /// Picks the bubble width and message height up front, measured with the exact text view.
    private func layoutBubble(for notice: Notice) {
        let screenHeight = settings.selectedScreen?.visibleFrame.height ?? 800
        // Keep the whole bubble within about 40% of the screen; scroll only beyond that.
        let cap = max(88, min(BubbleMetrics.maxMessageHeight, screenHeight * 0.4 - 110))
        var width = BubbleMetrics.baseWidth
        var height = BubbleMetrics.messageHeight(notice.displayBody, bubbleWidth: width)
        if height > BubbleMetrics.wideningHeight {
            width = BubbleMetrics.wideWidth
            height = BubbleMetrics.messageHeight(notice.displayBody, bubbleWidth: width)
        }
        bubbleWidth = width
        messageScrolls = height > cap
        messageHeight = min(height, cap)
    }

    func savePosition() {
        guard let panel else { return }
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = lhs.frame.intersection(panel.frame)
            let b = rhs.frame.intersection(panel.frame)
            return a.width * a.height < b.width * b.height
        } ?? settings.selectedScreen
        if let screen {
            let base = Placement.base(of: panel.frame, baseSize: baseSize)
            let point = Placement.normalized(frame: base, visible: screen.visibleFrame)
            settings.displayID = SettingsStore.id(for: screen)
            settings.x = point.x; settings.y = point.y
        }
        clear()
    }

    func dismiss() {
        hideTask?.cancel()
        if queue.isEmpty { clear() }
        else {
            let next = queue.removeFirst()
            pendingCount = queue.count
            show(next)
        }
    }

    func clear() {
        hideTask?.cancel(); hideTask = nil
        queue = []; pendingCount = 0
        panel?.orderOut(nil)
        notice = nil; showing = false; positioning = false; contentSize = nil
    }

    func pauseDismissTimer() { hideTask?.cancel() }

    func startDismissTimer() {
        guard !positioning, showing else { return }
        hideTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.duration, execute: work)
    }
}

// MARK: - Speech bubble UI

enum BubblePalette {
    static let fill = Color.dynamic(light: 0xFFFCF5, dark: 0x2B2A34)
    static let border = Color.dynamic(light: 0x86D6C9, dark: 0x4FB3A6)
    static let accent = Color.dynamic(light: 0x2FA898, dark: 0x5BCABA)
    static let ink = Color.dynamic(light: 0x4A3F47, dark: 0xF3EEF1)
    static let subInk = Color.dynamic(light: 0x8C8189, dark: 0xB8AFB5)
    static let blush = Color.dynamic(light: 0xFF9DAB, dark: 0xF08C9C)
}

private extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func make(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        })
    }
}

enum BubbleMetrics {
    static let baseWidth: CGFloat = 358
    static let wideWidth: CGFloat = 470
    static let horizontalPadding: CGFloat = 20
    /// About 15 lines; anything longer scrolls rather than covering the screen.
    static let maxMessageHeight: CGFloat = 340
    /// Widen the bubble once the text would need more than about 5 lines.
    static let wideningHeight: CGFloat = 115

    @MainActor
    static func messageHeight(_ text: String, bubbleWidth: CGFloat) -> CGFloat {
        let view = MessageText(text: text).frame(width: bubbleWidth - horizontalPadding * 2)
        return ceil(NSHostingView(rootView: view).fittingSize.height)
    }
}

struct MessageText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(BubblePalette.ink)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// A rounded bubble whose tail is part of one continuous outline, so the border has no seam.
struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 24
    var tailHeight: CGFloat = 18
    var tailWidth: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let r = min(cornerRadius, body.height / 2, body.width / 2)
        // The tail leans slightly left and ends at the horizontal centre, right above the character's head.
        let tip = CGPoint(x: body.midX - 2, y: rect.maxY)
        let baseLeft = body.midX - tailWidth * 0.3
        let baseRight = body.midX + tailWidth * 0.7
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: baseRight, y: body.maxY))
        p.addQuadCurve(to: tip, control: CGPoint(x: body.midX + tailWidth * 0.12, y: body.maxY + tailHeight * 0.55))
        p.addQuadCurve(to: CGPoint(x: baseLeft, y: body.maxY), control: CGPoint(x: body.midX - tailWidth * 0.12, y: body.maxY + tailHeight * 0.35))
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct OverlayView: View {
    @ObservedObject var controller: OverlayController
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            if let notice = controller.notice {
                NoticeStage(notice: notice, controller: controller, settings: settings)
                    .id(controller.showCount)
            }
        }
        .padding(.vertical, 10)
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { controller.contentSizeChanged($0) }
        .onHover { inside in
            if inside { controller.pauseDismissTimer() } else { controller.startDismissTimer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// One notification: the character pops up, then the bubble pops out of its head.
private struct NoticeStage: View {
    let notice: Notice
    @ObservedObject var controller: OverlayController
    @ObservedObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var characterIn = false
    @State private var bubbleIn = false
    @State private var appIcon: NSImage?

    private let tailHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 2) {
            if controller.positioning {
                WindowDragHandle().padding(.bottom, 8)
            }
            bubble
                .scaleEffect(bubbleIn || reduceMotion ? 1 : 0.55, anchor: UnitPoint(x: 0.5, y: 1))
                .opacity(bubbleIn ? 1 : 0)
            CharacterStage(image: settings.image, size: settings.characterSize, animated: !reduceMotion, videoURL: settings.videoURL, appearance: settings.appearance)
                .scaleEffect(characterIn || reduceMotion ? 1 : 0.4, anchor: .bottom)
                .opacity(characterIn ? 1 : 0)
        }
        .task(id: "\(settings.showAppIcon)|\(notice.source)") {
            appIcon = settings.showAppIcon ? await AppIconResolver.shared.icon(for: notice.source) : nil
        }
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { characterIn = true; bubbleIn = true }
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { characterIn = true }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.62).delay(0.12)) { bubbleIn = true }
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notice.displayTitle.isEmpty {
                Text(notice.displayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BubblePalette.ink)
                    .lineLimit(2)
            }
            message
            if controller.positioning || controller.pendingCount > 0 { footer }
        }
        .frame(width: controller.bubbleWidth - BubbleMetrics.horizontalPadding * 2, alignment: .leading)
        .padding(.horizontal, BubbleMetrics.horizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, 16 + tailHeight)
        .background {
            ZStack {
                // A soft offset "sticker" shadow keeps the look flat and playful.
                SpeechBubbleShape(tailHeight: tailHeight).fill(BubblePalette.border.opacity(0.35)).offset(y: 4)
                SpeechBubbleShape(tailHeight: tailHeight).fill(BubblePalette.fill)
                SpeechBubbleShape(tailHeight: tailHeight)
                    .stroke(BubblePalette.border, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
        }
        .overlay(alignment: .topLeading) { nameTag.offset(x: 16, y: -13) }
        .overlay(alignment: .topTrailing) { closeButton.offset(x: 6, y: -8) }
        .padding(.top, 14)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var message: some View {
        if controller.messageScrolls {
            // Last resort for very long text: the bubble is already at its maximum size.
            ScrollView { MessageText(text: notice.displayBody) }
                .frame(height: controller.messageHeight)
        } else {
            MessageText(text: notice.displayBody)
        }
    }

    private var nameTag: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().interpolation(.high)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .bold))
                }
                Text(notice.source).font(.system(size: 11.5, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(BubblePalette.accent, in: Capsule())
            .overlay(Capsule().stroke(BubblePalette.fill, lineWidth: 2))
            if controller.pendingCount > 0 {
                Text("あと\(controller.pendingCount)件")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BubblePalette.blush, in: Capsule())
                    .overlay(Capsule().stroke(BubblePalette.fill, lineWidth: 2))
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .fixedSize()
    }

    private var closeButton: some View {
        Button(action: { controller.clear() }) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(BubblePalette.accent)
                .frame(width: 22, height: 22)
                .background(BubblePalette.fill, in: Circle())
                .overlay(Circle().stroke(BubblePalette.border, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("すべて閉じる")
        .accessibilityLabel("すべて閉じる")
    }

    private var footer: some View {
        HStack {
            Spacer()
            if controller.positioning {
                Button(action: { controller.savePosition() }) {
                    Label("ここに保存", systemImage: "pin.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(BubblePalette.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { controller.dismiss() }) {
                    HStack(spacing: 4) {
                        Text("つぎへ").font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 8))
                            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.25]) { content, opacity in
                                content.opacity(opacity)
                            } animation: { _ in .easeInOut(duration: 0.6) }
                    }
                    .foregroundStyle(BubblePalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BubblePalette.accent.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("次の通知")
            }
        }
    }
}

/// The character gently bobs while it is "talking", with a small shadow that breathes with it.
private struct CharacterStage: View {
    let image: NSImage?
    let size: Double
    let animated: Bool
    let videoURL: URL?
    let appearance: CharacterAppearance

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(appearance.shadow ? 0.10 : 0))
                .frame(width: size * 0.5, height: 8)
                .blur(radius: 2)
                .phaseAnimator(animated ? [false, true] : [false]) { content, up in
                    content.scaleEffect(up ? 0.82 : 1)
                } animation: { _ in .easeInOut(duration: 1.3) }
            CharacterView(image: image, size: size, videoURL: videoURL, appearance: appearance)
                .phaseAnimator(animated ? [false, true] : [false]) { content, up in
                    content.offset(y: up ? -9 : -4)
                } animation: { _ in .easeInOut(duration: 1.3) }
        }
    }
}
