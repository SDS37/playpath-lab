package lab.playpath.player

const val TITLE_ID = "playpath-bars"
const val CLEAR_KEY_SYSTEM = "org.w3.clearkey"
const val CLEAR_KEY_LICENSE_URL = "http://127.0.0.1:8082/"
const val DASH_MANIFEST = "http://127.0.0.1:8080/manifest.mpd"
const val WRONG_KEY_MANIFEST = "http://127.0.0.1:8080/manifest-wrong-kid.mpd"
const val EVENT_LOG = "playpath.event"

const val DRM_ERROR = "The title cannot be played."
const val PLAYBACK_ERROR = "Playback failed."

fun drmEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    result: String,
    code: String,
): String {
    return envelope(sessionId, "drm", at, positionMs)
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
    codecs: String,
): String {
    val line = envelope(sessionId, "bitrate", at, positionMs)
    if (height > 0) {
        line.append(",\"height\":$height")
    }
    if (bandwidthBps > 0) {
        line.append(",\"bandwidthBps\":$bandwidthBps")
    }
    if (codecs.isNotEmpty()) {
        line.append(",\"codecs\":${jsonString(codecs)}")
    }
    return line.append('}').toString()
}

fun startupEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    startupMs: Long,
    manifestUrl: String,
): String {
    return envelope(sessionId, "startup", at, positionMs)
        .append(",\"startupMs\":${startupMs.coerceAtLeast(0)}")
        .append(",\"manifestUrl\":${jsonString(manifestUrlForEvent(manifestUrl))}")
        .append('}')
        .toString()
}

fun adEvent(
    sessionId: String,
    at: String,
    positionMs: Long,
    action: String,
): String {
    return envelope(sessionId, "ad", at, positionMs)
        .append(",\"breakId\":\"midroll\"")
        .append(",\"mode\":\"csai\"")
        .append(",\"action\":${jsonString(action)}")
        .append('}')
        .toString()
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
    event: String,
    at: String,
    positionMs: Long,
): StringBuilder {
    return StringBuilder()
        .append("{\"version\":1")
        .append(",\"titleId\":${jsonString(TITLE_ID)}")
        .append(",\"sessionId\":${jsonString(sessionId)}")
        .append(",\"platform\":\"android\"")
        .append(",\"engine\":\"media3\"")
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
