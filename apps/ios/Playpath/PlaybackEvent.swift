import Foundation

/// UTC timestamp the playback event schema accepts.
func utcTimestamp(_ date: Date = Date()) -> String {
    let clock = ISO8601DateFormatter()
    clock.timeZone = TimeZone(secondsFromGMT: 0)
    clock.formatOptions = [.withInternetDateTime]
    return clock.string(from: date)
}

/// Drops userinfo and the query so a manifest URL cannot carry a credential.
func manifestUrlForEvent(_ url: String) -> String {
    let withoutFragment = url.split(separator: "#", maxSplits: 1).first.map(String.init) ?? url
    let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    guard let schemeEnd = withoutQuery.range(of: "://") else {
        return withoutQuery
    }
    let scheme = withoutQuery[..<schemeEnd.upperBound]
    let rest = withoutQuery[schemeEnd.upperBound...]
    guard let at = rest.firstIndex(of: "@") else {
        return withoutQuery
    }
    return String(scheme) + String(rest[rest.index(after: at)...])
}

func startupEvent(
    sessionId: String,
    at: String,
    positionMs: Int,
    startupMs: Int,
    manifestUrl: String
) -> String {
    var line = envelope(sessionId: sessionId, event: "startup", at: at, positionMs: positionMs)
    line += ",\"startupMs\":\(max(0, startupMs))"
    line += ",\"manifestUrl\":\(jsonString(manifestUrlForEvent(manifestUrl)))"
    line += "}"
    return line
}

func adEvent(
    sessionId: String,
    at: String,
    positionMs: Int,
    action: String,
    breakId: String = "midroll",
    mode: String = "csai"
) -> String {
    var line = envelope(sessionId: sessionId, event: "ad", at: at, positionMs: positionMs)
    line += ",\"breakId\":\(jsonString(breakId)),\"mode\":\(jsonString(mode)),\"action\":\(jsonString(action))"
    line += "}"
    return line
}

func bitrateEvent(
    sessionId: String,
    at: String,
    positionMs: Int,
    height: Int,
    bandwidthBps: Int
) -> String {
    var line = envelope(sessionId: sessionId, event: "bitrate", at: at, positionMs: positionMs)
    if height > 0 {
        line += ",\"height\":\(height)"
    }
    if bandwidthBps > 0 {
        line += ",\"bandwidthBps\":\(bandwidthBps)"
    }
    line += "}"
    return line
}

private func envelope(sessionId: String, event: String, at: String, positionMs: Int) -> String {
    var line = "{\"version\":1,\"titleId\":\"playpath-bars\""
    line += ",\"sessionId\":\(jsonString(sessionId)),\"platform\":\"ios\",\"engine\":\"avplayer\""
    line += ",\"event\":\(jsonString(event)),\"at\":\(jsonString(at))"
    line += ",\"positionMs\":\(max(0, positionMs))"
    return line
}

private func jsonString(_ value: String) -> String {
    var escaped = ""
    for character in value {
        switch character {
        case "\\":
            escaped += "\\\\"
        case "\"":
            escaped += "\\\""
        case "\n":
            escaped += "\\n"
        case "\r":
            escaped += "\\r"
        default:
            escaped.append(character)
        }
    }
    return "\"\(escaped)\""
}
