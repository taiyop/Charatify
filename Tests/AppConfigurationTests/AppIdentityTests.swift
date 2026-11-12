import XCTest
import AppConfiguration
import CharacterMediaKit

final class AppIdentityTests: XCTestCase {
    func testReleaseRemainsCompatibleAndUnbundledRunsDefaultToDevelopment() {
        XCTAssertEqual(AppIdentity.release.bundleIdentifier, "dev.local.CharacterNotification")
        XCTAssertEqual(AppIdentity.release.mediaRoot(in: URL(fileURLWithPath: "/tmp")).lastPathComponent, "CharacterNotification")
        XCTAssertEqual(AppIdentity.resolve(bundleIdentifier: "dev.local.CharacterNotification"), .release)
        XCTAssertEqual(AppIdentity.resolve(bundleIdentifier: "dev.local.CharacterNotification.dev"), .development)
        XCTAssertEqual(AppIdentity.resolve(bundleIdentifier: nil), .development)
        XCTAssertEqual(AppIdentity.resolve(bundleIdentifier: "unknown"), .development)
        XCTAssertNotEqual(AppIdentity.release.bundleIdentifier, AppIdentity.development.bundleIdentifier)
    }

    func testResettingDevMediaCannotDeleteReleaseMediaOrIconCache() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let dev = AppIdentity.development.mediaRoot(in: base)
        let release = AppIdentity.release.mediaRoot(in: base)
        for root in [dev, release] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("CharacterIcon"), withIntermediateDirectories: true)
            try Data("saved media".utf8).write(to: root.appendingPathComponent("character.png"))
            try Data("cached icon".utf8).write(to: root.appendingPathComponent("CharacterIcon/icon.png"))
        }
        try await CharacterMediaStore(root: dev).reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dev.appendingPathComponent("character.png").path))
        XCTAssertEqual(try Data(contentsOf: release.appendingPathComponent("character.png")), Data("saved media".utf8))
        XCTAssertEqual(try Data(contentsOf: release.appendingPathComponent("CharacterIcon/icon.png")), Data("cached icon".utf8))
    }
}
