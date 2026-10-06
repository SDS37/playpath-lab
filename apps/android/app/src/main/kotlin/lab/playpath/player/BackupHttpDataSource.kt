package lab.playpath.player

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.TransferListener
import java.io.IOException

// Media reads go through this source. The license callback keeps the plain
// HTTP factory, so a segment failure cannot move a license POST.
@OptIn(UnstableApi::class)
internal class BackupHttpDataSource(
    private val primary: HttpDataSource,
    private val backup: HttpDataSource,
) : DataSource {
    private var current: HttpDataSource = primary
    private var opened = false

    override fun addTransferListener(transferListener: TransferListener) {
        primary.addTransferListener(transferListener)
        backup.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        current = primary
        return try {
            val length = primary.open(dataSpec)
            opened = true
            length
        } catch (error: HttpDataSource.InvalidResponseCodeException) {
            closeQuietly(primary)
            val next = failoverSegmentUrl(error.responseCode, dataSpec.uri.toString())
                ?: throw error
            current = backup
            val length = backup.open(dataSpec.buildUpon().setUri(Uri.parse(next)).build())
            opened = true
            length
        }
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        return current.read(buffer, offset, length)
    }

    override fun getUri(): Uri? {
        return if (opened) current.uri else null
    }

    override fun close() {
        if (!opened) {
            return
        }
        opened = false
        current.close()
    }

    private fun closeQuietly(source: HttpDataSource) {
        try {
            source.close()
        } catch (_: IOException) {
            // The failed open already dropped the connection.
        }
    }
}

@OptIn(UnstableApi::class)
internal class BackupHttpDataSourceFactory(
    private val http: HttpDataSource.Factory,
) : DataSource.Factory {
    override fun createDataSource(): DataSource {
        return BackupHttpDataSource(http.createDataSource(), http.createDataSource())
    }
}
