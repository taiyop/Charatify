import Foundation
import XCTest
@testable import Charatify

final class GitHubUpdatesTests: XCTestCase {
    func testVersionsSortNumericallyAndStableSupersedesItsNightly() throws {
        let expected = ["0.9.9", "0.10.0-nightly.20261126.99", "0.10.0-nightly.20261127.9",
                        "0.10.0-nightly.20261127.10", "0.10.0", "0.10.1"]
        let versions = try expected.map { try XCTUnwrap(UpdateVersion($0), $0) }
        XCTAssertEqual(versions.reversed().sorted(), versions)
        for invalid in ["", "0.1", "0.١.2", "0.1.2-beta", "0.1.2-nightly", "0.1.2-nightly.11.2",
                        "0.1.2-nightly.20261127.0", "0.1.2-nightly.20261127.+2"] {
            XCTAssertNil(UpdateVersion(invalid), invalid)
        }
    }

    func testAssetSelectionIncludesUnnotarizedStableAndIgnoresLegacyDMG() throws {
        let zip = "Charatify-0.3.2-macos-universal-unnotarized.zip"
        let release = release("v0.3.2", assets: [zip, "SHA256SUMS"])
        let update = try XCTUnwrap(GitHubUpdate(release: release, includesNightly: false, requiresDeveloperID: false))
        XCTAssertEqual(update.archiveName, zip)
        XCTAssertEqual(update.downloadURL(for: zip).absoluteString,
                       "https://github.com/taiyop/Charatify/releases/download/v0.3.2/\(zip)")
        XCTAssertFalse(update.developerSigned)
        XCTAssertNil(GitHubUpdate(release: release, includesNightly: false, requiresDeveloperID: true))

        let legacy = self.release("0.3.1", prerelease: true, assets: ["Charatify-0.3.1-unnotarized.dmg"])
        XCTAssertNil(GitHubUpdate(release: legacy, includesNightly: true, requiresDeveloperID: false))
    }

    func testNightlyAndDraftsAreFilteredAndIncompleteAssetsAreIgnored() throws {
        let tag = "0.3.3-nightly.20261127.32"
        let zip = "Charatify-\(tag)-macos-universal.zip"
        let nightly = release(tag, prerelease: true, assets: [zip, "SHA256SUMS"])
        XCTAssertNil(GitHubUpdate(release: nightly, includesNightly: false, requiresDeveloperID: false))
        XCTAssertTrue(try XCTUnwrap(GitHubUpdate(release: nightly, includesNightly: true,
                                                requiresDeveloperID: true)).developerSigned)
        let draft = release(tag, draft: true, prerelease: true, assets: [zip, "SHA256SUMS"])
        let incomplete = release(tag, prerelease: true, assets: [zip])
        let unfinished = GitHubRelease(tagName: tag, draft: false, prerelease: true,
                                       assets: [.init(name: zip, state: "starter"),
                                                .init(name: "SHA256SUMS", state: "uploaded")])
        for release in [draft, incomplete, unfinished] {
            XCTAssertNil(GitHubUpdate(release: release, includesNightly: true, requiresDeveloperID: false))
        }
    }

    func testChecksumMustIdentifyExactlyOneMatchingArchive() throws {
        let hash = String(repeating: "f", count: 64)
        XCTAssertEqual(try GitHubUpdates.checksum(in: Data("\(hash.uppercased()) *update.zip\r\n".utf8),
                                                 for: "update.zip"), hash)
        for manifest in ["\(hash)  other.zip", "\(hash)  update.zip\n\(hash)  update.zip", "bad  update.zip"] {
            XCTAssertThrowsError(try GitHubUpdates.checksum(in: Data(manifest.utf8), for: "update.zip"))
        }
    }

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String]) -> GitHubRelease {
        GitHubRelease(tagName: tag, draft: draft, prerelease: prerelease,
                      assets: assets.map { .init(name: $0, state: "uploaded") })
    }
}
