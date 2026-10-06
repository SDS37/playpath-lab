package lab.playpath.player

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

const val MIDROLL_VAST_URL = "http://127.0.0.1:8083/vast/midroll.xml"

data class Midroll(
    val cueMs: Long,
    val mediaUrl: String,
)

private val clock = Regex("timeOffset=\"(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d{3})\"")
private val mediaFile = Regex(
    "<MediaFile\\b[^>]*>\\s*<!\\[CDATA\\[(https?://[^\\]\\s]+)\\]\\]>\\s*</MediaFile>",
)

fun readMidroll(xml: String): Midroll? {
    val time = clock.find(xml) ?: return null
    val media = mediaFile.find(xml) ?: return null
    val hours = time.groupValues[1].toLongOrNull() ?: return null
    val minutes = time.groupValues[2].toLongOrNull() ?: return null
    val seconds = time.groupValues[3].toLongOrNull() ?: return null
    val millis = time.groupValues[4].toLongOrNull() ?: return null
    val mediaUrl = media.groupValues[1]
    if (mediaUrl.isEmpty()) {
        return null
    }
    return Midroll(
        cueMs = (hours * 60 * 60 + minutes * 60 + seconds) * 1000 + millis,
        mediaUrl = mediaUrl,
    )
}

fun resumedAtCue(positionMs: Long, cueMs: Long): Boolean {
    return positionMs + 1_000 >= cueMs
}

fun playingAtCue(
    currentTimeMs: Long,
    cueMs: Long,
    paused: Boolean,
    ended: Boolean,
): Boolean {
    if (paused || ended || cueMs < 0 || currentTimeMs < 0) {
        return false
    }
    return currentTimeMs >= cueMs
}

fun fetchMidroll(): Midroll? {
    val connection = (URL(MIDROLL_VAST_URL).openConnection() as HttpURLConnection).apply {
        connectTimeout = MIDROLL_TIMEOUT_MS
        readTimeout = MIDROLL_TIMEOUT_MS
        requestMethod = "GET"
        instanceFollowRedirects = false
    }
    return try {
        if (connection.responseCode != HttpURLConnection.HTTP_OK) {
            null
        } else {
            connection.inputStream.bufferedReader().use { reader ->
                readMidroll(reader.readText())
            }
        }
    } catch (_: IOException) {
        null
    } finally {
        connection.disconnect()
    }
}

private const val MIDROLL_TIMEOUT_MS = 2_000
