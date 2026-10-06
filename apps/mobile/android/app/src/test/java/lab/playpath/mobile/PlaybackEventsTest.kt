package lab.playpath.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PlaybackEventsTest {
    @Test
    fun startupStripsCredentials() {
        val line = startupEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 0,
            startupMs = 840,
            manifestUrl = "http://user:pass@127.0.0.1:8080/manifest.mpd?k=ffefcdab",
        )
        assertEquals(
            "{\"version\":1,\"titleId\":\"playpath-bars\",\"sessionId\":\"session\",\"platform\":\"react-native\",\"engine\":\"media3\",\"event\":\"startup\",\"at\":\"2026-10-06T09:00:00Z\",\"positionMs\":0,\"startupMs\":840,\"manifestUrl\":\"http://127.0.0.1:8080/manifest.mpd\"}",
            line,
        )
        assertFalse(line.contains("ffefcdab"))
        assertFalse(line.contains("user:pass"))
    }

    @Test
    fun drmOmitsTheLicenseBody() {
        val line = drmEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 0,
            result = "error",
            code = "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED",
        )
        assertFalse(line.contains("ffefcdab"))
        assertEquals("error", jsonValue(line, "result"))
        assertEquals("org.w3.clearkey", jsonValue(line, "keySystem"))
    }

    private fun jsonValue(line: String, key: String): String {
        val marker = "\"$key\":\""
        val start = line.indexOf(marker)
        assertFalse(start < 0)
        val from = start + marker.length
        return line.substring(from, line.indexOf('"', from))
    }
}
