package lab.playpath.player

import android.content.Context
import android.util.Log
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.KeyRequestInfo
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

// Media3 numbers DRM failures from 6000 through 6999.
private const val DRM_ERROR_FIRST = 6000
private const val DRM_ERROR_LAST = 6999

@OptIn(UnstableApi::class)
class PlaybackSession(
    context: Context,
    private val onState: (PlaybackUiState) -> Unit,
) : Player.Listener, AnalyticsListener {
    private val player: ExoPlayer
    private var snapshot = PlaybackUiState()
    private var seeking = false
    private var sessionId = ""
    private var drmReported = false
    private var drmCode: String? = null
    private var manifestUrl: String? = null
    private var released = false
    private var recordedHeight = 0
    private var recordedBandwidth = 0

    init {
        val httpFactory = DefaultHttpDataSource.Factory().setUserAgent("playpath-android")
        val mediaSourceFactory = DashMediaSource.Factory(httpFactory)
            .setDrmSessionManagerProvider {
                val drmCallback = HttpMediaDrmCallback(CLEAR_KEY_LICENSE_URL, httpFactory)
                DefaultDrmSessionManager.Builder()
                    .setUuidAndExoMediaDrmProvider(
                        C.CLEARKEY_UUID,
                        FrameworkMediaDrm.DEFAULT_PROVIDER,
                    )
                    .setPlayClearSamplesWithoutKeys(false)
                    .build(drmCallback)
            }
        player = ExoPlayer.Builder(context.applicationContext)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
        player.addListener(this)
        player.addAnalyticsListener(this)
    }

    fun createSurface(context: Context): View {
        return PlayerView(context).apply {
            player = this@PlaybackSession.player
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setKeepContentOnPlayerReset(false)
        }
    }

    fun load(manifestUrl: String) {
        if (released) {
            return
        }
        sessionId = UUID.randomUUID().toString()
        seeking = false
        drmReported = false
        drmCode = null
        recordedHeight = 0
        recordedBandwidth = 0
        this.manifestUrl = manifestUrl
        snapshot = PlaybackUiState()
        publish()
        val item = MediaItem.Builder()
            .setUri(manifestUrl)
            .setMimeType(MimeTypes.APPLICATION_MPD)
            .setDrmConfiguration(
                MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
                    .setLicenseUri(CLEAR_KEY_LICENSE_URL)
                    .build(),
            )
            .build()
        player.setMediaItem(item)
        player.prepare()
        player.playWhenReady = true
    }

    fun play() {
        if (released) {
            return
        }
        val manifest = manifestUrl
        if (player.playerError != null && manifest != null) {
            load(manifest)
            return
        }
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }
        player.play()
        publish()
    }

    fun pause() {
        if (released) {
            return
        }
        player.pause()
        publish()
    }

    fun seek(positionMs: Long) {
        if (released) {
            return
        }
        seeking = true
        player.seekTo(positionMs)
        publish()
    }

    fun release() {
        if (released) {
            return
        }
        released = true
        player.removeListener(this)
        player.removeAnalyticsListener(this)
        player.release()
    }

    override fun onTracksChanged(tracks: Tracks) {
        if (released) {
            return
        }
        var height = 0
        var bandwidth = 0
        var codecs = ""
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) {
                continue
            }
            for (index in 0 until group.length) {
                if (!group.isTrackSelected(index)) {
                    continue
                }
                val format = group.getTrackFormat(index)
                if (format.height > 0) {
                    height = format.height
                }
                if (format.bitrate > 0) {
                    bandwidth = format.bitrate
                }
                val formatCodecs = format.codecs
                if (!formatCodecs.isNullOrEmpty()) {
                    codecs = formatCodecs
                }
            }
        }
        if ((height == 0 && bandwidth == 0) ||
            (height == recordedHeight && bandwidth == recordedBandwidth)
        ) {
            return
        }
        recordedHeight = height
        recordedBandwidth = bandwidth
        logBitrate(height, bandwidth, codecs)
        publish()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_READY) {
            seeking = false
        }
        publish()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        publish()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            seeking = false
        }
        publish()
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        if (reason == Player.DISCONTINUITY_REASON_SEEK) {
            seeking = true
            publish()
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error.errorCode in DRM_ERROR_FIRST..DRM_ERROR_LAST) {
            reportDrm(error.errorCodeName)
        } else if (drmReported) {
            publish(error = DRM_ERROR)
        } else {
            publish(error = PLAYBACK_ERROR)
        }
    }

    override fun onDrmSessionManagerError(
        eventTime: AnalyticsListener.EventTime,
        error: Exception,
    ) {
        val playback = error as? PlaybackException
        val code = when {
            playback != null && playback.errorCode in DRM_ERROR_FIRST..DRM_ERROR_LAST ->
                playback.errorCodeName
            else -> error.javaClass.simpleName
        }
        reportDrm(code)
    }

    @Suppress("UNUSED_PARAMETER")
    override fun onDrmKeysLoaded(
        eventTime: AnalyticsListener.EventTime,
        keyRequestInfo: KeyRequestInfo,
    ) {
        // keyRequestInfo can carry the license request. It is not logged.
        if (drmReported) {
            return
        }
        drmReported = true
        logDrm(result = "ok", code = "")
    }

    private fun reportDrm(code: String) {
        val engineCode = code.startsWith("ERROR_CODE_")
        val loggedEngineCode = drmCode?.startsWith("ERROR_CODE_") == true
        if (!drmReported || (engineCode && !loggedEngineCode)) {
            drmReported = true
            drmCode = code
            logDrm(result = "error", code = code)
        }
        publish(error = DRM_ERROR)
    }

    private fun logBitrate(height: Int, bandwidth: Int, codecs: String) {
        val positionMs = if (released) 0 else player.currentPosition.coerceAtLeast(0)
        Log.i(
            EVENT_LOG,
            bitrateEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = positionMs,
                height = height,
                bandwidthBps = bandwidth,
                codecs = codecs,
            ),
        )
    }

    private fun logDrm(result: String, code: String) {
        val positionMs = if (released) 0 else player.currentPosition.coerceAtLeast(0)
        Log.i(
            EVENT_LOG,
            drmEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = positionMs,
                result = result,
                code = code,
            ),
        )
    }

    private fun publish(error: String? = snapshot.error) {
        if (released) {
            return
        }
        val duration = player.duration
        val next = PlaybackUiState(
            playbackState = stateOf(),
            stalled = player.playbackState == Player.STATE_BUFFERING &&
                player.playWhenReady &&
                !seeking,
            positionMs = player.currentPosition.coerceAtLeast(0),
            durationMs = if (duration > 0) duration else 0,
            height = recordedHeight,
            bandwidthBps = recordedBandwidth,
            error = error,
        )
        snapshot = next
        onState(next)
    }

    private fun stateOf(): PlaybackState {
        if (player.playbackState == Player.STATE_ENDED || player.playerError != null) {
            return PlaybackState.Ended
        }
        if (!player.playWhenReady) {
            return PlaybackState.Paused
        }
        if (seeking) {
            return PlaybackState.Seeking
        }
        return PlaybackState.Playing
    }
}

private fun utcNow(): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date())
}
