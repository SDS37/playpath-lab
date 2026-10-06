package lab.playpath.player

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import java.util.Locale

@Composable
fun PlaybackControls(
    state: PlaybackUiState,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val showPause = state.playbackState == PlaybackState.Playing ||
        state.playbackState == PlaybackState.Seeking
    val duration = state.durationMs.coerceAtLeast(0)
    val rangeEnd = if (duration > 0) duration.toFloat() else 1f
    val position = state.positionMs.coerceIn(0, rangeEnd.toLong()).toFloat()
    val seekEnabled = !state.adPlaying && duration > 0
    val spacing = LocalPlaypathSpacing.current
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(spacing.bar),
    ) {
        Button(onClick = if (showPause) onPause else onPlay) {
            Text(
                text = if (showPause) "Pause" else "Play",
                style = MaterialTheme.typography.labelLarge,
            )
        }
        Slider(
            value = position,
            onValueChange = { next ->
                if (!state.adPlaying) {
                    onSeek(next.toLong())
                }
            },
            valueRange = 0f..rangeEnd,
            enabled = seekEnabled,
            modifier = if (seekEnabled) {
                Modifier.semantics { contentDescription = "Seek" }
            } else {
                Modifier.clearAndSetSemantics {
                    contentDescription = "Seek"
                    disabled()
                }
            },
        )
        Text(
            text = timeLabel(state),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )
        if (state.stalled) {
            Text(
                text = "Buffering",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

private fun timeLabel(state: PlaybackUiState): String {
    val prefix = if (state.adPlaying) "Ad " else ""
    return prefix + formatTime(state.positionMs) + " / " + formatTime(state.durationMs)
}

private fun formatTime(positionMs: Long): String {
    val totalSeconds = (positionMs.coerceAtLeast(0) / 1000).toInt()
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return String.format(Locale.US, "%d:%02d", minutes, seconds)
}
