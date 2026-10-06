package lab.playpath.player

import java.net.URI
import java.net.URISyntaxException

// Same roots as services/origin/session.json. A failed media segment
// keeps its path. The title does not start again at the first segment.
internal const val primaryOrigin = "http://127.0.0.1:8080"
internal const val backupOrigin = "http://127.0.0.1:8081"

internal fun backupSegmentUrl(failed: String): String? {
    val parsed = try {
        URI(failed)
    } catch (_: URISyntaxException) {
        return null
    }
    if (parsed.scheme != "http" || parsed.host != "127.0.0.1" || parsed.port != 8080) {
        return null
    }
    val path = parsed.path ?: return null
    if (path.isEmpty() || path == "/" || path.endsWith("/") || !path.endsWith(".m4s")) {
        return null
    }
    return URI("http", null, "127.0.0.1", 8081, path, parsed.rawQuery, null).toASCIIString()
}

internal fun failoverSegmentUrl(responseCode: Int, failed: String): String? {
    if (responseCode != 503) {
        return null
    }
    return backupSegmentUrl(failed)
}
