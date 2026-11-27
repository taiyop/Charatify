import Foundation

/// A character "face" chosen per notification. `normal` is the main character media;
/// every other expression is optional and falls back along the classifier's preference list.
public enum CharacterExpression: String, Codable, CaseIterable, Sendable {
    case normal
    /// An agent or tool reporting back (task finished, build passed).
    case done
    /// A person reaching out: DMs, mentions, mail.
    case called
    /// Something is blocked on the user: input or permission requests.
    case waiting
    /// Schedules, reminders and system notices.
    case notice
    /// Errors and failures.
    case trouble
    /// Several notifications in quick succession.
    case hurried
    /// Late-night notifications.
    case sleepy

    public static var variants: [CharacterExpression] { allCases.filter { $0 != .normal } }
}

/// What kind of app posted a notification. Inferred from the bundle ID when the banner's
/// app name resolved to one, otherwise from well-known display names.
public enum NoticeCategory: Equatable, Sendable {
    case agent, chat, schedule, system

    var defaultExpression: CharacterExpression {
        switch self {
        case .agent: .done
        case .chat: .called
        case .schedule, .system: .notice
        }
    }

    static let bundleIDs: [String: NoticeCategory] = {
        var map: [String: NoticeCategory] = [:]
        for id in [
            "com.cmuxterm.app", "com.t3tools.t3code", "com.meta.endo", "com.google.antigravity",
            "com.google.geminimacos", "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
            "com.todesktop.230313mzl4w4u92", "com.microsoft.vscode", "com.exafunction.windsurf",
            "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.terminal", "dev.warp.warp-stable",
            "dev.zed.zed", "com.apple.dt.xcode", "com.github.githubclient"
        ] { map[id] = .agent }
        for id in [
            "com.hnc.discord", "com.tinyspeck.slackmacgap", "com.apple.mobilesms", "com.apple.mail",
            "com.apple.facetime", "jp.naver.line.mac", "net.whatsapp.whatsapp", "ru.keepcoder.telegram",
            "com.microsoft.teams2", "com.microsoft.outlook", "us.zoom.xos", "com.facebook.archon",
            "org.whispersystems.signal-desktop", "com.readdle.smartemail-mac", "com.chatwork.chatwork"
        ] { map[id] = .chat }
        for id in [
            "com.apple.reminders", "com.apple.ical", "com.apple.notes", "com.apple.clock",
            "com.flexibits.fantastical2.mac", "com.culturedcode.thingsmac", "com.todoist.mac.todoist",
            "com.notion.id", "com.notion.calendar"
        ] { map[id] = .schedule }
        return map
    }()

    static let names: [String: NoticeCategory] = {
        var map: [String: NoticeCategory] = [:]
        for name in ["cmux", "t3 code", "muse", "antigravity", "gemini", "claude", "chatgpt", "codex", "cursor",
                     "visual studio code", "code", "windsurf", "ghostty", "iterm2", "iterm", "terminal", "ターミナル",
                     "warp", "zed", "xcode", "github desktop"] { map[name] = .agent }
        for name in ["discord", "slack", "messages", "メッセージ", "mail", "メール", "facetime", "line", "whatsapp",
                     "telegram", "microsoft teams", "teams", "outlook", "zoom", "messenger", "signal", "spark",
                     "chatwork"] { map[name] = .chat }
        for name in ["reminders", "リマインダー", "calendar", "カレンダー", "notes", "メモ", "clock", "時計",
                     "fantastical", "things", "todoist", "notion calendar"] { map[name] = .schedule }
        return map
    }()

    /// Browsers relay web notifications whose header is the site, so they say nothing about the sender.
    static let neutralBundleIDs: Set<String> = ["com.apple.safari"]

    public static func of(bundleID: String?, source: String) -> NoticeCategory? {
        if let id = bundleID?.lowercased(), !id.isEmpty {
            if let category = bundleIDs[id] { return category }
            if neutralBundleIDs.contains(id) { return nil }
            if id.hasPrefix("com.apple.") { return .system }
        }
        return names[AppMatcher.normalize(source)]
    }
}

/// Chooses expressions for incoming notices. Text is inspected in memory only and never kept;
/// the classifier remembers arrival times alone, for burst detection.
public struct ExpressionClassifier {
    public var burstWindow: TimeInterval = 10
    /// The arrival that makes this many notices within `burstWindow` counts as a burst.
    public var burstCount = 3
    public var nightHours = 0..<5
    private var arrivals: [Date] = []

    public init() {}

    /// Keyword matching is limited to tool/system messages: a person's chat text
    /// ("the build failed lol") should not change how the character greets them.
    public static func keywordExpression(_ text: String) -> CharacterExpression? {
        let rules: [(CharacterExpression, [String], [String])] = [
            (.trouble,
             ["error", "errors", "failed", "failure", "fails", "crash", "crashed", "exception", "denied", "warning"],
             ["エラー", "失敗", "異常", "クラッシュ", "警告", "できませんでした"]),
            (.waiting,
             ["waiting", "permission", "approve", "approval", "confirm", "needs your", "need your",
              "needs input", "requires your", "your input", "your attention", "action required"],
             ["許可", "承認", "確認してください", "入力待ち", "待っています", "待機中", "返答待ち", "選択してください"]),
            (.done,
             ["done", "complete", "completed", "finished", "succeeded", "success", "successful", "passed", "ready"],
             ["完了", "終わりました", "終了しました", "成功", "できました"])
        ]
        for (expression, words, phrases) in rules {
            if phrases.contains(where: { text.contains($0) }) { return expression }
            for word in words {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word).replacingOccurrences(of: " ", with: "\\s+") + "\\b"
                if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return expression }
            }
        }
        return nil
    }

    /// The base expression for a notice, before time-based modifiers.
    public static func baseExpression(for notice: Notice, bundleID: String?) -> CharacterExpression {
        let category = NoticeCategory.of(bundleID: bundleID, source: notice.source)
        if category == .chat { return .called }
        let text = [notice.title, notice.body].filter { !$0.isEmpty }.joined(separator: "\n")
        return keywordExpression(text) ?? category?.defaultExpression ?? .normal
    }

    /// Records an arrival and returns expressions in order of preference, always ending in `.normal`.
    /// Display code uses the first one that has media.
    public mutating func classify(_ notice: Notice, bundleID: String?, at date: Date = Date(),
                                  calendar: Calendar = .current) -> [CharacterExpression] {
        arrivals = arrivals.filter { date.timeIntervalSince($0) < burstWindow && $0 <= date }
        arrivals.append(date)
        let base = Self.baseExpression(for: notice, bundleID: bundleID)
        var result: [CharacterExpression] = []
        // Errors stay recognisable even during a burst or at night.
        if base == .trouble { result.append(.trouble) }
        if arrivals.count >= burstCount { result.append(.hurried) }
        if nightHours.contains(calendar.component(.hour, from: date)) { result.append(.sleepy) }
        result.append(base)
        result.append(.normal)
        var seen: Set<CharacterExpression> = []
        return result.filter { seen.insert($0).inserted }
    }

    public mutating func reset() { arrivals = [] }
}
