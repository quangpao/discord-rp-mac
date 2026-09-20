import XCTest

@testable import DiscordRP

/// Preview URL rules: an external key is loaded as-is, a bare name becomes a Discord app-asset CDN
/// URL (which is why the Application ID matters for previews).
final class PreviewTargetTests: XCTestCase {
    private let appID = "1041550572223995925"

    func testExternalURLIsUsedAsIs() {
        let target = PreviewTarget.make(key: "https://media.giphy.com/media/abc123/giphy.gif", appID: appID)
        XCTAssertEqual(target?.url.absoluteString, "https://media.giphy.com/media/abc123/giphy.gif")
        XCTAssertEqual(target?.kind, "external URL")
    }

    func testHTTPIsAcceptedToo() {
        XCTAssertEqual(PreviewTarget.make(key: "http://example.com/a.png", appID: "")?.kind, "external URL")
    }

    func testBareNameBecomesDiscordAppAssetURLUsingTheNumericID() {
        let target = PreviewTarget.make(key: "3-asset-small-512", appID: appID, assetID: "1550951948394692669")
        XCTAssertEqual(target?.url.absoluteString,
                       "https://cdn.discordapp.com/app-assets/\(appID)/1550951948394692669.png")
        XCTAssertEqual(target?.kind, "Discord asset")
    }

    /// The name-based CDN path 404s, so without the id there is nothing to show.
    func testAssetNameWithoutItsIDHasNoPreview() {
        XCTAssertNil(PreviewTarget.make(key: "3-asset-small-512", appID: appID))
        XCTAssertNil(PreviewTarget.make(key: "3-asset-small-512", appID: appID, assetID: ""))
    }

    func testAssetNameNeedsTheApplicationID() {
        XCTAssertNil(PreviewTarget.make(key: "3-asset-small-512", appID: "", assetID: "1550951948394692669"))
        XCTAssertNil(PreviewTarget.make(key: "3-asset-small-512", appID: "   ", assetID: "1550951948394692669"))
    }

    func testEmptyKeyHasNoPreview() {
        XCTAssertNil(PreviewTarget.make(key: "", appID: appID))
        XCTAssertNil(PreviewTarget.make(key: "   \n ", appID: appID))
    }

    func testWhitespaceAroundAURLIsIgnored() {
        XCTAssertEqual(PreviewTarget.make(key: "  https://example.com/a.gif \n", appID: appID)?.url.absoluteString,
                       "https://example.com/a.gif")
    }

    /// A key with a slash that is not a URL is not a valid asset name either.
    func testSlashWithoutSchemeIsNotPreviewable() {
        XCTAssertNil(PreviewTarget.make(key: "some/path.png", appID: appID))
    }
}
