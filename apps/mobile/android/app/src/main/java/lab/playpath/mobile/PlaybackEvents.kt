package lab.playpath.mobile

const val TITLE_ID = "playpath-bars"
const val CLEAR_KEY_SYSTEM = "org.w3.clearkey"
const val CLEAR_KEY_LICENSE_URL = "http://127.0.0.1:8082/"

const val DRM_ERROR = "The title cannot be played."
const val PLAYBACK_ERROR = "Playback failed."

fun startupEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    startupMs: Long,
    manifestUrl: String,
): String {
    return envelope(sessionId, "media3", "startup", at, positionMs)
        .append(",\"startupMs\":${startupMs.coerceAtLeast(0)}")
        .append(",\"manifestUrl\":${jsonString(manifestUrlForEvent(manifestUrl))}")
        .append('}')
        .toString()
}

fun drmEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    result: String,
    code: String,
): String {
    return envelope(sessionId, "media3", "drm", at, positionMs)
        .append(",\"keySystem\":${jsonString(CLEAR_KEY_SYSTEM)}")
        .append(",\"result\":${jsonString(result)}")
        .append(",\"code\":${jsonString(code)}")
        .append('}')
        .toString()
}

fun bitrateEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    height: Int,
    bandwidthBps: Int,
): String {
    val line = envelope(sessionId, "media3", "bitrate", at, positionMs)
    if (height > 0) {
        line.append(",\"height\":$height")
    }
    if (bandwidthBps > 0) {
        line.append(",\"bandwidthBps\":$bandwidthBps")
    }
    return line.append('}').toString()
}

/** Drops userinfo and the query so a manifest URL cannot carry a credential. */
fun manifestUrlForEvent(url: String): String {
    val withoutFragment = url.substringBefore('#')
    val withoutQuery = withoutFragment.substringBefore('?')
    val scheme = when {
        withoutQuery.startsWith("https://") -> "https://"
        withoutQuery.startsWith("http://") -> "http://"
        else -> return withoutQuery
    }
    val rest = withoutQuery.removePrefix(scheme)
    val at = rest.indexOf('@')
    val hostAndPath = if (at >= 0) rest.substring(at + 1) else rest
    return scheme + hostAndPath
}

private fun envelope(
    sessionId: String,
    engine: String,
    event: String,
    at: String,
    positionMs: Long,
): StringBuilder {
    return StringBuilder()
        .append("{\"version\":1")
        .append(",\"titleId\":${jsonString(TITLE_ID)}")
        .append(",\"sessionId\":${jsonString(sessionId)}")
        .append(",\"platform\":\"react-native\"")
        .append(",\"engine\":${jsonString(engine)}")
        .append(",\"event\":${jsonString(event)}")
        .append(",\"at\":${jsonString(at)}")
        .append(",\"positionMs\":${positionMs.coerceAtLeast(0)}")
}

private fun jsonString(value: String): String {
    val escaped = buildString(value.length) {
        for (ch in value) {
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                else -> append(ch)
            }
        }
    }
    return "\"$escaped\""
}
