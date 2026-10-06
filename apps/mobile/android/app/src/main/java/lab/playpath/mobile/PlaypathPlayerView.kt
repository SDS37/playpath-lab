package lab.playpath.mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.widget.FrameLayout
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
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

private const val EVENT_LOG = "playpath.event"
private const val DRM_ERROR_FIRST = 6000
private const val DRM_ERROR_LAST = 6999
private const val POSITION_TICK_MS = 200L

/**
 * Media3 renders the picture. JavaScript never sees samples.
 * keyRequestInfo can carry the license request. It is not logged.
 */
@OptIn(UnstableApi::class)
class PlaypathPlayerView(context: Context) :
    FrameLayout(context),
    Player.Listener,
    AnalyticsListener {
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            if (!released) {
                publish()
                handler.postDelayed(this, POSITION_TICK_MS)
            }
        }
    }
    private var released = false
    private var seeking = false
    private var sessionId = ""
    private var manifestUrl: String? = null
    private var startupLogged = false
    private var drmReported = false
    private var loadStartedAt = 0L
    private var recordedHeight = 0
    private var recordedBandwidth = 0
    private var errorMessage: String? = null
    private var playWhenLoaded = false

    init {
        val httpFactory = DefaultHttpDataSource.Factory().setUserAgent("playpath-mobile")
        val dashFactory = DashMediaSource.Factory(httpFactory)
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
            .setMediaSourceFactory(dashFactory)
            .build()
        player.addListener(this)
        player.addAnalyticsListener(this)
        val surface = PlayerView(context).apply {
            this.player = this@PlaypathPlayerView.player
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        }
        addView(surface)
        handler.post(ticker)
    }

    fun setManifestUrl(url: String?) {
        if (released || url.isNullOrEmpty() || url == manifestUrl) {
            return
        }
        manifestUrl = url
        sessionId = UUID.randomUUID().toString()
        startupLogged = false
        drmReported = false
        recordedHeight = 0
        recordedBandwidth = 0
        errorMessage = null
        loadStartedAt = SystemClock.elapsedRealtime()
        player.setMediaItem(filmItem(url))
        player.prepare()
        player.playWhenReady = playWhenLoaded
        publish()
    }

    fun play() {
        if (released) {
            return
        }
        playWhenLoaded = true
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
        playWhenLoaded = false
        player.pause()
        publish()
    }

    fun seekToMs(positionMs: Int) {
        if (released) {
            return
        }
        seeking = true
        player.seekTo(positionMs.toLong().coerceAtLeast(0))
        publish()
    }

    fun releasePlayer() {
        if (released) {
            return
        }
        released = true
        handler.removeCallbacks(ticker)
        player.removeListener(this)
        player.removeAnalyticsListener(this)
        player.release()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            seeking = false
            if (!startupLogged && manifestUrl != null) {
                startupLogged = true
                emitEvent(
                    startupEvent(
                        sessionId = sessionId,
                        at = utcNow(),
                        positionMs = player.currentPosition.coerceAtLeast(0),
                        startupMs = SystemClock.elapsedRealtime() - loadStartedAt,
                        manifestUrl = manifestUrl ?: "",
                    ),
                )
            }
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

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_READY) {
            seeking = false
        }
        publish()
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error.errorCode in DRM_ERROR_FIRST..DRM_ERROR_LAST) {
            errorMessage = DRM_ERROR
            if (!drmReported) {
                drmReported = true
                emitEvent(
                    drmEvent(
                        sessionId = sessionId,
                        at = utcNow(),
                        positionMs = player.currentPosition.coerceAtLeast(0),
                        result = "error",
                        code = error.errorCodeName,
                    ),
                )
            }
        } else {
            errorMessage = PLAYBACK_ERROR
        }
        publish()
    }

    override fun onDrmKeysLoaded(
        eventTime: AnalyticsListener.EventTime,
        keyRequestInfo: KeyRequestInfo,
    ) {
        if (drmReported) {
            return
        }
        drmReported = true
        emitEvent(
            drmEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = player.currentPosition.coerceAtLeast(0),
                result = "ok",
                code = "",
            ),
        )
    }

    override fun onTracksChanged(tracks: Tracks) {
        var height = 0
        var bandwidth = 0
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
            }
        }
        if (height <= 0 && bandwidth <= 0) {
            return
        }
        if (height == recordedHeight && bandwidth == recordedBandwidth) {
            return
        }
        recordedHeight = height
        recordedBandwidth = bandwidth
        emitEvent(
            bitrateEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = player.currentPosition.coerceAtLeast(0),
                height = height,
                bandwidthBps = bandwidth,
            ),
        )
        publish()
    }

    private fun filmItem(url: String): MediaItem {
        return MediaItem.Builder()
            .setUri(url)
            .setMimeType(MimeTypes.APPLICATION_MPD)
            .setDrmConfiguration(
                MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
                    .setLicenseUri(CLEAR_KEY_LICENSE_URL)
                    .build(),
            )
            .build()
    }

    private fun publish() {
        if (released) {
            return
        }
        val duration = player.duration
        val payload = Arguments.createMap().apply {
            putString("playbackState", stateName())
            putBoolean(
                "stalled",
                player.playbackState == Player.STATE_BUFFERING &&
                    player.playWhenReady &&
                    !seeking,
            )
            putBoolean("adPlaying", false)
            putInt("positionMs", player.currentPosition.coerceAtLeast(0).toInt())
            putInt("durationMs", if (duration > 0) duration.toInt() else 0)
            putString("error", errorMessage ?: "")
        }
        emit("onSnapshot", payload)
    }

    private fun stateName(): String {
        if (player.playbackState == Player.STATE_ENDED || player.playerError != null) {
            return "ended"
        }
        if (!player.playWhenReady) {
            return "paused"
        }
        if (seeking) {
            return "seeking"
        }
        return "playing"
    }

    private fun emitEvent(json: String) {
        Log.i(EVENT_LOG, json)
        val payload = Arguments.createMap().apply {
            putString("json", json)
        }
        emit("onPlaybackEvent", payload)
    }

    private fun emit(eventName: String, payload: WritableMap) {
        val reactContext = context as? ReactContext ?: return
        if (id == NO_ID) {
            return
        }
        val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
        dispatcher.dispatchEvent(BridgeEvent(UIManagerHelper.getSurfaceId(this), id, eventName, payload))
    }
}

private class BridgeEvent(
    surfaceId: Int,
    viewId: Int,
    private val name: String,
    private val payload: WritableMap,
) : Event<BridgeEvent>(surfaceId, viewId) {
    override fun getEventName(): String = name

    override fun getEventData(): WritableMap = payload
}

private fun utcNow(): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date())
}
