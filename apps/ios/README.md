# iOS

The iOS app plays clear `playpath-bars` with [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer). The menu is `http://127.0.0.1:8084/master.m3u8`, from the origin pointed at `pipeline/package/playpath-bars`. This PoC plays that clear HLS menu. It does not call the license service.

FairPlay needs an FPS certificate and a key server module, and it needs an [`AVContentKeySession`](https://developer.apple.com/documentation/avfoundation/avcontentkeysession) on the asset. Those credentials are not in this PoC. The app does not create that session and does not report a FairPlay result. See [beyond the PoC](../../docs/beyond-poc.md).

Requires the clear package and an iOS simulator. From `apps/ios`:

```bash
xcodebuild -project Playpath.xcodeproj -scheme Playpath -sdk iphonesimulator -configuration Debug -derivedDataPath build build
```

The simulator shares the host’s `127.0.0.1`, so the menu URL does not need a port reverse. The ads service is `http://127.0.0.1:8083`. Install `build/Build/Products/Debug-iphonesimulator/Playpath.app` and open it. On an iOS 27 simulator the screen shows the color bars and Pause while the picture changes. The license log does not record a request from that play. The session logs `startup` when playback starts, `ad` when the mid-roll starts and ends, and `bitrate` from the access log and the presentation height. That play does not log `drm`. On an iOS 27 simulator one session logged `startup` for `http://127.0.0.1:8084/master.m3u8`, `bitrate` with `height` 720 and `bandwidthBps` 2157897, and the mid-roll `ad` events. The label was 0:24 / 1:00. The controls do not pick a rung. On an iOS 27 simulator, after `AVPlayer` had selected height 1080 and `bandwidthBps` 4670889, restricting throughput logged `bitrate` with `height` 720 and `bandwidthBps` 2157897. The picture was the color bars and the label was Play at 1:00 / 1:00.

`PlaybackSession` creates an `AVPlayer` for that URL, observes `timeControlStatus`, the item status, and the access log. The picture is an `AVPlayerLayer`. Play, pause, and seek go through the session. At 10 seconds the session plays the VAST creative, seek is disabled, a drag leaves the creative, and the film continues from the cue. The impression URL is not requested. The session does not choose a rung. The system transport bar is off. Entering the background pauses playback.

## Screen

`SceneDelegate` shows `PlayerViewController`. That controller keeps the session and `PlaybackControlsView`. The controls draw Pause while the engine is playing or seeking, and Play while it is paused or ended. Seek is disabled during the mid-roll, and the time label reads Ad. Color, type, and spacing are set on the views. A failed item says “Playback failed.”

```mermaid
flowchart TD
  scene["SceneDelegate"] --> screen["PlayerViewController"]
  screen --> controls["PlaybackControlsView"]
  screen --> session["PlaybackSession"]
  session --> player["AVPlayer"]
  controls -->|play, pause, seek| session
  session -->|snapshot| controls
```

`PlaybackSession` is the only type that talks to AVFoundation for playback policy. Controls do not import it, read a playlist, or receive key bytes.
