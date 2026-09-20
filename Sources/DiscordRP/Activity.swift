import Foundation

/// Discord activity type (`type` in the SET_ACTIVITY payload).
public enum ActivityKind: Int, Codable, CaseIterable, Sendable, Identifiable {
    case playing = 0
    case streaming = 1
    case listening = 2
    case watching = 3
    case competing = 5

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .playing: "Playing"
        case .streaming: "Streaming"
        case .listening: "Listening to"
        case .watching: "Watching"
        case .competing: "Competing in"
        }
    }

    /// Mirrors CustomRP `MainForm.cs:1607-1616`: only Playing supports a party, and
    /// Competing cannot carry timestamps.
    public var allowsParty: Bool { self == .playing }
    public var allowsTimestamps: Bool { self != .competing }
}

/// `status_display_type` — which field Discord shows under the app name.
public enum DisplayType: Int, Codable, CaseIterable, Sendable, Identifiable {
    case name = 0
    case details = 1
    case state = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .name: "Name"
        case .details: "Details"
        case .state: "State"
        }
    }
}

/// CustomRP's timestamp modes (`MainForm.cs:1035-1068`).
public enum TimestampMode: Int, Codable, CaseIterable, Sendable, Identifiable {
    case off = 0
    /// Since this app connected to Discord.
    case sinceConnection = 1
    /// Since this app was launched.
    case sinceAppStart = 2
    /// Reset on every presence update ("Total time").
    case sincePresenceUpdate = 3
    /// Since local midnight — Discord renders this as the current local time.
    case localTime = 4
    case custom = 5

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .off: "Off (no timer)"
        case .sinceConnection: "Since Discord connect"
        case .sinceAppStart: "Since app launch"
        case .sincePresenceUpdate: "Since last update"
        case .localTime: "Local time"
        case .custom: "Custom"
        }
    }

    /// One-line explanation shown under the picker, so the label never has to be decoded.
    public var explanation: String {
        switch self {
        case .off:
            "No timer on the card."
        case .sinceConnection:
            "Counts from the moment this app connected to Discord. Resets when Discord restarts or the app reconnects."
        case .sinceAppStart:
            "Counts from the moment this app was launched. Keeps running across Discord restarts."
        case .sincePresenceUpdate:
            "Counts from the last time the presence was pushed (Apply, preset switch, reconnect). Looks like an elapsed session timer."
        case .localTime:
            "Discord renders the current local time — the stamp is local midnight, so it reads like a clock."
        case .custom:
            "Pick a start date; if the start is in the future, Discord shows a countdown instead. Add an end date for a fixed range."
        }
    }
}

public struct Button: Codable, Equatable, Sendable, Identifiable {
    public var label: String
    public var url: String
    public var id: String { label + url }

    public init(label: String = "", url: String = "") {
        self.label = label
        self.url = url
    }
}

/// One preset's worth of presence. Field set mirrors CustomRP's `Settings.settings`
/// (`id,type,display,name,details,detailsURL,state,stateURL,partySize,partyMax,timestamps,
/// customTimestamp,customTimestampEnd*,large*,small*,button1*,button2*`) minus its telemetry.
public struct Activity: Codable, Equatable, Sendable {
    public var name: String = ""
    public var kind: ActivityKind = .playing
    public var display: DisplayType = .name

    public var details: String = ""
    public var detailsURL: String = ""
    public var state: String = ""
    public var stateURL: String = ""

    public var partySize: Int = 0
    public var partyMax: Int = 0

    public var timestampMode: TimestampMode = .sinceConnection
    /// Truncated to the storage precision (epoch milliseconds) so a save/load round trip is exact.
    public var customStart: Date = ActivityRules.millisecondPrecision(Date())
    public var customEnd: Date = ActivityRules.millisecondPrecision(Date())
    public var customEndEnabled: Bool = false

    public var largeKey: String = ""
    public var largeText: String = ""
    public var largeURL: String = ""
    public var smallKey: String = ""
    public var smallText: String = ""
    public var smallURL: String = ""

    /// At most two, Discord's limit.
    public var buttons: [Button] = []

    public init() {}

    public init(name: String, details: String, state: String = "", kind: ActivityKind = .playing) {
        self.name = name
        self.details = details
        self.state = state
        self.kind = kind
    }

    /// Starter preset. The name carries the credit line on purpose — Discord renders `name`
    /// instead of the application's own name, so this is the visible byline on every profile.
    public static func sample(_ name: String = "CustomRP by quangpao") -> Activity {
        var activity = Activity(name: name, details: "Đang code", state: "customrp-mac")
        activity.timestampMode = .sinceConnection
        activity.buttons = [Button(label: "quangpao.dev", url: "https://quangpao.dev")]
        return activity
    }
}
