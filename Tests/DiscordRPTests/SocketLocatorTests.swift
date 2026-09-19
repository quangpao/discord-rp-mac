import XCTest

@testable import DiscordRP

final class SocketLocatorTests: XCTestCase {
    func testEnvOverrideWins() {
        let candidates = SocketLocator.candidates(
            env: ["CUSTOMRP_IPC_PATH": "/custom/path"], tmpdir: "/tmp/x", home: "/Users/nobody"
        )
        XCTAssertEqual(candidates.first, "/custom/path")
    }

    func testPreferredPipeIndexComesFirst() {
        let candidates = SocketLocator.candidates(tmpdir: "/tmp/x", home: "/Users/nobody", pipeIndex: 1)
        XCTAssertEqual(candidates.first, "/tmp/x/discord-ipc-1")
        XCTAssertTrue(candidates.contains("/tmp/x/discord-ipc-0"), "other clients still probed")
    }

    func testTrailingSlashInTmpdirIsHandled() {
        let candidates = SocketLocator.candidates(tmpdir: "/tmp/x/", home: "/Users/nobody")
        XCTAssertEqual(candidates.first, "/tmp/x/discord-ipc-0")
    }

    func testNoDuplicates() {
        let candidates = SocketLocator.candidates(
            env: ["CUSTOMRP_IPC_PATH": "/tmp/x/discord-ipc-0"], tmpdir: "/tmp/x", home: "/Users/nobody"
        )
        XCTAssertEqual(candidates.count, Set(candidates).count)
    }

    func testFirstAvailableSkipsMissingSockets() {
        let found = SocketLocator.firstAvailable(
            tmpdir: "/tmp/x", home: "/Users/nobody",
            fileExists: { $0 == "/tmp/x/discord-ipc-2" }
        )
        XCTAssertEqual(found, "/tmp/x/discord-ipc-2")
    }

    func testSameSocketIgnoresPrivatePrefix() {
        XCTAssertTrue(SocketLocator.sameSocket("/var/folders/a/T/s", "/private/var/folders/a/T/s"))
    }
}
