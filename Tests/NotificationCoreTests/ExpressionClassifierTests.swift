import XCTest
@testable import NotificationCore

final class ExpressionClassifierTests: XCTestCase {
    private func notice(_ source: String, _ title: String = "", _ body: String = "") -> Notice {
        Notice(id: UUID().uuidString, source: source, title: title, body: body)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(hour: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: 0, second: second))!
    }

    func testCategoriesFromBundleIDAndNames() {
        XCTAssertEqual(NoticeCategory.of(bundleID: "com.cmuxterm.app", source: "cmux"), .agent)
        XCTAssertEqual(NoticeCategory.of(bundleID: "COM.HNC.DISCORD", source: "Discord"), .chat)
        XCTAssertEqual(NoticeCategory.of(bundleID: "com.apple.reminders", source: "リマインダー"), .schedule)
        XCTAssertEqual(NoticeCategory.of(bundleID: "com.apple.BTUserNotifications", source: "Bluetooth"), .system)
        // Unresolved names still classify by well-known display names.
        XCTAssertEqual(NoticeCategory.of(bundleID: nil, source: " Slack "), .chat)
        XCTAssertEqual(NoticeCategory.of(bundleID: nil, source: "カレンダー"), .schedule)
        XCTAssertNil(NoticeCategory.of(bundleID: nil, source: "example.com"))
        XCTAssertNil(NoticeCategory.of(bundleID: "com.apple.Safari", source: "Safari"))
    }

    func testKeywordsPreferTroubleThenWaitingThenDone() {
        XCTAssertEqual(ExpressionClassifier.keywordExpression("Build completed with errors"), .trouble)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("Claude needs your permission to use Bash"), .waiting)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("Claude is waiting for your input"), .waiting)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("Task finished"), .done)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("テストが失敗しました"), .trouble)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("実行の許可が必要です"), .waiting)
        XCTAssertEqual(ExpressionClassifier.keywordExpression("タスクが完了しました"), .done)
        // Word boundaries: "abandoned" is not "done", "terror" is not "error".
        XCTAssertNil(ExpressionClassifier.keywordExpression("abandoned terror"))
    }

    func testChatTextNeverTriggersKeywords() {
        let dm = notice("Discord", "friend", "the build failed lol")
        XCTAssertEqual(ExpressionClassifier.baseExpression(for: dm, bundleID: "com.hnc.Discord"), .called)
        let agent = notice("cmux", "Claude Code", "Error: tests failed")
        XCTAssertEqual(ExpressionClassifier.baseExpression(for: agent, bundleID: "com.cmuxterm.app"), .trouble)
        XCTAssertEqual(ExpressionClassifier.baseExpression(for: notice("cmux", "Claude Code"), bundleID: nil), .done)
        XCTAssertEqual(ExpressionClassifier.baseExpression(for: notice("Unknown", "Hi"), bundleID: nil), .normal)
    }

    func testBurstNightAndFallbackOrder() {
        var classifier = ExpressionClassifier()
        let start = date(hour: 14)
        XCTAssertEqual(classifier.classify(notice("Slack"), bundleID: nil, at: start, calendar: calendar), [.called, .normal])
        _ = classifier.classify(notice("Slack"), bundleID: nil, at: start.addingTimeInterval(3), calendar: calendar)
        XCTAssertEqual(classifier.classify(notice("Slack"), bundleID: nil, at: start.addingTimeInterval(6), calendar: calendar),
                       [.hurried, .called, .normal])
        // Outside the window the burst is over.
        XCTAssertEqual(classifier.classify(notice("Slack"), bundleID: nil, at: start.addingTimeInterval(30), calendar: calendar),
                       [.called, .normal])

        classifier.reset()
        XCTAssertEqual(classifier.classify(notice("cmux", "Task failed"), bundleID: nil, at: date(hour: 2), calendar: calendar),
                       [.trouble, .sleepy, .normal])
        XCTAssertEqual(classifier.classify(notice("Unknown"), bundleID: nil, at: date(hour: 2, second: 30), calendar: calendar),
                       [.sleepy, .normal])
    }
}
