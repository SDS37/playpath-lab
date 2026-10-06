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
    return buildString {
        append('{')
        append("\"version\":1")
        append(",\"titleId\":${jsonString(TITLE_ID)}")
        append(",\"sessionId\":${jsonString(sessionId)}")
        append(",\"platform\":\"android\"")
        append(",\"engine\":\"media3\"")
        append(",\"event\":\"drm\"")
        append(",\"at\":${jsonString(at)}")
        append(",\"positionMs\":$positionMs")
        append(",\"keySystem\":${jsonString(CLEAR_KEY_SYSTEM)}")
        append(",\"result\":${jsonString(result)}")
        append(",\"code\":${jsonString(code)}")
        append('}')
    }
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
