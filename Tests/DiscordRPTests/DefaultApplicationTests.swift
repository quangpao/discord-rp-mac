import XCTest
@testable import DiscordRP

/// An Application ID is required by Discord's handshake, so "no setup" has to mean "the built-in
/// application", not "no id". These tests pin that choice and the shape of the id.
final class DefaultApplicationTests: XCTestCase {
    func testTheBuiltInIDLooksLikeAnApplicationID() {
        let id = DefaultApplication.id
        XCTAssertTrue(id.allSatisfy(\.isNumber), "an application id is numeric: \(id)")
        XCTAssertTrue((17...19).contains(id.count), "Discord application ids are 17–19 digits, got \(id.count)")
    }

    func testAFreshInstallUsesTheBuiltInApplication() {
        XCTAssertEqual(AppSettings().appID, DefaultApplication.id,
                       "a fresh install should work without visiting the Developer Portal first")
    }

    func testAnExplicitIDIsNotMistakenForTheDefault() {
        XCTAssertTrue(DefaultApplication.isDefault(DefaultApplication.id))
        XCTAssertTrue(DefaultApplication.isDefault("  \(DefaultApplication.id)\n"))
        XCTAssertFalse(DefaultApplication.isDefault("123456789012345678"))
        XCTAssertFalse(DefaultApplication.isDefault(""))
    }

    func testAnEmptyIDStillMeansNoPresence() {
        // Clearing the field must keep meaning "send nothing" — the default is a default, not a floor.
        var settings = AppSettings()
        settings.appID = ""
        XCTAssertTrue(settings.appID.isEmpty)
    }
}
