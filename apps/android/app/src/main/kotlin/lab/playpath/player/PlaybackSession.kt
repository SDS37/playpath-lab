package lab.playpath.player

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.KeyRequestInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import java.text.SimpleDateFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

// Media3 numbers DRM failures from 6000 through 6999.
private const val DRM_ERROR_FIRST = 6000
private const val DRM_ERROR_LAST = 6999
private const val CREATIVE_TIMEOUT_MS = 5_000L
private const val POSITION_TICK_MS = 200L

private enum class AdPhase {
    Off,
    Creative,
    Resume,
}

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
    private var cueMs: Long? = null
    private var creativeUrl: String? = null
    private var filmCueMs: Long? = null
    private var filmCueSeeked = false
    private var adPlayed = false
    private var adPhase = AdPhase.Off
    private var adAttempt = 0
    private var creativeAssigned = false
    private var creativeStarted = false
    private var startupLogged = false
    private var stitchedImpressionLogged = false
    private var loadStartedAt = 0L
    private var captions = true
    private val sessionJob = SupervisorJob()
    private val scope = CoroutineScope(sessionJob + Dispatchers.Main.immediate)
    private val httpFactory = DefaultHttpDataSource.Factory().setUserAgent("playpath-android")
    private val dashFactory = DashMediaSource.Factory(BackupHttpDataSourceFactory(httpFactory))
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

    init {
        player = ExoPlayer.Builder(context.applicationContext)
            .setMediaSourceFactory(dashFactory)
            .build()
        player.addListener(this)
        player.addAnalyticsListener(this)
        applyCaptions()
        scope.launch {
            while (isActive) {
                if (!released && adPhase == AdPhase.Off && atCue()) {
                    playCreative()
                }
                publish()
                delay(POSITION_TICK_MS)
            }
        }
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
        cueMs = null
        creativeUrl = null
        filmCueMs = null
        filmCueSeeked = false
        adPlayed = false
        adPhase = AdPhase.Off
        adAttempt += 1
        creativeAssigned = false
        creativeStarted = false
        startupLogged = false
        stitchedImpressionLogged = false
        loadStartedAt = SystemClock.elapsedRealtime()
        this.manifestUrl = manifestUrl
        snapshot = PlaybackUiState(captions = captions)
        publish()
        val attempt = adAttempt
        player.setMediaItem(filmItem(manifestUrl))
        player.prepare()
        player.playWhenReady = true
        readCue(attempt)
    }

    fun play() {
        if (released) {
            return
        }
        if (adPhase != AdPhase.Off) {
            player.play()
            publish()
            return
        }
        val manifest = manifestUrl
        if (player.playerError != null && manifest != null) {
            load(manifest)
            return
        }
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
            player.play()
            publish()
            return
        }
        player.play()
        publish()
        if (atCue()) {
            playCreative()
        }
    }

    fun pause() {
        if (released) {
            return
        }
        player.pause()
        publish()
    }

    fun setCaptions(enabled: Boolean) {
        if (released) {
            return
        }
        captions = enabled
        applyCaptions()
        publish()
    }

    fun seek(positionMs: Long) {
        if (released || adPhase != AdPhase.Off) {
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
        sessionJob.cancel()
        player.removeListener(this)
        player.removeAnalyticsListener(this)
        player.release()
    }

    override fun onDownstreamFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        mediaLoadData: MediaLoadData,
    ) {
        if (released || adPhase != AdPhase.Off) {
            return
        }
        if (mediaLoadData.trackType != C.TRACK_TYPE_VIDEO) {
            return
        }
        val format = mediaLoadData.trackFormat ?: return
        val height = format.height.coerceAtLeast(0)
        val bandwidth = format.bitrate.coerceAtLeast(0)
        val codecs = format.codecs ?: ""
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
            if (adPhase == AdPhase.Creative) {
                creativeStarted = true
            } else if (adPhase == AdPhase.Resume) {
                val cue = filmCueMs
                if (cue == null || resumedAtCue(player.currentPosition, cue)) {
                    filmCueMs = null
                    adPhase = AdPhase.Off
                } else if (!filmCueSeeked) {
                    filmCueSeeked = true
                    player.seekTo(cue)
                }
            }
        }
        if (
            playbackState == Player.STATE_ENDED &&
            adPhase == AdPhase.Creative &&
            creativeStarted
        ) {
            scope.launch { resumeFilm(completed = true) }
            return
        }
        publish()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        publish()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            seeking = false
            if (adPhase == AdPhase.Off && !startupLogged) {
                startupLogged = true
                logStartup()
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

    override fun onPlayerError(error: PlaybackException) {
        if (adPhase == AdPhase.Creative) {
            if (creativeFailure()) {
                scope.launch { resumeFilm(completed = false) }
            }
            return
        }
        if (adPhase == AdPhase.Resume) {
            adPhase = AdPhase.Off
        }
        val clean = if (manifestUrl == STITCHED_DASH) cleanMenu(STITCHED_DASH) else null
        if (
            adPhase == AdPhase.Off &&
            clean != null &&
            !startupLogged &&
            error.errorCode !in DRM_ERROR_FIRST..DRM_ERROR_LAST
        ) {
            scope.launch { load(clean) }
            return
        }
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
        if (adPhase == AdPhase.Creative) {
            return
        }
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

    private fun logStartup() {
        val manifest = manifestUrl ?: return
        val positionMs = if (released) 0 else player.currentPosition.coerceAtLeast(0)
        Log.i(
            EVENT_LOG,
            startupEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = positionMs,
                startupMs = SystemClock.elapsedRealtime() - loadStartedAt,
                manifestUrl = manifest,
            ),
        )
        if (manifest == STITCHED_DASH && !stitchedImpressionLogged) {
            stitchedImpressionLogged = true
            Log.i(
                EVENT_LOG,
                adEvent(
                    sessionId = sessionId,
                    at = utcNow(),
                    positionMs = positionMs,
                    action = "impression",
                    breakId = "preroll",
                    mode = "ssai",
                ),
            )
        }
    }

    private fun logAd(action: String) {
        Log.i(
            EVENT_LOG,
            adEvent(
                sessionId = sessionId,
                at = utcNow(),
                positionMs = cueMs ?: 0L,
                action = action,
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
            adPlaying = adPhase != AdPhase.Off,
            positionMs = player.currentPosition.coerceAtLeast(0),
            durationMs = if (duration > 0) duration else 0,
            height = recordedHeight,
            bandwidthBps = recordedBandwidth,
            captions = captions,
            error = error,
        )
        snapshot = next
        onState(next)
    }

    private fun applyCaptions() {
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setPreferredAudioLanguage("en")
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !captions)
            .setPreferredTextLanguage(if (captions) "en" else null)
            .setSelectUndeterminedTextLanguage(captions)
            .build()
    }

    private fun filmItem(manifestUrl: String): MediaItem {
        return MediaItem.Builder()
            .setUri(manifestUrl)
            .setMimeType(MimeTypes.APPLICATION_MPD)
            .setDrmConfiguration(
                MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
                    .setLicenseUri(CLEAR_KEY_LICENSE_URL)
                    .build(),
            )
            .build()
    }

    private fun readCue(attempt: Int) {
        scope.launch {
            val midroll = withContext(Dispatchers.IO) { fetchMidroll() }
            if (released || attempt != adAttempt || midroll == null) {
                return@launch
            }
            cueMs = presentationCueMs(midroll.cueMs, manifestUrl ?: "")
            creativeUrl = midroll.mediaUrl
        }
    }

    private fun creativeFailure(): Boolean {
        if (!creativeAssigned) {
            return false
        }
        val current = player.currentMediaItem?.localConfiguration?.uri?.toString()
        return current == null || current == creativeUrl
    }

    private fun atCue(): Boolean {
        val cue = cueMs
        if (creativeUrl == null || cue == null || adPlayed || adPhase != AdPhase.Off) {
            return false
        }
        val ended = player.playbackState == Player.STATE_ENDED || player.playerError != null
        return playingAtCue(
            currentTimeMs = player.currentPosition,
            cueMs = cue,
            paused = !player.playWhenReady,
            ended = ended,
        )
    }

    private fun playCreative() {
        if (released || adPlayed || adPhase != AdPhase.Off) {
            return
        }
        val url = creativeUrl ?: return
        adPlayed = true
        adPhase = AdPhase.Creative
        creativeAssigned = false
        creativeStarted = false
        val attempt = adAttempt
        val item = MediaItem.Builder()
            .setUri(url)
            .setMimeType(MimeTypes.VIDEO_MP4)
            .build()
        player.stop()
        player.setMediaSource(ProgressiveMediaSource.Factory(httpFactory).createMediaSource(item))
        creativeAssigned = true
        player.prepare()
        player.play()
        logAd("impression")
        logAd("start")
        scope.launch {
            delay(CREATIVE_TIMEOUT_MS)
            if (
                !released &&
                attempt == adAttempt &&
                adPhase == AdPhase.Creative &&
                !creativeStarted
            ) {
                resumeFilm(completed = false)
            }
        }
    }

    private fun resumeFilm(completed: Boolean) {
        if (released || adPhase != AdPhase.Creative) {
            return
        }
        logAd(if (completed) "complete" else "error")
        val manifest = manifestUrl
        val cue = cueMs
        if (manifest == null || cue == null) {
            adPhase = AdPhase.Off
            publish(error = PLAYBACK_ERROR)
            return
        }
        adAttempt += 1
        val attempt = adAttempt
        val resumePlaying = player.playWhenReady
        adPhase = AdPhase.Resume
        creativeAssigned = false
        creativeStarted = false
        filmCueMs = cue
        filmCueSeeked = false
        player.stop()
        player.setMediaItem(filmItem(manifest), cue)
        player.prepare()
        player.playWhenReady = resumePlaying
        scope.launch {
            delay(CREATIVE_TIMEOUT_MS)
            if (!released && attempt == adAttempt && adPhase == AdPhase.Resume) {
                adPhase = AdPhase.Off
                publish(error = PLAYBACK_ERROR)
            }
        }
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
