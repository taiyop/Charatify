import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum IconError: LocalizedError {
    case invalidImage, renderFailed, cacheInvalid
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "キャラクター画像を読み込めません。画像を選び直してください。"
        case .renderFailed: "アイコンを生成できませんでした。画像を選び直して再試行してください。"
        case .cacheInvalid: "アイコンのキャッシュが破損しています。"
        }
    }
}

public enum IconComposer {
    /// Decode orientation-aware raster data without NSImage/AppKit drawing on a worker.
    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw IconError.invalidImage }
        return image
    }

    public static func hasTransparency(_ image: CGImage) -> Bool {
        // Alpha-channel images get a pastel backing even when only part of the file is transparent.
        [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(image.alphaInfo)
    }

    public static func compose(image: CGImage, crop: IconCrop, size: Int) throws -> Data {
        guard IconGeometry.sizes.contains(size),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw IconError.renderFailed }
        // Offscreen canvas = 1024×1024 design units, TOP-LEFT origin, normalized 0...1.
        // Every representation is drawn independently; 32/16 use different geometry.
        c.translateBy(x: 0, y: CGFloat(size))
        c.scaleBy(x: CGFloat(size), y: -CGFloat(size))
        c.interpolationQuality = .high
        let small = size <= 32
        if small {
            let whiteBase = CGPath(roundedRect: CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84), cornerWidth: 0.18, cornerHeight: 0.18, transform: nil)
            c.addPath(whiteBase); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
            let clip = CGPath(roundedRect: IconGeometry.smallFaceBounds, cornerWidth: 0.12, cornerHeight: 0.12, transform: nil)
            c.saveGState(); c.addPath(clip); c.clip()
            let zoom = IconCrop(x: crop.x, y: crop.y, scale: crop.scale * 1.15)
            draw(image, in: IconGeometry.imageRect(source: CGSize(width: image.width, height: image.height), target: IconGeometry.smallFaceBounds, crop: zoom), context: c)
            c.restoreGState()
        } else {
            let tile = CGPath(roundedRect: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92), cornerWidth: 0.205, cornerHeight: 0.205, transform: nil)
            c.saveGState(); c.addPath(tile); c.clip()
            let colors = [color(0xDCE9FF), color(0xD9C8F5)] as CFArray
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else { throw IconError.renderFailed }
            c.drawLinearGradient(gradient, start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1), options: [])
            c.restoreGState()
            let bubble = IconGeometry.bubblePath()
            c.addPath(bubble)
            c.setFillColor(hasTransparency(image) ? color(0xE9DFF7) : CGColor(gray: 1, alpha: 1))
            c.fillPath()
            c.saveGState(); c.addPath(bubble); c.clip()
            draw(image, in: IconGeometry.imageRect(source: CGSize(width: image.width, height: image.height), target: IconGeometry.bubbleBounds, crop: crop), context: c)
            // Clip the 5-unit stroke to keep an approximately 2.5px INNER outline at 1024.
            c.addPath(bubble); c.setStrokeColor(color(0x5C4038, alpha: 0.55)); c.setLineWidth(5.0 / 1024)
            c.setLineJoin(.round); c.strokePath(); c.restoreGState()
        }
        guard let rendered = c.makeImage() else { throw IconError.renderFailed }
        return try png(rendered)
    }

    private static func draw(_ image: CGImage, in rect: CGRect, context c: CGContext) {
        // CGImage drawing is bottom-up; locally invert it within the top-left design space.
        c.saveGState()
        c.translateBy(x: rect.minX, y: rect.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: rect.size))
        c.restoreGState()
    }

    private static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw IconError.renderFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw IconError.renderFailed }
        return data as Data
    }
}
