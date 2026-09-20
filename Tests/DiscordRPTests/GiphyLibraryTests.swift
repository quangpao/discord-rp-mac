import XCTest

@testable import DiscordRP

/// The upload history is the only way back to an already-uploaded GIF: the Giphy API has no
/// "list my uploads" endpoint and hidden uploads are not on the account page.
final class GiphyLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("customrp-giphy-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func upload(_ id: String, name: String, minutesAgo: Double = 0, hidden: Bool = false) -> GiphyUpload {
        GiphyUpload(
            id: id,
            mediaURL: "https://media.giphy.com/media/\(id)/giphy.gif",
            pageURL: "https://giphy.com/gifs/\(id)",
            filename: name,
            bytes: 1234,
            hidden: hidden,
            uploadedAt: Date(timeIntervalSince1970: 1_789_837_200 - minutesAgo * 60)
        )
    }

    func testRecordPersistsAndLoadsNewestFirst() {
        let library = GiphyLibrary(directory: directory)
        library.record(upload("aaa", name: "logo.gif", minutesAgo: 10))
        library.record(upload("bbb", name: "later.gif"))

        let loaded = GiphyLibrary(directory: directory).load()
        XCTAssertEqual(loaded.map(\.id), ["bbb", "aaa"])
        XCTAssertEqual(loaded.first?.filename, "later.gif")
        XCTAssertEqual(loaded.first?.mediaURL, "https://media.giphy.com/media/bbb/giphy.gif")
        XCTAssertEqual(loaded.first?.pageURL, "https://giphy.com/gifs/bbb")
    }

    /// Same Giphy id twice (the same file pushed again) must not create two entries.
    func testReuploadingTheSameIdMovesItToTheFrontWithoutDuplicating() {
        let library = GiphyLibrary(directory: directory)
        library.record(upload("aaa", name: "logo.gif", minutesAgo: 30))
        library.record(upload("bbb", name: "other.gif", minutesAgo: 20))
        library.record(upload("aaa", name: "logo-again.gif"))

        let loaded = library.load()
        XCTAssertEqual(loaded.map(\.id), ["aaa", "bbb"])
        XCTAssertEqual(loaded.first?.filename, "logo-again.gif", "the newest record wins")
    }

    func testHiddenUploadsAreRecordedToo() {
        let library = GiphyLibrary(directory: directory)
        library.record(upload("ccc", name: "private.gif", hidden: true))
        XCTAssertEqual(library.load().first?.hidden, true)
    }

    func testListIsCappedAtMaxEntries() {
        let library = GiphyLibrary(directory: directory)
        for index in 0..<(GiphyLibrary.maxEntries + 5) {
            library.record(upload("id\(index)", name: "file\(index).gif", minutesAgo: Double(index)))
        }
        XCTAssertEqual(library.load().count, GiphyLibrary.maxEntries)
        XCTAssertEqual(library.load().first?.id, "id0", "the newest survives the cap")
    }

    func testMissingFileYieldsEmptyListInsteadOfFailing() {
        XCTAssertTrue(GiphyLibrary(directory: directory).load().isEmpty)
    }

    /// Dates must survive as epoch milliseconds, the storage contract shared with presets.
    func testDatesAreStoredAsEpochMilliseconds() throws {
        let library = GiphyLibrary(directory: directory)
        library.record(upload("ddd", name: "dated.gif"))
        let raw = try String(contentsOf: directory.appendingPathComponent("giphy-uploads.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("1789837200000"), "expected epoch ms, got:\n\(raw)")
    }
}
