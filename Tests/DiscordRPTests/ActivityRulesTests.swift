import XCTest

@testable import DiscordRP

final class ActivityRulesTests: XCTestCase {
    private let appID = "123456789012345678"
    private let now = Date()
    private var started: Date { now.addingTimeInterval(-90) }

    private func payload(_ activity: Activity, at moment: Date? = nil) -> [String: Any]? {
        ActivityRules.payload(
            activity, appID: appID, now: moment ?? now,
            appStarted: now.addingTimeInterval(-600), connectionStarted: started, presenceStarted: started
        )
    }

    func testTextLengthRules() {
        var activity = Activity(name: "T", details: "ok")
        XCTAssertTrue(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).isEmpty)

        activity.details = "x"
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).first?.field, .details)

        activity.details = String(repeating: "a", count: ActivityRules.maxTextLength + 1)
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).first?.field, .details)

        activity.details = ""
        activity.state = "y"
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).first?.field, .state)
    }

    func testButtonLabelIsLimitedInUTF8Bytes() {
        var activity = Activity(name: "T", details: "ok")
        activity.buttons = [Button(label: String(repeating: "ế", count: 11), url: "https://example.com")]
        XCTAssertGreaterThan(ActivityRules.utf8ByteCount(activity.buttons[0].label), ActivityRules.maxButtonLabelBytes)
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).first?.field, .buttonLabel)
    }

    func testButtonNeedsBothLabelAndURL() {
        var activity = Activity(name: "T", details: "ok")
        activity.buttons = [Button(label: "Docs", url: "")]
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: appID)).first?.field, .buttonURL)
        XCTAssertNil(payload(activity), "an incomplete button blocks the payload")
        activity.buttons = []
        XCTAssertNotNil(payload(activity))
    }

    func testPayloadContainsBothButtons() {
        var activity = Activity(name: "T", details: "ok")
        activity.buttons = [
            Button(label: "One", url: "example.com"),
            Button(label: "Two", url: "https://two.example.com"),
        ]
        let buttons = payload(activity)?["buttons"] as? [[String: String]]
        XCTAssertEqual(buttons?.count, 2)
        XCTAssertEqual(buttons?.first?["url"], "https://example.com", "scheme is added")
    }

    func testURLNormalisation() {
        XCTAssertEqual(ActivityRules.normalizedURL("example.com"), "https://example.com")
        XCTAssertEqual(ActivityRules.normalizedURL("  example.com  "), "https://example.com")
        XCTAssertNil(ActivityRules.normalizedURL("ftp://example.com"))
        XCTAssertNil(ActivityRules.normalizedURL(""))
        XCTAssertEqual(ActivityRules.normalizedURL(String(repeating: "a", count: 900))?.count, ActivityRules.maxURLLength)
    }

    func testZeroWidthGuardForLeadingNBSP() {
        XCTAssertEqual(ActivityRules.zeroWidthGuarded("\u{00A0}x"), "\u{200B}\u{00A0}x")
        XCTAssertEqual(ActivityRules.zeroWidthGuarded("ok"), "ok")
    }

    func testExternalImageBudget() {
        let short = "https://cdn.example.com/a.png"
        XCTAssertLessThan(ActivityRules.externalImageBudget(for: short), ActivityRules.maxExternalImageBudget)
        var activity = Activity(name: "T", details: "ok")
        activity.largeKey = "https://cdn.example.com/" + String(repeating: "a", count: 300) + ".png"
        XCTAssertEqual(ActivityRules.validate(activity, appID: appID).first?.field, .imageKey)
        XCTAssertNil(payload(activity))
    }

    func testAssetNameValidation() {
        var activity = Activity(name: "T", details: "ok")
        activity.largeKey = "my_asset-1"
        XCTAssertTrue(ActivityRules.validate(activity, appID: appID).isEmpty)
        activity.largeKey = "has spaces"
        XCTAssertEqual(ActivityRules.validate(activity, appID: appID).first?.field, .imageKey)
    }

    func testTimestampsAreEpochMilliseconds() {
        var activity = Activity(name: "T", details: "ok")
        activity.timestampMode = .sinceConnection
        let timestamps = payload(activity)?["timestamps"] as? [String: Int]
        XCTAssertEqual(timestamps?["start"], Int(started.timeIntervalSince1970 * 1000))
    }

    func testFutureCustomStartBecomesCountdown() {
        var activity = Activity(name: "T", details: "ok")
        activity.timestampMode = .custom
        activity.customStart = now.addingTimeInterval(3600)
        let timestamps = payload(activity)?["timestamps"] as? [String: Int]
        XCTAssertEqual(timestamps?["start"], Int(now.timeIntervalSince1970 * 1000))
        XCTAssertEqual(timestamps?["end"], Int(now.addingTimeInterval(3600).timeIntervalSince1970 * 1000))
    }

    func testTimestampClampBounds() {
        XCTAssertEqual(ActivityRules.clampedTimestamp(Date(timeIntervalSince1970: 0)), ActivityRules.earliestTimestamp)
        XCTAssertEqual(ActivityRules.clampedTimestamp(Date(timeIntervalSince1970: 1e12)), ActivityRules.latestTimestamp)
    }

    func testCompetingHasNoTimestampsAndPartyOnlyForPlaying() {
        var activity = Activity(name: "T", details: "ok")
        activity.kind = .competing
        activity.timestampMode = .sinceConnection
        XCTAssertNil(payload(activity)?["timestamps"])

        activity.kind = .listening
        activity.partySize = 2
        activity.partyMax = 5
        XCTAssertNil(payload(activity)?["party"], "party is Playing-only")

        activity.kind = .playing
        XCTAssertNotNil(payload(activity)?["party"])
    }

    func testPartyMaxIsRaisedToSize() {
        var activity = Activity(name: "T", details: "ok")
        activity.partySize = 4
        activity.partyMax = 2
        let party = payload(activity)?["party"] as? [String: Any]
        XCTAssertEqual(party?["size"] as? [Int], [4, 4])
    }

    func testMissingAppIDBlocksPayload() {
        let activity = Activity(name: "T", details: "ok")
        XCTAssertEqual(ActivityRules.errors(in: ActivityRules.validate(activity, appID: "")).first?.field, .appID)
        XCTAssertNil(ActivityRules.payload(activity, appID: "", appStarted: now,
                                           connectionStarted: now, presenceStarted: now))
    }

    func testEmptyFieldsAreOmitted() {
        var activity = Activity(name: "T", details: "ok")
        activity.smallKey = "small_asset"
        let payload = payload(activity)
        XCTAssertNil(payload?["state"])
        let assets = payload?["assets"] as? [String: Any]
        XCTAssertEqual(assets?["small_image"] as? String, "small_asset")
        XCTAssertNil(assets?["large_image"], "an empty key must not be sent — Discord renders a broken asset")
    }

    func testTypeAndDisplayAreAlwaysSent() {
        var activity = Activity(name: "T", details: "ok")
        activity.kind = .watching
        activity.display = .details
        XCTAssertEqual(payload(activity)?["type"] as? Int, 3)
        XCTAssertEqual(payload(activity)?["status_display_type"] as? Int, 1)
    }

    /// The picker is only useful if the labels are distinguishable and each mode explains itself.
    func testTimestampModeLabelsAreUniqueAndExplained() {
        let labels = TimestampMode.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count, "labels must be unique: \(labels)")
        for mode in TimestampMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
            XCTAssertGreaterThan(mode.explanation.count, 20, "\(mode.label) needs a real explanation")
        }
        XCTAssertTrue(TimestampMode.sinceConnection.label.contains("Discord"))
        XCTAssertTrue(TimestampMode.sinceAppStart.label.contains("app launch"))
    }

    /// Discord's RPC validator accepts `type` in [0, 2, 3, 5] only — verified against a real
    /// rejection: `"type" must be one of [0, 2, 3, 5]`. Streaming (1) must never be sent.
    func testStreamingTypeIsRejectedLocallyAndNeverOffered() {
        var activity = Activity(name: "T", details: "ok")
        activity.kind = .streaming
        let issues = ActivityRules.validate(activity, appID: "1041550572223995925")
        XCTAssertTrue(issues.contains { $0.field == .kind && $0.isError },
                      "streaming must be an error: \(issues.map(\.message))")

        XCTAssertEqual(ActivityKind.selectable.map(\.rawValue), [0, 2, 3, 5])
        XCTAssertFalse(ActivityKind.selectable.contains(.streaming))
        XCTAssertFalse(ActivityKind.streaming.isAcceptedByDiscord)
        for kind in ActivityKind.selectable {
            XCTAssertTrue(kind.isAcceptedByDiscord, "\(kind.label) should be accepted")
        }
    }
}
