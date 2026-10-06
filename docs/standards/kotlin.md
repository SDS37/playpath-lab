# Kotlin standards

Kotlin is the Android app: Jetpack Compose for controls, and the code that configures Media3. Media3 itself still contains Java. We call that Java. We do not restyle it. See [dependencies.md](dependencies.md).

## Primary sources

1. [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
2. [Android Kotlin style guide](https://developer.android.com/kotlin/style-guide)
3. [Jetpack Compose](https://developer.android.com/compose), in particular [state](https://developer.android.com/develop/ui/compose/state), [side-effects](https://developer.android.com/develop/ui/compose/side-effects), and [accessibility](https://developer.android.com/develop/ui/compose/accessibility)
4. [Media3 ExoPlayer](https://developer.android.com/media/media3/exoplayer) and [DRM](https://developer.android.com/media/media3/exoplayer/drm)

Where the Android style guide and the Kotlin conventions differ, follow the Android guide inside `apps/android`. They agree on naming, four-space indent, and the order of declarations. Android’s line length for review is 100 characters.

Format with the official Kotlin style (IntelliJ / Android Studio “Kotlin style guide”, or ktlint configured to that style). Do not hand-format.

## Naming and layout

From the Kotlin conventions:

- Packages are lowercase, with no underscores: `lab.playpath.player`.
- Classes and objects are upper camel case. Functions, properties, and local variables are lower camel case.
- `@Composable` functions that return `Unit` are upper camel case, like types: `PlaybackControls`.
- Factory functions that return an instance may use the type’s name.
- Constants (`const val`, or a top-level immutable `val` with no custom getter) are screaming snake case.
- Backing properties use an underscore prefix only for that documented pattern (`_elementList` / `elementList`).
- A class is a noun. A function is a verb. `sort` mutates, `sorted` returns a copy. Avoid empty words such as `Manager` and `Wrapper`. The type that owns Media3 is `PlaybackSession`.
- Two-letter acronyms stay uppercase (`Io`). Longer acronyms capitalize the first letter (`DrmSession`, `HttpClient`).
- Tests may use backtick names. Production code does not.

File and class layout follow the conventions: properties and initializers, then secondary constructors, then methods, then the companion object. Related declarations share a file. Do not create a file that is only extensions for a type the whole app uses; put those extensions next to the caller that needs them.

Source files match the package directory. A file with one class is named after that class.

## Formatting

- Four spaces. No tabs.
- Opening brace at the end of the line.
- Expression bodies for functions that are a single expression.
- Omit a redundant `Unit` return and a redundant `public`.
- Modifier order is the order in the Kotlin conventions (`override` before `suspend`, annotations before modifiers).
- Trailing commas in multiline parameter lists are used, matching the convention’s long-signature example.
- No horizontal alignment of declarations.

## Compose

- State hoisting: the session holds playback state. `PlaybackControls` receives state and lambdas.
- Unidirectional flow. Controls do not reach into `ExoPlayer`.
- Remember the player only inside a holder that releases it. `DisposableEffect` (or a `ViewModel.onCleared`) calls `player.release()`.
- `LaunchedEffect` collects one-off session work tied to a key. It is not a second player loop.
- State that the bar reads is a `data class` snapshot (`PlaybackUiState`), produced from `Player.Listener` callbacks. Compose does not observe the player object directly in arbitrary composables.
- Theme color, type, and spacing come from `MaterialTheme`. Magic numbers in modifiers are named constants when they are part of the bar’s layout.

```kotlin
@Composable
fun PlaybackControls(
    state: PlaybackUiState,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val showPause = state.playbackState == PlaybackState.Playing ||
        state.playbackState == PlaybackState.Seeking
    Button(onClick = if (showPause) onPause else onPlay, modifier = modifier) {
        Text(text = if (showPause) "Pause" else "Play")
    }
}
```

## Media3

- Build the player with `ExoPlayer.Builder`.
- Pass a `MediaItem` for the DASH URL.
- Clear Key goes through Media3’s DRM session API and the license URL. The key bytes are not a parameter of a composable.
- Listen with `Player.Listener`. Map those callbacks into [playback events](../playback-events.md) in `PlaybackSession`, not in a composable.
- Track selection stays on the player’s ABR. The UI does not set a video format except through a public track-selection override the product has asked for. The PoC has not asked for one.

## Coroutines

Suspending functions are used for our own HTTP (ads fallback, event post). Media3’s listener thread is not a coroutine context we block. Post back to `Main` before updating snapshot state.

Errors from our HTTP are explicit. A license failure is a `drm` event, not a silent `null`.

## Review rejects

- A composable that constructs `ExoPlayer` with no release
- Logging `MediaItem` DRM request bodies
- Playlist parsing in Kotlin to choose a rung
- Java sources in `apps/android` for code we write. Interop with Media3’s Java types is normal
- Wildcard imports
