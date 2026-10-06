package lab.playpath.player

enum class PlaybackState {
    Paused,
    Playing,
    Seeking,
    Ended,
}

data class PlaybackUiState(
    val playbackState: PlaybackState = PlaybackState.Paused,
    val stalled: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val height: Int = 0,
    val bandwidthBps: Int = 0,
    val error: String? = null,
)
