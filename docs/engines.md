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

The page installs the polyfills Shaka requires, constructs `shaka.Player` on a media element, attaches an error listener, then `load`s a manifest URI. Clear Key is a DRM server entry for `org.w3.clearkey` pointing at `services/license`. The application reads `error` and adaptation events and maps them into [playback events](playback-events.md). It does not read key material out of the EME session.

Shaka is the web player whenever the title is encrypted, whether the menu is DASH or HLS.

## hls.js

Primary source: the project [README](https://github.com/video-dev/hls.js/).

Use it only when `Hls.isSupported()` is true and the menu is clear HLS. The supported sequence is: construct `Hls`, `loadSource` the master playlist, `attachMedia` the element. Destroy the instance when the screen goes away. On Safari, skip hls.js when `canPlayType` says the element can play HLS.

hls.js covers a real gap: Chromium and Firefox do not play HLS by themselves. It is a weak place to hang DRM. The protected package does not go through this object.

## Media3 ExoPlayer

Primary sources: [Get started](https://developer.android.com/media/media3/exoplayer) and [DRM](https://developer.android.com/media/media3/exoplayer/drm).

Kotlin builds an `ExoPlayer` with `ExoPlayer.Builder`, sets a `MediaItem` whose URI is the DASH manifest, and prepares. Clear Key uses Media3’s DRM session manager and the license URL. A listener (`Player.Listener`) is the source of playing, stalled, and track changes. Release the player in the Compose `DisposableEffect` or the `ViewModel`’s `onCleared`.

Media3 still contains Java. The app code that configures it is Kotlin. See [standards/dependencies.md](standards/dependencies.md).

The Compose screen draws our controls. A stock `PlayerView` control bar is not the product UI. A surface view may still display frames.

## AVPlayer

Primary sources: [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) and [HTTP Live Streaming](https://developer.apple.com/documentation/http-live-streaming).

Swift creates an `AVPlayer` with the HLS URL, observes `timeControlStatus`, and uses the item’s access log when a variant change needs to be reported. Play, pause, and seek are calls on the player. The view layer or player view controller’s view shows frames. Transport controls are UIKit views we own.

FairPlay, when a certificate exists, is an `AVContentKeySession` attached to the asset, as [FairPlay Streaming](https://developer.apple.com/streaming/fps/) describes. Until then the iOS happy path is clear HLS, and the session type keeps a single place where that key session will be created.

## React Native

The TypeScript screen follows React Native’s [Fabric native components](https://reactnative.dev/docs/fabric-native-components-introduction) guide ([Android](https://reactnative.dev/docs/fabric-native-components-android), [iOS](https://reactnative.dev/docs/fabric-native-components-ios)). The native view creates the Media3 or `AVPlayer` instance. JavaScript receives the same intent and event names as the other apps. It does not bundle a second decoder.

## Receiver page

A Cast or smart-TV web runtime is JavaScript. The PoC page is a document that can be opened in a desktop browser and that loads the manifest with Shaka. Certification, CAF receiver registration, and Tizen or webOS packages are [beyond the PoC](beyond-poc.md).

## Choosing an engine

| Question | Choice |
|---|---|
| Is the media encrypted on the web? | Shaka |
| Is it clear HLS on a browser that cannot play HLS? | hls.js |
| Is it clear HLS on Safari? | The media element |
| Is the app Android? | Media3, DASH |
| Is the app iOS? | `AVPlayer`, HLS |
| Is the app React Native? | The native engine for that OS |
