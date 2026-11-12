import AppKit
import SwiftUI

/// A dedicated drag target: SwiftUI content and video views need not forward mouse events.
struct WindowDragHandle: View {
    var body: some View {
        Label("ここをつかんで移動", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(BubblePalette.accent)
            .frame(width: 240, height: 34)
            .background(BubblePalette.fill, in: Capsule())
            .overlay(Capsule().stroke(BubblePalette.border, lineWidth: 2))
            .overlay { WindowDragArea() }
            .help("マウスボタンを押したまま動かし、移動先で離してください。最後に「ここに保存」を押します。")
            .accessibilityLabel("通知の配置を移動するドラッグハンドル")
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
        }
    }
}
