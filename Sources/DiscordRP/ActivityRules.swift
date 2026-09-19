import Foundation

public enum IssueField: String, Sendable, Equatable {
    case appID, details, state, buttonLabel, buttonURL, timestamp, imageKey, imageURL, party
}

public struct ActivityIssue: Equatable, Sendable {
    public let field: IssueField
    public let message: String
    /// false = warning: the value is usable but Discord will render something different.
    public let isError: Bool

    public init(field: IssueField, message: String, isError: Bool = true) {
        self.field = field
        self.message = message
        self.isError = isError
    }
}

/// Discord's own rules, transcribed from the CustomRP source so we do not re-derive them:
/// min 2 chars (`MainForm.cs:1658`), 32-**byte** button labels (`:1656`), timestamp window
/// (`:371-376`), `mp:external` 256-char budget (`:955-958`), party only for Playing,
/// no timestamps for Competing (`:1607-1616`), zero-width-space guard for a leading NBSP (`:850`).
public enum ActivityRules {
    public static let minTextLength = 2
    public static let maxTextLength = 128
    public static let maxButtonLabelBytes = 32
    public static let maxURLLength = 512
    public static let earliestTimestamp = Date(timeIntervalSince1970: 1)
    /// 99_999_999_999 s — Discord's ceiling, `MainForm.cs:374-376`.
    public static let latestTimestamp = Date(timeIntervalSince1970: 99_999_999_999)
    public static let maxExternalImageBudget = 256
    public static let maxButtons = 2

    // MARK: - primitives

    public static func utf8ByteCount(_ text: String) -> Int {
        text.utf8.count
    }

    /// `MainForm.cs:908-927`: trim, add `https://` when the scheme is missing, cap the length.
    public static func normalizedURL(_ raw: String, maxLength: Int = ActivityRules.maxURLLength) -> String? {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if !url.contains("://") { url = "https://" + url }
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", parsed.host?.isEmpty == false
        else { return nil }
        return String(url.prefix(maxLength))
    }

    /// Discord rejects details/state that *start* with a non-breaking space unless a
    /// zero-width space is prepended — `MainForm.cs:850-859`.
    public static func zeroWidthGuarded(_ text: String, maxLength: Int = ActivityRules.maxTextLength) -> String {
        guard text.hasPrefix("\u{00A0}"), text.count < maxLength else { return text }
        return "\u{200B}" + text
    }

    /// Length Discord sees for an external image key (`MainForm.cs:955-958`).
    public static func externalImageBudget(for key: String) -> Int {
        guard let url = URL(string: key) else { return 0 }
        let escapedQuery = url.query.map { "?\($0)" } ?? ""
        let host = url.host ?? ""
        let path = url.path
        // "mp:external/<32-char md5>/<escaped query>/<scheme>/<host><path>"
        return 12 + 32 + 1 + escapedQuery.count + 1 + url.scheme!.count + 1 + host.count + path.count
    }

    public static func isExternalImageKey(_ key: String) -> Bool {
        key.lowercased().hasPrefix("http://") || key.lowercased().hasPrefix("https://")
    }

    /// Asset-name keys go to Discord verbatim; only real URLs are normalised (running an asset
    /// name through `normalizedURL` would turn `my_asset` into `https://my_asset`).
    public static func imageKey(_ key: String) -> String {
        isExternalImageKey(key) ? (normalizedURL(key) ?? key) : key
    }

    public static func isAssetNameKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 64 else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    public static func clampedTimestamp(_ date: Date) -> Date {
        min(max(date, earliestTimestamp), latestTimestamp)
    }

    // MARK: - validation

