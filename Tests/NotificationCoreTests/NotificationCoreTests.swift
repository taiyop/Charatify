import XCTest
import CoreGraphics
@testable import NotificationCore

final class NotificationCoreTests: XCTestCase {
    func testNegativeOriginAndRoundTrip() {
        let screen = CGRect(x: -1920, y: -500, width: 1920, height: 1080)
        let frame = Placement.frame(size: CGSize(width: 480, height: 260), visible: screen, x: 0.2, y: 0.8)
        XCTAssertTrue(screen.contains(frame))
        let point = Placement.normalized(frame: frame, visible: screen)
        XCTAssertEqual(point.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.8, accuracy: 0.0001)
    }

    func testClampsSmallScreensAndInvalidCoordinates() {
        let screen = CGRect(x: 0, y: 0, width: 320, height: 200)
        let frame = Placement.frame(size: CGSize(width: 480, height: 260), visible: screen, x: -2, y: 4)
        XCTAssertTrue(screen.contains(frame))
    }

    func testAnchoredGrowsUpFromCharacterAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let base = Placement.frame(size: CGSize(width: 390, height: 400), visible: screen, x: 0.5, y: 0)
        let grown = Placement.anchored(size: CGSize(width: 500, height: 600), base: base, visible: screen)
        XCTAssertEqual(grown.midX, base.midX, accuracy: 0.0001)
        XCTAssertEqual(grown.minY, base.minY, accuracy: 0.0001)
        XCTAssertEqual(Placement.base(of: grown, baseSize: base.size), base)

        // Near the top-right corner, the grown frame is pushed back inside the margin.
        let corner = Placement.frame(size: CGSize(width: 390, height: 400), visible: screen, x: 1, y: 1)
        let pushed = Placement.anchored(size: CGSize(width: 500, height: 600), base: corner, visible: screen)
        XCTAssertEqual(pushed.maxX, screen.maxX - 20, accuracy: 0.0001)
        XCTAssertEqual(pushed.maxY, screen.maxY - 20, accuracy: 0.0001)

        // Larger than a tiny screen: still fully visible.
        let tiny = CGRect(x: -800, y: -300, width: 320, height: 240)
        let base2 = Placement.frame(size: CGSize(width: 390, height: 400), visible: tiny, x: 0.5, y: 0)
        XCTAssertTrue(tiny.contains(Placement.anchored(size: CGSize(width: 500, height: 600), base: base2, visible: tiny)))
    }

    func testNoStartupReplayAndIdenticalTextArrivals() {
        var tracker = ArrivalTracker()
        let first = Notice(id: "1", source: "Mail", title: "Hello", body: "Same")
        let second = Notice(id: "2", source: "Mail", title: "Hello", body: "Same")
        XCTAssertEqual(tracker.arrivals([first]), [])
        XCTAssertEqual(tracker.arrivals([first, second, second]), [second])
        XCTAssertEqual(tracker.arrivals([first, second]), [])
        XCTAssertEqual(tracker.arrivals([]), [])
        XCTAssertEqual(tracker.arrivals([first]), [first])
        tracker.reset()
        XCTAssertEqual(tracker.arrivals([second]), [])
    }

    func testBannerTextAndActionExclusion() {
        let banner = AXNode(subrole: "AXNotificationCenterBanner", identifier: "unique", children: [
            AXNode(role: "AXStaticText", identifier: "header", text: "Mail"),
            AXNode(role: "AXStaticText", identifier: "title", text: "Meeting"),
            AXNode(role: "AXStaticText", identifier: "body", text: "Starts soon"),
            AXNode(role: "AXButton", children: [AXNode(role: "AXStaticText", text: "Reply")])
        ])
        XCTAssertEqual(BannerParser.notices(in: banner), [Notice(id: "unique", source: "Mail", title: "Meeting", body: "Starts soon")])
    }

    func testHistoryAndWidgetsAreNotNotifications() {
        let widget = AXNode(role: "AXGroup", children: [AXNode(role: "AXStaticText", text: "Weather")])
        let history = AXNode(subrole: "AXNotificationCenterAlertStack", children: [widget])
        XCTAssertEqual(BannerParser.notices(in: history), [])
        XCTAssertEqual(BannerParser.notices(in: widget), [])
    }

    func testNestedStackSeparatesMessagesAndDoesNotDuplicate() {
        let one = AXNode(subrole: "AXNotificationCenterAlert", identifier: "1", children: [AXNode(role: "AXStaticText", identifier: "body", text: "One")])
        let two = AXNode(subrole: "AXNotificationCenterAlert", identifier: "2", children: [AXNode(role: "AXStaticText", identifier: "body", text: "Two")])
        XCTAssertEqual(BannerParser.notices(in: AXNode(subrole: "AXNotificationCenterBannerWindow", children: [one, two])).map(\.id), ["1", "2"])
    }

    func testSemanticFieldOnContainerAndBodyOnlyNoDuplication() {
        let banner = AXNode(subrole: "AXNotificationCenterAlert", identifier: "1", children: [
            AXNode(role: "AXGroup", identifier: "body", children: [AXNode(role: "AXStaticText", text: "Message")])
        ])
        XCTAssertEqual(BannerParser.notices(in: banner), [Notice(id: "1", source: "通知", title: "", body: "Message")])
    }

    func testCombinedTitleAndBodyRemainsFullyReadable() {
        let text = "キャラクター通知のテスト\n" + String(repeating: "本文をすべて読めます。", count: 20)
        let banner = AXNode(subrole: "AXNotificationCenterBanner", identifier: "live-format", children: [
            AXNode(role: "AXStaticText", identifier: "title", text: text)
        ])
        let notice = BannerParser.notices(in: banner).first!
        XCTAssertEqual(notice.displayTitle, "")
        XCTAssertEqual(notice.displayBody, text)
    }
}

final class AppMatcherTests: XCTestCase {
    private func app(_ path: String, _ id: String, _ names: [String], running: Bool = false) -> AppCandidate {
        AppCandidate(path: path, bundleID: id, names: names, isRunning: running)
    }

    func testMatchesLocalizedNameIgnoringCaseWidthAndSuffix() {
        let apps = [app("/System/Applications/Messages.app", "com.apple.MobileSMS", ["メッセージ", "Messages"]),
                    app("/Applications/Slack.app", "com.tinyspeck.slackmacgap", ["Slack.app"])]
        XCTAssertEqual(AppMatcher.match(source: " メッセージ ", in: apps)?.bundleID, "com.apple.MobileSMS")
        XCTAssertEqual(AppMatcher.match(source: "ＳＬＡＣＫ", in: apps)?.bundleID, "com.tinyspeck.slackmacgap")
        XCTAssertNil(AppMatcher.match(source: "通知", in: apps))
        XCTAssertNil(AppMatcher.match(source: "", in: apps))
    }

    func testPrefersRunningAppAndRejectsAmbiguousNames() {
        let a = app("/Applications/Notes.app", "com.example.notes", ["Notes"])
        let b = app("/Applications/Other/Notes.app", "com.other.notes", ["Notes"])
        XCTAssertNil(AppMatcher.match(source: "Notes", in: [a, b]))
        let running = app(b.path, b.bundleID, b.names, running: true)
        XCTAssertEqual(AppMatcher.match(source: "Notes", in: [a, running])?.bundleID, "com.other.notes")
        // Two copies of one app are not ambiguous.
        let copy = app("/Users/x/Applications/Notes.app", "COM.EXAMPLE.NOTES", ["Notes"])
        XCTAssertEqual(AppMatcher.match(source: "notes", in: [a, copy])?.path, a.path)
    }
}
