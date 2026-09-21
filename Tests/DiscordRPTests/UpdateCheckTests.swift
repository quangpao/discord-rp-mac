import XCTest
@testable import DiscordRP

/// The comparison rules for a manual update check. No test here touches the network: `interpret` is
/// the pure half, and `fetchLatest` is the only part that can talk to GitHub.
final class UpdateCheckTests: XCTestCase {
    func testANewerReleaseIsDetected() {
        XCTAssertTrue(UpdateCheck.isNewer("1.1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateCheck.isNewer("v1.1.0", than: "1.0.0"), "tags carry a leading v")
        XCTAssertTrue(UpdateCheck.isNewer("2.0.0", than: "1.9.9"))
    }

    func testTheSameOrAnOlderReleaseIsNotAnUpdate() {
        XCTAssertFalse(UpdateCheck.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0.0", than: "1.1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.0.0", than: "1.1.0"))
    }

    func testTenIsNotNewerThanNine() {
        // The trap a plain string comparison falls into: "1.10.0" < "1.9.9" lexically.
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("1.9.9", than: "1.10.0"))
    }

    func testMissingComponentsAndSuffixesCountAsZero() {
        XCTAssertTrue(UpdateCheck.isNewer("2.0", than: "1.9.9"), "2.0 is newer than 1.9.9")
        XCTAssertTrue(UpdateCheck.isNewer("1.2.1", than: "1.2"), "a missing component counts as 0")
        XCTAssertFalse(UpdateCheck.isNewer("1.2.0", than: "1.2"),
                       "1.2 is shorthand for 1.2.0, so it is not an update")
        XCTAssertFalse(UpdateCheck.isNewer("1.2.0-beta.1", than: "1.2.0"),
                       "a pre-release suffix does not make a version newer")
    }

    func testInterpretReportsAnAvailableUpdateWithItsPage() {
        let page = URL(string: "https://github.com/quangpao/discord-rp-mac/releases/tag/v9.9.9")!
        let result = UpdateCheck.interpret(latestTag: "v9.9.9", current: "1.1.0", htmlURL: page)
        XCTAssertEqual(result, .newer(version: "9.9.9", url: page))
    }

    func testInterpretStaysQuietWhenTheRunningVersionIsCurrent() {
        let result = UpdateCheck.interpret(latestTag: "v1.1.0", current: "1.1.0", htmlURL: nil)
        XCTAssertEqual(result, .upToDate(current: "1.1.0"))
    }

    func testInterpretFallsBackToTheReleasesPageAndHandlesAnEmptyTag() {
        XCTAssertEqual(UpdateCheck.interpret(latestTag: "v2.0.0", current: "1.1.0", htmlURL: nil),
                       .newer(version: "2.0.0", url: UpdateCheck.releasesPage))
        guard case .failed = UpdateCheck.interpret(latestTag: "  ", current: "1.1.0", htmlURL: nil) else {
            return XCTFail("an empty tag is a failure, not an update")
        }
    }

    func testTheEndpointsAreHTTPS() {
        XCTAssertEqual(UpdateCheck.latestReleaseAPI.scheme, "https")
        XCTAssertEqual(UpdateCheck.releasesPage.scheme, "https")
    }
}