    public static func validate(_ activity: Activity, appID: String) -> [ActivityIssue] {
        var issues: [ActivityIssue] = []

        if appID.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ActivityIssue(
                field: .appID,
                message: "Set your Discord Application ID first — without it nothing can be shown."
            ))
        } else if !appID.allSatisfy(\.isNumber) {
            issues.append(ActivityIssue(field: .appID, message: "Application ID must be digits only."))
        }

        for (text, field) in [(activity.details, IssueField.details), (activity.state, .state)] {
            let count = text.count
            if count == 1 {
                issues.append(ActivityIssue(
                    field: field,
                    message: "\(field == .details ? "Details" : "State") needs at least \(minTextLength) characters."
                ))
            } else if count > maxTextLength {
                issues.append(ActivityIssue(
                    field: field,
                    message: "\(field == .details ? "Details" : "State") is limited to \(maxTextLength) characters."
                ))
            }
        }

        for (index, button) in activity.buttons.prefix(maxButtons).enumerated() {
            let position = index + 1
            let hasLabel = !button.label.trimmingCharacters(in: .whitespaces).isEmpty
            let hasURL = !button.url.trimmingCharacters(in: .whitespaces).isEmpty
            if hasLabel != hasURL {
                issues.append(ActivityIssue(
                    field: hasLabel ? .buttonURL : .buttonLabel,
                    message: "Button \(position) needs both a label and a URL — it is skipped otherwise."
                ))
            }
            let bytes = utf8ByteCount(button.label)
            if bytes > maxButtonLabelBytes {
                issues.append(ActivityIssue(
                    field: .buttonLabel,
                    message: "Button \(position) label is \(bytes) bytes; Discord allows \(maxButtonLabelBytes)."
                ))
            }
            if hasURL, normalizedURL(button.url) == nil {
                issues.append(ActivityIssue(field: .buttonURL, message: "Button \(position) URL is not a valid http(s) URL."))
            }
        }

        if activity.buttons.count > maxButtons {
            issues.append(ActivityIssue(field: .buttonLabel, message: "Discord allows at most \(maxButtons) buttons."))
        }

        if activity.partySize > 0 || activity.partyMax > 0 {
            if !activity.kind.allowsParty {
                issues.append(ActivityIssue(
                    field: .party,
                    message: "Party size only works with the “Playing” type.",
                    isError: false
                ))
            }
            if activity.partySize < 0 || activity.partyMax < 0 {
                issues.append(ActivityIssue(field: .party, message: "Party numbers cannot be negative."))
            }
            if activity.partySize > activity.partyMax {
                issues.append(ActivityIssue(
                    field: .party,
                    message: "Party size \(activity.partySize) is bigger than the maximum — the maximum will be raised.",
                    isError: false
                ))
            }
        }

        if activity.timestampMode != .off && !activity.kind.allowsTimestamps {
            issues.append(ActivityIssue(
                field: .timestamp,
                message: "The “Competing” type cannot show timestamps.",
                isError: false
            ))
        }

        if activity.timestampMode == .custom {
            if activity.customStart < earliestTimestamp || activity.customStart > latestTimestamp {
                issues.append(ActivityIssue(
                    field: .timestamp,
                    message: "Custom start must be between 1970-01-01 00:00:01Z and 5138-11-16 09:46:39Z."
                ))
            }
            if activity.customEndEnabled, activity.customEnd < activity.customStart {
                issues.append(ActivityIssue(field: .timestamp, message: "Custom end is before the start."))
            }
        }

        for (key, field, label) in [(activity.largeKey, IssueField.imageKey, "Large image"),
                                    (activity.smallKey, .imageKey, "Small image")] {
            guard !key.isEmpty else { continue }
            if isExternalImageKey(key) {
                if normalizedURL(key) == nil {
                    issues.append(ActivityIssue(field: field, message: "\(label) URL is not a valid http(s) URL."))
                } else if externalImageBudget(for: key) > maxExternalImageBudget {
                    issues.append(ActivityIssue(
                        field: field,
                        message: "\(label) URL is too long for Discord (\(externalImageBudget(for: key)) > \(maxExternalImageBudget) characters). Shorten the path or upload it as an asset."
                    ))
                }
            } else if !isAssetNameKey(key) {
                issues.append(ActivityIssue(
                    field: field,
                    message: "\(label) key must be an uploaded asset name (letters, digits, `_`, `-`) or an https URL."
                ))
            }
        }

        for (raw, field, label) in [(activity.largeURL, IssueField.imageURL, "Large image"),
                                    (activity.smallURL, .imageURL, "Small image"),
                                    (activity.detailsURL, .imageURL, "Details"),
                                    (activity.stateURL, .imageURL, "State")] {
            if !raw.trimmingCharacters(in: .whitespaces).isEmpty, normalizedURL(raw) == nil {
                issues.append(ActivityIssue(field: field, message: "\(label) link is not a valid http(s) URL."))
            }
        }

        return issues
    }

    public static func errors(in issues: [ActivityIssue]) -> [ActivityIssue] {
        issues.filter(\.isError)
    }

    // MARK: - payload

    /// Builds the `activity` object for SET_ACTIVITY, or nil when a rule is violated
    /// (invalid input must never reach Discord).
    public static func payload(
        _ activity: Activity,
        appID: String,
        now: Date = Date(),
        appStarted: Date,
        connectionStarted: Date,
        presenceStarted: Date,
        partyID: String = "customrp-mac"
    ) -> [String: Any]? {
        guard errors(in: validate(activity, appID: appID)).isEmpty else { return nil }

        var out: [String: Any] = ["type": activity.kind.rawValue]
        if !activity.name.isEmpty { out["name"] = activity.name }
        out["status_display_type"] = activity.display.rawValue

        let details = zeroWidthGuarded(activity.details.trimmingCharacters(in: .whitespacesAndNewlines))
        let state = zeroWidthGuarded(activity.state.trimmingCharacters(in: .whitespacesAndNewlines))
        if !details.isEmpty {
            out["details"] = details
            if let url = normalizedURL(activity.detailsURL) { out["details_url"] = url }
        }
        if !state.isEmpty {
            out["state"] = state
            if let url = normalizedURL(activity.stateURL) { out["state_url"] = url }
        }

        if activity.kind.allowsTimestamps, let timestamps = timestamps(activity, now: now, appStarted: appStarted,
                                                                      connectionStarted: connectionStarted,
                                                                      presenceStarted: presenceStarted) {
            out["timestamps"] = timestamps
        }

        var assets: [String: Any] = [:]
        if !activity.largeKey.isEmpty {
            assets["large_image"] = imageKey(activity.largeKey)
            if !activity.largeText.isEmpty { assets["large_text"] = activity.largeText }
            if let url = normalizedURL(activity.largeURL) { assets["large_url"] = url }
        }
        if !activity.smallKey.isEmpty {
            assets["small_image"] = imageKey(activity.smallKey)
            if !activity.smallText.isEmpty { assets["small_text"] = activity.smallText }
            if let url = normalizedURL(activity.smallURL) { assets["small_url"] = url }
        }
        if !assets.isEmpty { out["assets"] = assets }

        if activity.kind.allowsParty, activity.partySize > 0, activity.partyMax > 0 {
            out["party"] = [
                "id": partyID,
                "size": [activity.partySize, max(activity.partySize, activity.partyMax)],
            ]
        }

        let buttons = activity.buttons.prefix(maxButtons).compactMap { button -> [String: Any]? in
            let label = button.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, let url = normalizedURL(button.url) else { return nil }
            return ["label": label, "url": url]
        }
        if !buttons.isEmpty { out["buttons"] = buttons }

        return out
    }

    /// Epoch **milliseconds**; returns nil when the mode produces nothing.
    public static func timestamps(
        _ activity: Activity,
        now: Date,
        appStarted: Date,
        connectionStarted: Date,
        presenceStarted: Date
    ) -> [String: Int]? {
        func milliseconds(_ date: Date) -> Int { Int(clampedTimestamp(date).timeIntervalSince1970 * 1000) }

        switch activity.timestampMode {
        case .off:
            return nil
        case .sinceConnection:
            return ["start": milliseconds(connectionStarted)]
        case .sinceAppStart:
            return ["start": milliseconds(appStarted)]
        case .sincePresenceUpdate:
            return ["start": milliseconds(presenceStarted)]
        case .localTime:
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: now)
            return ["start": milliseconds(midnight)]
        case .custom:
            if activity.customEndEnabled {
                return ["start": milliseconds(activity.customStart), "end": milliseconds(activity.customEnd)]
            }
            // Future start = a countdown (`MainForm.cs:1065-1066`): swap start/end.
            if activity.customStart > now {
                return ["start": milliseconds(now), "end": milliseconds(activity.customStart)]
            }
            return ["start": milliseconds(activity.customStart)]
        }
    }
}
