import Foundation
import CoreGraphics

public struct Notice: Equatable, Identifiable {
    public let id: String
    public let source: String
    public let title: String
    public let body: String

    // Some OS versions expose the entire notification as a single "title" field.
    // Put that text in the scrollable message area instead of truncating it as a heading.
    public var displayTitle: String { body.isEmpty ? "" : title }
    public var displayBody: String { body.isEmpty ? title : body }

    public init(id: String, source: String, title: String, body: String) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
    }
}

/// Tracks presence rather than a text hash: two successive identical messages must both arrive.
public struct ArrivalTracker {
    private var visible: Set<String> = []
    private var primed = false

    public init() {}

    public mutating func arrivals(_ notices: [Notice]) -> [Notice] {
        let current = Set(notices.map(\.id))
        defer { visible = current; primed = true }
        guard primed else { return [] } // Never replay banners already present at startup/resume.
        var emitted: Set<String> = []
        return notices.filter { !visible.contains($0.id) && emitted.insert($0.id).inserted }
    }

    public mutating func reset() { visible = []; primed = false }
}

public enum Placement {
    /// AppKit global coordinates; handles negative monitor origins and undersized screens.
    public static func frame(size: CGSize, visible: CGRect, x: Double, y: Double, margin: Double = 20) -> CGRect {
        let width = min(size.width, max(1, visible.width - margin * 2))
        let height = min(size.height, max(1, visible.height - margin * 2))
        let insetX = min(margin, max(0, (visible.width - width) / 2))
        let insetY = min(margin, max(0, (visible.height - height) / 2))
        let travelX = max(0, visible.width - width - insetX * 2)
        let travelY = max(0, visible.height - height - insetY * 2)
        return CGRect(x: visible.minX + insetX + travelX * min(1, max(0, x)),
                      y: visible.minY + insetY + travelY * min(1, max(0, y)),
                      width: width, height: height)
    }

    /// Places content of `size` so it grows up and sideways from the bottom centre of `base`
    /// (where the character stands), shifting only as far as needed to stay on screen.
    public static func anchored(size: CGSize, base: CGRect, visible: CGRect, margin: Double = 20) -> CGRect {
        let width = min(size.width, max(1, visible.width - margin * 2))
        let height = min(size.height, max(1, visible.height - margin * 2))
        let insetX = min(margin, max(0, (visible.width - width) / 2))
        let insetY = min(margin, max(0, (visible.height - height) / 2))
        let x = min(max(base.midX - width / 2, visible.minX + insetX), visible.maxX - insetX - width)
        let y = min(max(base.minY, visible.minY + insetY), visible.maxY - insetY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The reference box (as stored by `normalized`) that an anchored frame grew from.
    public static func base(of frame: CGRect, baseSize: CGSize) -> CGRect {
        CGRect(x: frame.midX - baseSize.width / 2, y: frame.minY, width: baseSize.width, height: baseSize.height)
    }

    public static func normalized(frame: CGRect, visible: CGRect, margin: Double = 20) -> CGPoint {
        let tx = max(0, visible.width - frame.width - margin * 2)
        let ty = max(0, visible.height - frame.height - margin * 2)
        return CGPoint(x: tx == 0 ? 0.5 : min(1, max(0, (frame.minX - visible.minX - margin) / tx)),
                       y: ty == 0 ? 0.5 : min(1, max(0, (frame.minY - visible.minY - margin) / ty)))
    }
}

/// A small, platform-independent AX snapshot. Notification text never needs to be persisted.
public struct AXNode {
    public var role: String
    public var subrole: String
    public var identifier: String
    public var text: String
    public var children: [AXNode]

    public init(role: String = "", subrole: String = "", identifier: String = "", text: String = "", children: [AXNode] = []) {
        self.role = role; self.subrole = subrole; self.identifier = identifier
        self.text = text; self.children = children
    }
}

public enum BannerParser {
    public static let bannerRoles: Set<String> = [
        "AXNotificationCenterBanner", "AXNotificationCenterAlert",
        "AXNotificationCenterNotification", "AXNotificationCenterBannerWindow"
    ]

    public static func notices(in root: AXNode) -> [Notice] {
        // Deliberately exclude stacks/history containers: reading a whole stack as a single
        // message risks replaying old history or mixing text from different notifications.
        if bannerRoles.contains(root.subrole) {
            let nested = root.children.flatMap { notices(in: $0) }
            if !nested.isEmpty { return nested }
            let fields = textFields(root)
            guard !fields.isEmpty else { return [] }
            let source = fields.first(where: { $0.0 == "header" })?.1 ?? "通知"
            let title = fields.first(where: { $0.0 == "title" })?.1 ?? ""
            let body = fields.filter { $0.0 != "header" && $0.0 != "title" }.map(\.1).joined(separator: "\n")
            let fallback = fields.map(\.1).joined(separator: "\n")
            return [Notice(id: root.identifier.isEmpty ? fallback : root.identifier,
                           source: source, title: title, body: body)]
        }
        return root.children.flatMap { notices(in: $0) }
    }

    private static func textFields(_ node: AXNode, inheritedField: String = "") -> [(String, String)] {
        // Buttons contain actions (Reply, Close, etc.), never message content.
        guard node.role != "AXButton" && node.role != "AXMenuButton" else { return [] }
        let field = ["header", "title", "body"].contains(node.identifier) ? node.identifier : inheritedField
        if node.role == "AXStaticText", !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [(field, String(node.text.prefix(4000)))]
        }
        return node.children.flatMap { textFields($0, inheritedField: field) }
    }
}
