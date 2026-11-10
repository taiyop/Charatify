import Foundation
import CoreGraphics

public enum CharacterShape: String, Codable, CaseIterable, Sendable {
    case automatic, original, rounded, circle, square
    public var label: String {
        switch self {
        case .automatic: "自動"
        case .original: "元の形"
        case .rounded: "角丸"
        case .circle: "円形"
        case .square: "四角"
        }
    }
    public var usesSquareFrame: Bool { self == .rounded || self == .circle || self == .square }
}

public enum CharacterFit: String, Codable, CaseIterable, Sendable {
    case fit, fill
    public var label: String { self == .fit ? "全体を表示" : "枠いっぱい" }
}

public enum CharacterBorderColor: String, Codable, CaseIterable, Sendable {
    case white, mint, pink, charcoal
    public var label: String {
        switch self {
        case .white: "白"
        case .mint: "ミント"
        case .pink: "ピンク"
        case .charcoal: "チャコール"
        }
    }
    public var rgb: UInt32 {
        switch self {
        case .white: 0xFFFFFF
        case .mint: 0x86D6C9
        case .pink: 0xFF9DAB
        case .charcoal: 0x4A3F47
        }
    }
}

public struct CharacterAppearance: Codable, Equatable, Sendable {
    public var shape: CharacterShape = .automatic
    public var fit: CharacterFit = .fill
    public var cornerRadius: Double = 0.12
    public var borderWidth: Double = 3
    public var borderColor: CharacterBorderColor = .white
    public var shadow = true
    public init() {}

    public var clamped: Self {
        var result = self
        result.cornerRadius = cornerRadius.isFinite ? min(0.5, max(0, cornerRadius)) : 0.12
        result.borderWidth = borderWidth.isFinite ? min(8, max(0, borderWidth)) : 3
        return result
    }

    public func frame(source: CGSize, size: CGFloat) -> CGSize {
        if shape.usesSquareFrame { return CGSize(width: size, height: size) }
        let width = max(1, source.width), height = max(1, source.height)
        let scale = size / max(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
