# Android

The Android app plays protected `playpath-bars` with [Media3 ExoPlayer](https://github.com/androidx/media) 1.11.1. It is the encrypted DASH session. The web app and iOS are other apps.

Requires origin A, the license service, a JDK, and the Android SDK. From `apps/android`, after `./pipeline/encrypt.sh` has written the protected package:

```bash
./wrong-kid.sh
./gradlew assembleDebug
```

`wrong-kid.sh` copies the protected menu and its init segments, and changes only the key id. The segments stay encrypted with the lab key. The content key is not read. The copy is a build product under `pipeline/protected/` and is not committed.

Point the emulator at the host before opening the app. The menu and the license URL are already `127.0.0.1`, and inside the emulator that address is the emulator itself.

```bash
adb reverse tcp:8080 tcp:8080
adb reverse tcp:8082 tcp:8082
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n lab.playpath.player/.MainActivity
```

DASH loads `http://127.0.0.1:8080/manifest.mpd`. `PlaybackSession` builds an `ExoPlayer`, sets that DASH `MediaItem`, and opens a `DefaultDrmSessionManager` for `org.w3.clearkey` at `http://127.0.0.1:8082/`. The license log shows `POST / 200` and the lab key id. The Compose screen shows the picture. Play and pause go through the session. Play after the title ends seeks to the start. Play after an error, and choosing the menu that is already selected, loads that menu again. The session does not choose a rung. The stock `PlayerView` bar is off. Stopping the activity pauses playback. Leaving the screen releases the player.

Wrong key loads `http://127.0.0.1:8080/manifest-wrong-kid.mpd`. The license log shows `POST / 403` and the other key id, and it does not log the key. The picture stays black. The screen says the title cannot be played. Logcat tag `playpath.event` contains one JSON object per DRM result, including `event: "drm"`, `result: "error"`, and `code: "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED"`. The app does not load the clear package.

## Screen

`MainActivity` sets `PlaypathTheme` and `PlayerScreen`. `PlayerScreen` keeps the selected menu and the session. `PlaybackControls` draws Pause while the engine is playing or seeking, and Play while it is paused or ended. A DRM error uses the same Play label and the sentence “The title cannot be played.”

```mermaid
flowchart TD
  activity["MainActivity"] --> screen["PlayerScreen"]
  screen --> controls["PlaybackControls"]
  screen --> session["PlaybackSession"]
  session --> exo["ExoPlayer"]
  exo --> drm["DefaultDrmSessionManager"]
  controls -->|play, pause| session
  session -->|snapshot| controls
```

`PlaybackSession` is the only type that talks to Media3. Controls do not import it, read a playlist, or receive key bytes.
