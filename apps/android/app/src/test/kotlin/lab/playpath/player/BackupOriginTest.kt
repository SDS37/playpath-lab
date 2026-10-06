package lab.playpath.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class BackupOriginTest {
    @Test
    fun `a refused segment keeps its path on origin B`() {
        assertEquals(
            "$backupOrigin/720p/seg_5.m4s",
            backupSegmentUrl("$primaryOrigin/720p/seg_5.m4s"),
        )
        assertEquals(
            "$backupOrigin/audio/seg_3.m4s?x=1",
            backupSegmentUrl("$primaryOrigin/audio/seg_3.m4s?x=1"),
        )
    }

    @Test
    fun `menus init segments and other hosts stay put`() {
        assertNull(backupSegmentUrl("$primaryOrigin/manifest.mpd"))
        assertNull(backupSegmentUrl("$primaryOrigin/720p/init_0.mp4"))
        assertNull(backupSegmentUrl("$backupOrigin/720p/seg_5.m4s"))
        assertNull(backupSegmentUrl("http://127.0.0.1:8082/"))
        assertNull(backupSegmentUrl("http://127.0.0.1:8083/preroll/creative.mp4"))
    }

    @Test
    fun `only a 503 on a media segment fails over`() {
        val segment = "$primaryOrigin/1080p/seg_3.m4s"
        assertEquals("$backupOrigin/1080p/seg_3.m4s", failoverSegmentUrl(503, segment))
        assertNull(failoverSegmentUrl(404, segment))
        assertNull(failoverSegmentUrl(503, "$primaryOrigin/manifest.mpd"))
    }

    @Test
    fun `the mapped URL does not carry key material`() {
        val mapped = backupSegmentUrl("$primaryOrigin/720p/seg_0.m4s")
        assertFalse(mapped!!.contains("ffefcdab"))
    }
}
