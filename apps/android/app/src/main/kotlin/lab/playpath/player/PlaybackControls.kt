package lab.playpath.player

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
fun PlaybackControls(
    state: PlaybackUiState,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val showPause = state.playbackState == PlaybackState.Playing ||
        state.playbackState == PlaybackState.Seeking
    Row(modifier = modifier.fillMaxWidth()) {
        Button(onClick = if (showPause) onPause else onPlay) {
            Text(text = if (showPause) "Pause" else "Play")
        }
    }
}
