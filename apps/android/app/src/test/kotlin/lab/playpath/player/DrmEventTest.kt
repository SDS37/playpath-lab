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
