import Foundation
import CoreGraphics

public struct IconCrop: Codable, Equatable, Sendable {
    /// All persisted/rendering coordinates use TOP-LEFT origin, normalized 0...1.
    /// Scale is an aspect-fill zoom multiplier, never an independent x/y stretch.
    public var x: Double
    public var y: Double
    public var scale: Double

    public init(x: Double = 0.5, y: Double = 0.5, scale: Double = 1) {
        self.x = x; self.y = y; self.scale = scale
    }

    public var clamped: IconCrop {
        IconCrop(x: x.isFinite ? min(1, max(0, x)) : 0.5,
                 y: y.isFinite ? min(1, max(0, y)) : 0.5,
                 scale: scale.isFinite ? min(12, max(1, scale)) : 1)
    }
}

public enum FaceEstimate: String, Codable, Sendable {
    case detected, noFace, multipleFaces, detectionFailed, manual

    public var explanation: String {
        switch self {
        case .detected: "顔の位置を自動で合わせました。必要に応じて調整できます。"
        case .noFace: "顔を検出できませんでした。ドラッグと拡大で顔を合わせてください。"
        case .multipleFaces: "複数の顔があります。使いたい顔に位置と拡大を合わせてください。"
        case .detectionFailed: "顔検出を実行できませんでした。手動で顔を合わせてください。"
        case .manual: "調整した位置を保存しています。"
        }
    }
}

public struct CharacterIconConfiguration: Codable, Equatable, Sendable {
    public let sourceHash: String
    public var crop: IconCrop
    public var estimate: FaceEstimate

    public init(sourceHash: String, crop: IconCrop, estimate: FaceEstimate) {
        self.sourceHash = sourceHash; self.crop = crop.clamped; self.estimate = estimate
    }
}

public enum IconGeometry {
    public static let sizes = [1024, 512, 256, 128, 64, 32, 16]
    public static let body = CGRect(x: 0.14, y: 0.18, width: 0.72, height: 0.58)
    public static let bubbleBounds = CGRect(x: 0.14, y: 0.18, width: 0.72, height: 0.64)
    public static let smallFaceBounds = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    /// One continuous path, shared by background fill, clipping and inner outline.
    /// Coordinates are top-left normalized 0...1, including the short lower-left tail.
    public static func bubblePath() -> CGPath {
        let b = body, r = body.width * 0.18
        let p = CGMutablePath()
        p.move(to: CGPoint(x: b.minX + r, y: b.minY))
        p.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
        p.addQuadCurve(to: CGPoint(x: b.maxX, y: b.minY + r), control: CGPoint(x: b.maxX, y: b.minY))
        p.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
        p.addQuadCurve(to: CGPoint(x: b.maxX - r, y: b.maxY), control: CGPoint(x: b.maxX, y: b.maxY))
        p.addLine(to: CGPoint(x: 0.40, y: b.maxY))
        p.addLine(to: CGPoint(x: 0.265, y: b.maxY + 0.06))
        p.addLine(to: CGPoint(x: 0.30, y: b.maxY))
        p.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
        p.addQuadCurve(to: CGPoint(x: b.minX, y: b.maxY - r), control: CGPoint(x: b.minX, y: b.maxY))
        p.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
        p.addQuadCurve(to: CGPoint(x: b.minX + r, y: b.minY), control: CGPoint(x: b.minX, y: b.minY))
        p.closeSubpath()
        return p
    }

    public static func imageRect(source: CGSize, target: CGRect, crop: IconCrop) -> CGRect {
        let crop = crop.clamped
        let factor = max(target.width / max(1, source.width), target.height / max(1, source.height)) * crop.scale
        let size = CGSize(width: source.width * factor, height: source.height * factor)
        let x = min(target.minX, max(target.maxX - size.width, target.midX - crop.x * size.width))
        let y = min(target.minY, max(target.maxY - size.height, target.midY - crop.y * size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    public static func crop(forTopLeftFace face: CGRect, imageSize: CGSize) -> IconCrop {
        let base = max(bubbleBounds.width / imageSize.width, bubbleBounds.height / imageSize.height)
        let desired = min(body.width * 0.75 / (face.width * imageSize.width), body.height * 0.82 / (face.height * imageSize.height))
        return IconCrop(x: face.midX, y: face.midY, scale: desired / base).clamped
    }

    public static func topLeftRect(fromVision rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}
