# Engines

Which engine plays `playpath-bars` on which device, and the official way that engine is embedded. The session in each app is the only caller. See [ADR-004](architecture-decision-records.md) and [ADR-005](architecture-decision-records.md).

| Device | Engine | Menu in this PoC | DRM in this PoC |
|---|---|---|---|
| Chrome, Edge, Firefox | [Shaka Player](https://shaka-project.github.io/shaka-player/docs/api/tutorial-welcome.html) | Protected DASH, and protected HLS when we need Shaka’s EME path | Clear Key via EME |
| Chrome, Edge, Firefox | [hls.js](https://github.com/video-dev/hls.js/) | Clear HLS | None. Do not add it here |
| Safari | Native HLS on the media element | Clear HLS | None in the PoC |
| Safari | Shaka | Protected HLS, when a lab encryption is played on Safari | Clear Key, or FairPlay later |
| Android | [Media3 ExoPlayer](https://developer.android.com/media/media3/exoplayer) | DASH | Clear Key via Media3’s DRM session |
| iOS | [`AVPlayer`](https://developer.apple.com/documentation/avfoundation/avplayer) | HLS | None in the PoC. Production seam is [`AVContentKeySession`](https://developer.apple.com/documentation/avfoundation/avcontentkeysession) |
| React Native | Those same native engines behind a native view | The menu that engine already plays | The same rule as that engine |
| TV or Cast web page | Shaka, or the platform player | HLS or DASH | Only if that runtime’s EME stack is actually present |

## Shaka Player

Primary tutorial: [Welcome](https://shaka-project.github.io/shaka-player/docs/api/tutorial-welcome.html) and [basic usage](https://shaka-project.github.io/shaka-player/docs/api/tutorial-basic-usage.html). DRM configuration: the player’s DRM tutorial in the same manual.

The page installs the polyfills Shaka requires, constructs `shaka.Player` on a media element, attaches an error listener, then `load`s a manifest URI. Clear Key is a DRM server entry for `org.w3.clearkey` pointing at `http://127.0.0.1:8082/`. The application does not read key material out of the EME session. The session logs `bitrate` from the active variant on `adaptation`. A Shaka `buffering` event keeps `stalled` until Shaka reports that buffering has ended. hls.js has no buffering event, so that play sets `stalled` from the element's `readyState`. The Buffering label observed on clear HLS came from `readyState`. `packages/playback-events` validates that [playback event](playback-events.md) document. The session logs `startup` when playback first starts, `drm` for a Shaka play, and `ad` when the mid-roll starts and ends. On Chrome, one protected DASH session logged `startup` for `http://127.0.0.1:8080/manifest.mpd`, `drm` with `result` `ok`, that mid-roll `ad`, and `bitrate` from `height` 720 and `bandwidthBps` 2164878 to `height` 1080 and `bandwidthBps` 4677870. The picture was the color bars at 0:23 / 1:00. Stitched loads `http://127.0.0.1:8083/ssai/dash/manifest.mpd`. On Chrome that play shows the green pre-roll, then the color bars at 0:10 / 1:05, and logs an `ad` impression with `breakId` `preroll` and `mode` `ssai`, then one with `breakId` `midroll` and `mode` `csai`. The impression URL is not requested. With the ads service stopped, that same control reaches 0:16 / 1:00 of color bars and the startup event names `http://127.0.0.1:8080/manifest.mpd`. `drm` with `result` `ok` is logged once the film period is playing. hls.js logs `startup` and `ad` and does not log `drm`. The impression URL is not requested. Captions starts on. The session selects the English audio rendition and the English text track already in the menu. After a replacement WebVTT was passed to `./pipeline/master.sh` and the package was rebuilt, the picture showed Rebuilt cue at ten. When origin A returns an error for a media segment, the next attempt requests that same path on `http://127.0.0.1:8081`. Menus, init segments, and the license POST stay on their own URLs. On Chrome, with `-refuse-segments`, protected DASH reached 0:25 and `1080p/seg_3.m4s` was 503 on origin A and 200 on origin B.

Shaka is the web player whenever the title is encrypted, whether the menu is DASH or HLS. Shaka 5.2.12 does not parse the lab HLS key format `urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e`. The web session rewrites that playlist line to the key format Shaka does parse, maps `com.widevine.alpha` to `org.w3.clearkey`, and puts a Clear Key init-data box in the data URI. The box is built from the key id already in the playlist. The content key stays out of the page, and the license request stays on `http://127.0.0.1:8082/`.

## hls.js

Primary source: the project [README](https://github.com/video-dev/hls.js/).

The web session uses hls.js 1.7.3 for the clear menu `http://127.0.0.1:8084/master.m3u8` on Chrome, Edge, and Firefox, where `Hls.isSupported()` is true. The sequence is: construct `Hls`, `loadSource` that master playlist, `attachMedia` the element. Destroy the instance when the screen goes away. Safari plays that menu on the media element and does not construct hls.js, including when hls.js also reports support, because `canPlayType` says the element can play HLS. Chromium returns `maybe` for that type too, so the Safari branch is the Apple vendor rather than the type string alone. On Safari 26.6.2 that play shows the color bars and the control reaches 1:00 / 1:00. The playlist request is `Sec-Fetch-Dest: video` and `Sec-Fetch-Mode: no-cors`, with no `Origin` header, and the license log has no request from it. A browser that cannot run hls.js and can play HLS also uses the element.

`LEVEL_SWITCHED` logs `bitrate` with that level’s height, bandwidth, and codecs. On Chrome, after hls.js has selected 1080p (`bandwidthBps` 4670889), restricting throughput logs `bitrate` with `height` 720 and `bandwidthBps` 2157897. The control does not pick that rung. While the first segment is still arriving the bar says Buffering and Pause. At the end of the title the control reads 1:00 / 1:00 and Play.

hls.js covers a real gap: Chromium and Firefox do not play HLS by themselves. It is a weak place to hang DRM. The protected package does not go through this object.

## Media3 ExoPlayer

Primary sources: [Get started](https://developer.android.com/media/media3/exoplayer) and [DRM](https://developer.android.com/media/media3/exoplayer/drm).

Kotlin builds an `ExoPlayer` with `ExoPlayer.Builder`, sets a `MediaItem` whose URI is the DASH manifest, and prepares. Clear Key uses Media3’s DRM session manager and the license URL. A listener (`Player.Listener`) is the source of playing, stalled, and track changes. Release the player in the Compose `DisposableEffect` or the `ViewModel`’s `onCleared`.

Media3 1.11.1 is the build in `apps/android`. `PlaybackSession` opens a `DefaultDrmSessionManager` for `org.w3.clearkey` at `http://127.0.0.1:8082/`. The content key is not a parameter. On an emulator, `adb reverse` maps `127.0.0.1:8080`, `127.0.0.1:8081`, `127.0.0.1:8082`, and `127.0.0.1:8083` to the host, because those are the URLs already written into the menu, the backup origin, the license service, and the mid-roll. When origin A returns 503 for a `.m4s`, the media data source opens that same path on `http://127.0.0.1:8081`. The license callback stays on `http://127.0.0.1:8082/`. Stitched loads `http://127.0.0.1:8083/ssai/dash/manifest.mpd`. On the emulator that play shows the green pre-roll, then the color bars, at 0:32 / 1:05, and logcat has the preroll impression and the mid-roll impression. The impression URL is not requested. With the ads service stopped, Stitched shows the color bars and the label is 0:05 / 1:00. Logcat names `http://127.0.0.1:8080/manifest.mpd` and does not log a preroll impression. On the emulator, with `-refuse-segments`, protected DASH reached 0:50 and `720p/seg_0.m4s` was 503 on origin A and 200 on origin B. The observed play shows the color bars after `POST / 200` with the lab key id. On the emulator, one DASH session logged `startup` for `http://127.0.0.1:8080/manifest.mpd`, `drm` with `result` `ok`, the mid-roll `ad` events, and `bitrate` with `height` 1080 and `bandwidthBps` 4545011. The label was 0:21 / 1:00. `./wrong-kid.sh` writes a menu whose key id the service does not hold. That play is `POST / 403`, a black picture, and a `drm` event with `result: "error"` and `code: "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED"`. The app does not load the clear package. Stopping the license service, then playing the encrypted DASH menu, is a black picture and `playpath.event` has `drm` with `result: "error"` and `code: "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED"`. The clear package is not requested. The stock `PlayerView` control bar is off. Play, pause, and seek are intents on the session. At 10 seconds the session plays the VAST creative, seek is disabled, a drag leaves the creative, and the film continues from the cue. The impression URL is not requested. Logcat tag `playpath.event` logs `startup` when playback starts and `ad` when the mid-roll starts and ends. The session selects the English audio rendition and the English text track, and does not choose a video rung. On the emulator, after that same caption rebuild, the picture showed Rebuilt cue alpha. The session logs `bitrate` from the video format Media3 loads. On the emulator, after that format was height 1080 and `bandwidthBps` 4545011, restricting throughput logged `bitrate` with `height` 720 and `bandwidthBps` 2032019. The picture was the color bars and the label was Play at 1:00 / 1:00. Back from the Compose screen leaves the activity. Logcat then shows `ExoPlayerImpl: Release` for the same instance that logged `Init`, and the launcher is in front.

Media3 still contains Java. The app code that configures it is Kotlin. See [standards/dependencies.md](standards/dependencies.md).

The Compose screen draws our controls. A stock `PlayerView` control bar is not the product UI. A surface view may still display frames.

## AVPlayer

Primary sources: [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) and [HTTP Live Streaming](https://developer.apple.com/documentation/http-live-streaming).

Swift creates an `AVPlayer` with the HLS URL, observes `timeControlStatus`, and uses the item’s access log when a variant change needs to be reported. Play, pause, and seek are calls on the player. The view layer or player view controller’s view shows frames. Transport controls are UIKit views we own.

FairPlay, when a certificate exists, is an `AVContentKeySession` attached to the asset, as [FairPlay Streaming](https://developer.apple.com/streaming/fps/) describes. Until then the iOS happy path is clear HLS, and the session type keeps a single place where that key session will be created. `apps/ios` does not create that session. On an iOS 27 simulator the clear menu shows the color bars and Pause while the picture changes. At 10 seconds the label reads Ad, seek is disabled, a drag leaves the creative, and the film continues from the cue. The impression URL is not requested. That play does not appear in the license log. The session logs `startup` when playback starts, `ad` when the mid-roll starts and ends, and `bitrate` from the access log and `presentationSize`. That play does not log `drm`. On an iOS 27 simulator one session logged `startup` for `http://127.0.0.1:8084/master.m3u8`, `bitrate` with `height` 720 and `bandwidthBps` 2157897, and the mid-roll `ad` events. The label was 0:24 / 1:00. The session selects the English audible option and the English legible option from the menu. On the simulator, after that same caption rebuild, the screen showed Rebuilt cue alpha. On an iOS 27 simulator, after `AVPlayer` had selected height 1080 and `bandwidthBps` 4670889, restricting throughput logged `bitrate` with `height` 720 and `bandwidthBps` 2157897. The picture was the color bars and the label was Play at 1:00 / 1:00. The controls do not pick the rung.

## React Native

`apps/mobile` uses React Native 0.87.1 and follows the [Fabric native components](https://reactnative.dev/docs/0.87/fabric-native-components-introduction) guide ([Android](https://reactnative.dev/docs/0.87/fabric-native-components-android), [iOS](https://reactnative.dev/docs/0.87/fabric-native-components-ios)). The spec is `PlaypathPlayerViewNativeComponent.ts`. Commands are `play`, `pause`, and `seek`. Events across the bridge are the [playback event](playback-events.md) JSON, with `platform` `react-native` and engine `media3` or `avplayer`.

On Android the view builds Media3 1.11.1, opens Clear Key at `http://127.0.0.1:8082/`, and loads `http://127.0.0.1:8080/manifest.mpd`. The content key is not a prop. `./gradlew :app:compileDebugKotlin` and `PlaybackEventsTest` pass. On iOS the view creates `AVPlayer` and loads `http://127.0.0.1:8084/master.m3u8`. That play does not log `drm`. CocoaPods 1.15.2 on Homebrew Ruby 4.0.7 built the app. The system Ruby 2.6.10 still stops while compiling the `json` gem. JavaScript does not decode samples. On the emulator the TypeScript controls show Pause and 0:04 / 1:00, and the Media3 view shows the color bars. That session logs `startup` for `http://127.0.0.1:8080/manifest.mpd`, `drm` with `result` `ok`, and `bitrate` with `height` 1080 and `bandwidthBps` 4545011. `platform` is `react-native` and `engine` is `media3`. On the simulator the TypeScript controls show Play and 0:00 / 1:00, and the `AVPlayer` view shows the color bars. The mid-roll is not wired on this view, and the impression URL is not requested.

## Receiver page

A Cast or smart-TV web runtime is JavaScript. The PoC page is `http://127.0.0.1:5173/receiver.html`. It creates a media element and loads `http://127.0.0.1:8080/manifest.mpd` with Shaka, using the same Clear Key license URL as the web session. Opening that page in a desktop browser shows the color bars. Shaka requests the manifest and posts to the license service. The content key is not in the page. Certification, CAF receiver registration, and Tizen or webOS packages are [beyond the PoC](beyond-poc.md).

## Choosing an engine

| Question | Choice |
|---|---|
| Is the media encrypted on the web? | Shaka |
| Is it clear HLS on a browser that cannot play HLS? | hls.js |
| Is it clear HLS on Safari? | The media element |
| Is the app Android? | Media3, DASH |
| Is the app iOS? | `AVPlayer`, HLS |
| Is the app React Native? | The native engine for that OS |
