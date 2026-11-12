import AppKit
import Foundation

// Package the bundled artwork at every macOS icon size; mark development builds.
guard (3...4).contains(CommandLine.arguments.count),
      CommandLine.arguments.count == 3 || CommandLine.arguments[3] == "--dev",
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("Usage: swift make-app-icon.swift SOURCE.png OUTPUT.iconset [--dev]\n", stderr)
    exit(1)
}
let isDevelopment = CommandLine.arguments.count == 4
let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSGraphicsContext.current?.imageInterpolation = .high
        // Keep the packaged tile's outline smooth at every size and exclude
        // the neutral surround outside the source artwork.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(pixels) * 0.075, dy: CGFloat(pixels) * 0.075),
                     xRadius: CGFloat(pixels) * 0.18, yRadius: CGFloat(pixels) * 0.18).addClip()
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        if isDevelopment {
            NSColor.systemOrange.setFill()
            let badge = NSRect(x: CGFloat(pixels) * 0.42, y: CGFloat(pixels) * 0.06,
                               width: CGFloat(pixels) * 0.54, height: CGFloat(pixels) * 0.27)
            NSBezierPath(roundedRect: badge, xRadius: CGFloat(pixels) * 0.06, yRadius: CGFloat(pixels) * 0.06).fill()
            if pixels >= 32 {
                let text = NSAttributedString(string: "DEV", attributes: [
                    .font: NSFont.boldSystemFont(ofSize: CGFloat(pixels) * 0.17), .foregroundColor: NSColor.white
                ])
                let textSize = text.size()
                text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
