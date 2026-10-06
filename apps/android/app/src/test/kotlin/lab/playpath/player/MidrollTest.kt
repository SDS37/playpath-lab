package lab.playpath.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MidrollTest {
    @Test
    fun `the document names the cue and the creative`() {
        val midroll = readMidroll(
            """
            <Cue timeOffset="00:00:10.000"/>
            <MediaFile><![CDATA[http://127.0.0.1:8083/preroll/creative.mp4]]></MediaFile>
            """.trimIndent(),
        )
        assertEquals(10_000L, midroll?.cueMs)
        assertEquals("http://127.0.0.1:8083/preroll/creative.mp4", midroll?.mediaUrl)
    }

    @Test
    fun `a document with no creative is ignored`() {
        assertNull(readMidroll("""<Cue timeOffset="00:00:10.000"/>"""))
    }

    @Test
    fun `the cue starts only while the film is playing`() {
        assertTrue(playingAtCue(15_000, 10_000, paused = false, ended = false))
        assertFalse(playingAtCue(15_000, 10_000, paused = true, ended = false))
        assertFalse(playingAtCue(9_000, 10_000, paused = false, ended = false))
        assertFalse(playingAtCue(10_000, 10_000, paused = false, ended = true))
    }

    @Test
    fun `the film is back only once it reaches the cue`() {
        assertFalse(resumedAtCue(0, 10_000))
        assertFalse(resumedAtCue(8_000, 10_000))
        assertTrue(resumedAtCue(9_200, 10_000))
        assertTrue(resumedAtCue(10_000, 10_000))
    }
}
