package lab.playpath.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DrmEventTest {
    @Test
    fun `wrong key id is a drm error and the event has no content key`() {
        val event = drmEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 0,
            result = "error",
            code = "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED",
        )
        assertEquals("drm", field(event, "event"))
        assertEquals("error", field(event, "result"))
        assertEquals("org.w3.clearkey", field(event, "keySystem"))
        assertEquals("media3", field(event, "engine"))
        assertEquals("android", field(event, "platform"))
        assertEquals(
            "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED",
            field(event, "code"),
        )
        assertFalse(event.contains("ffefcdab"))
    }

    @Test
    fun `a loaded key is a drm ok event`() {
        val event = drmEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 40,
            result = "ok",
            code = "",
        )
        assertEquals("ok", field(event, "result"))
        assertEquals("40", field(event, "positionMs"))
        assertFalse(event.contains("ffefcdab"))
    }

    @Test
    fun `a lower rung is a bitrate event`() {
        val event = bitrateEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 4000,
            height = 720,
            bandwidthBps = 2_164_878,
            codecs = "avc1.64001f,mp4a.40.2",
        )
        assertEquals("bitrate", field(event, "event"))
        assertEquals("media3", field(event, "engine"))
        assertEquals("720", field(event, "height"))
        assertEquals("2164878", field(event, "bandwidthBps"))
        assertFalse(event.contains("ffefcdab"))
    }

    @Test
    fun `startup and the mid-roll use the same field names and omit credentials`() {
        val startup = startupEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 0,
            startupMs = 840,
            manifestUrl = "http://user:pass@127.0.0.1:8080/manifest.mpd?k=ffefcdab",
        )
        assertEquals("startup", field(startup, "event"))
        assertEquals("android", field(startup, "platform"))
        assertEquals("media3", field(startup, "engine"))
        assertEquals("840", field(startup, "startupMs"))
        assertEquals("http://127.0.0.1:8080/manifest.mpd", field(startup, "manifestUrl"))
        assertFalse(startup.contains("ffefcdab"))
        assertFalse(startup.contains("user:pass"))
        val ad = adEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:10Z",
            positionMs = 10_000,
            action = "start",
        )
        assertEquals("ad", field(ad, "event"))
        assertEquals("midroll", field(ad, "breakId"))
        assertEquals("csai", field(ad, "mode"))
        assertEquals("start", field(ad, "action"))
        assertEquals("10000", field(ad, "positionMs"))
        assertFalse(ad.contains("ffefcdab"))
        val impression = adEvent(
            sessionId = "session",
            at = "2026-10-06T09:00:00Z",
            positionMs = 0,
            action = "impression",
            breakId = "preroll",
            mode = "ssai",
        )
        assertEquals("preroll", field(impression, "breakId"))
        assertEquals("ssai", field(impression, "mode"))
        assertEquals("impression", field(impression, "action"))
        assertFalse(impression.contains("vast/impression"))
        assertEquals(10_000L, presentationCueMs(10_000L, DASH_MANIFEST))
        assertEquals(15_000L, presentationCueMs(10_000L, STITCHED_DASH))
        assertEquals(DASH_MANIFEST, cleanMenu(STITCHED_DASH))
        assertEquals(null, cleanMenu(DASH_MANIFEST))
        assertEquals(null, cleanMenu("http://127.0.0.1:8083/vast/impression"))
        assertFalse(DASH_MANIFEST.contains("vast/impression"))
        assertFalse(DASH_MANIFEST.contains("8083"))
    }
}

private fun field(json: String, name: String): String {
    val key = "\"$name\":"
    val start = json.indexOf(key)
    check(start >= 0) { name }
    val valueStart = start + key.length
    if (json[valueStart] == '"') {
        val end = json.indexOf('"', valueStart + 1)
        return json.substring(valueStart + 1, end)
    }
    val end = json.indexOfAny(charArrayOf(',', '}'), valueStart)
    return json.substring(valueStart, end)
}
