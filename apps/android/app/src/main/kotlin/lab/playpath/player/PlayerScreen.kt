package lab.playpath.player

import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

private val ScreenPadding = 12.dp

@Composable
fun PlayerScreen() {
    val context = LocalContext.current
    var state by remember { mutableStateOf(PlaybackUiState()) }
    var manifestUrl by remember { mutableStateOf(DASH_MANIFEST) }
    val session = remember {
        PlaybackSession(context) { next -> state = next }
    }
    DisposableEffect(session) {
        onDispose { session.release() }
    }
    LaunchedEffect(manifestUrl) {
        session.load(manifestUrl)
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(ScreenPadding),
    ) {
        MenuButton(
            label = "DASH",
            onClick = { manifestUrl = DASH_MANIFEST },
        )
        MenuButton(
            label = "Wrong key",
            onClick = { manifestUrl = WRONG_KEY_MANIFEST },
        )
        AndroidView(
            factory = { viewContext -> session.createSurface(viewContext) },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            update = { view: View -> view.contentDescription = "playpath-bars" },
        )
        PlaybackControls(
            state = state,
            onPlay = session::play,
            onPause = session::pause,
        )
        val error = state.error
        if (error != null) {
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun MenuButton(
    label: String,
    onClick: () -> Unit,
) {
    Button(onClick = onClick) {
        Text(text = label)
    }
}

@Composable
fun PlaypathTheme(content: @Composable () -> Unit) {
    val scheme = darkColorScheme(
        background = BACKGROUND,
        surface = CONTROL,
        onBackground = TEXT,
        onSurface = TEXT,
        primary = ACCENT,
        error = DANGER,
        onError = BACKGROUND,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}

private val BACKGROUND = Color(0xFF111111)
private val CONTROL = Color(0xFF1E1E1E)
private val TEXT = Color(0xFFF4F4F4)
private val ACCENT = Color(0xFF8EB6FF)
private val DANGER = Color(0xFFFFB4B4)
