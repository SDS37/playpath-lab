# Technical requirements

**Product:** PlayPath Lab
**Version:** PoC
**Last updated:** 2026-10-04
**Status:** The contract for the proof. Each item names the phase, the technology, and the observation that shows the happy path.

Business intent is in [business-requirements.md](business-requirements.md). The demo script is [happy-path.md](happy-path.md). Decisions that constrain this list are the [ADRs](architecture-decision-records.md).

A requirement is met only when the observation can be repeated from the repository. A diagram is not the observation.

## Fixture

| Item | Value |
|---|---|
| Title id | `playpath-bars` |
| Programme | Generated mezzanine, about 60 seconds. Video, stereo audio, one WebVTT caption file |
| Video codec | H.264, progressive, closed GOP so segment boundaries are random-access points |
| Audio codec | AAC-LC |
| Ladder | At least two video rungs of the same duration, plus the audio rendition and the caption track |
| Segment duration | 6 seconds, recorded in [`pipeline/timeline`](../pipeline/timeline). [HLS Authoring Specification for Apple Devices](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices) items 7.5 and 7.6. DASH uses this same duration |
| Encryption | One MPEG-CENC pass. Lab key system `org.w3.clearkey`. Key bytes in [`services/license/lab-key.json`](../services/license/lab-key.json), a published lab test key |
| Ad pre-roll | About 5 seconds, stitched by the SSAI service |
| Ad mid-roll | Cue at 10 seconds, VAST linear creative, played by the client |

The mezzanine is an input. It is not an `.m3u8` or an `.mpd`. What “mezzanine” and “sidecar” mean is in [Phase 1 of the architecture](architecture.md#phase-1--master).

## Phase 1 — Master

| ID | Requirement | Observation |
|---|---|---|
| TR-1.1 | The pipeline accepts one high-quality file and a caption file, and no playlist | The master directory contains the mezzanine and the VTT, and no segment or manifest |
| TR-1.2 | Apps and services never transcode the master at play time | Play requests fetch manifests and segments only |
| TR-1.3 | Replacing the caption file and re-running the pipeline changes captions on every player | Web, Android, and iOS show the new cues after a rebuild |

## Phase 2 — Package

| ID | Requirement | Observation |
|---|---|---|
| TR-2.1 | One encode ladder is stored as CMAF fragmented MP4 | Segments are fMP4, shared by both menus |
| TR-2.2 | The HLS menu is a master playlist that lists every rung | The master `.m3u8` includes `BANDWIDTH`, `RESOLUTION`, and `CODECS` for each video variant, per Apple’s HLS authoring specification |
| TR-2.3 | The DASH menu is an MPD that lists the same rungs and the same timeline | Period duration and segment times line up with the HLS media playlists |
| TR-2.4 | Audio and captions are addressable from both menus | A player can select the audio rendition and the text track without a second encode |
| TR-2.5 | Packaging is done by Shaka Packager (C++) or ffmpeg. Application code does not slice the file | The pipeline is a script or a Go command that shells out to the packager. Kotlin, Swift, and TypeScript do not link the packager |

Primary sources: [HLS](https://developer.apple.com/documentation/http-live-streaming), [HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices), [DASH-IF guidelines](https://dashif.org/guidelines/), [Shaka Packager](https://github.com/shaka-project/shaka-packager).

## Phase 3 — Encrypt

| ID | Requirement | Observation |
|---|---|---|
| TR-3.1 | Delivery segments for the protected package are encrypted with MPEG Common Encryption | A segment’s sample data is not playable as clear media in a player that has no key |
| TR-3.2 | The menus name the key id that belongs to those segments | The player can form a license request without a person typing a key |
| TR-3.3 | The lab key system is Clear Key (`org.w3.clearkey`), as defined by Encrypted Media Extensions | Shaka on the web, and Media3 on Android, request that key system |
| TR-3.4 | The content key lives in the license service configuration, not in the apps | App repositories contain no key bytes. The license service reads them from local config that is documented as a lab key |
| TR-3.5 | FairPlay, Widevine, and PlayReady are named in the engine configuration map and are not reported as passing | The README states they need vendor credentials. See [beyond-poc.md](beyond-poc.md) |

Primary sources: [W3C Encrypted Media Extensions](https://www.w3.org/TR/encrypted-media/) (Clear Key key system), ISO/IEC 23001-7 (CENC). Production systems: [FairPlay Streaming](https://developer.apple.com/streaming/fps/), Widevine, PlayReady.

## Phase 4 — CDN

| ID | Requirement | Observation |
|---|---|---|
| TR-4.1 | Menus and segments are fetched with ordinary HTTP GET | Any engine plays a URL. No app-specific socket protocol |
| TR-4.2 | The origin adds cache validators (`ETag` or `Last-Modified`) and correct content types for `.m3u8`, `.mpd`, and fMP4 | A browser or player request shows the matching `Content-Type` |
| TR-4.3 | A failed segment request is retried by the engine | Dropping one response does not restart the title from zero |
| TR-4.4 | The same tree is served on two local origins | Pointing the player at the second base URL plays the same title |
| TR-4.5 | The player can be configured with a backup base URL | When the first origin returns an error for a segment, playback continues from the second |

The PoC origin is a Go file server. It stands in for a CDN. It does not claim global scale. See [ADR-010](architecture-decision-records.md).

## Phase 5 — Ads

| ID | Requirement | Observation |
|---|---|---|
| TR-5.1 | The SSAI service returns an HLS playlist and a DASH MPD that include a pre-roll and then the film, on one timeline the player treats as a single stream | Play of the stitched URL shows the ad and then the film without a second `load` from the UI |
| TR-5.2 | If the SSAI service errors, the client requests the clean menu and plays the film | Stopping the stitcher still yields picture |
| TR-5.3 | The clean film menu stays available at a stable URL that SSAI does not own | The fallback URL plays with no ad period |
| TR-5.4 | A VAST document describes one linear mid-roll creative and an impression URL | The document validates as VAST and contains a media file the engine can play |
| TR-5.5 | At 10 seconds the engine pauses the film, plays the creative, then seeks to the cue | The film frame after the ad is the frame at the cue, not the start of the file |
| TR-5.6 | The app emits an ad impression for the SSAI pre-roll and for the CSAI mid-roll | Both appear in the playback event log |

Primary source: [IAB VAST](https://iabtechlab.com/standards/vast/). Server-side insertion gives the player one presentation: a DASH period or an HLS discontinuity sequence that already contains the ad.

## Phase 6 — App and engines

| ID | Requirement | Observation |
|---|---|---|
| TR-6.1 | The web app loads encrypted DASH and HLS through Shaka Player | Loading either protected menu reaches a playing state after a Clear Key response |
| TR-6.2 | The web app loads clear HLS through hls.js where `Hls.isSupported()` is true | Chrome or Firefox plays the clear HLS menu via Media Source Extensions |
| TR-6.3 | Safari plays clear HLS through the platform media element | The page does not attach hls.js when the element can play HLS |
| TR-6.4 | Android configures Media3 ExoPlayer from Kotlin and plays the DASH menu | Picture appears in a Compose screen |
| TR-6.5 | iOS configures `AVPlayer` from Swift and plays the HLS menu | Picture appears in a UIKit screen |
| TR-6.6 | React Native renders the TypeScript controls and plays through a native view backed by Media3 on Android and `AVPlayer` on iOS | The JavaScript layer does not decode samples |
| TR-6.7 | Each app depends on one engine interface in that process: load, play, pause, seek, and a subscription to engine events | UI code does not parse playlists to choose a rung |

Engine choice and the official setup for each one: [engines.md](engines.md).

## Phase 7 — License

| ID | Requirement | Observation |
|---|---|---|
| TR-7.1 | The license HTTP service returns a Clear Key response only to the engine’s license request | The web network log shows the license call coming from the EME path Shaka drives, and the CDM consumes the response |
| TR-7.2 | Media3 uses its DRM session API for the same Clear Key license URL | Android plays the encrypted package |
| TR-7.3 | A wrong key id, or a license service that is down, produces a DRM error and a black picture | The event log contains `drm` with `result: "error"`. The film does not fall back to clear segments |
| TR-7.4 | hls.js is not the DRM path | The protected title is not loaded through hls.js |
| TR-7.5 | iOS documents the `AVContentKeySession` boundary and plays clear HLS in this PoC | The iOS README states that FairPlay needs an FPS certificate and key server module |

## Phase 8 — Buffer, ABR, decode

| ID | Requirement | Observation |
|---|---|---|
| TR-8.1 | The engine, not the UI, selects the rendition | No Compose, UIKit, or React code assigns a bitrate except by setting engine ABR configuration |
| TR-8.2 | Restricting throughput moves playback to the lower rung | A bitrate event fires with the lower height or bandwidth |
| TR-8.3 | The app surfaces engine states `playing`, `paused`, `stalled`, and `ended` | The control model updates from those events |
| TR-8.4 | Decode stays inside the engine and the platform decoders | Application code does not ship a video decoder |

## Phase 9 — Controls

| ID | Requirement | Observation |
|---|---|---|
| TR-9.1 | Web controls are React components styled with CSS classes | TypeScript does not set layout colors inline for the theme |
| TR-9.2 | Android controls are Compose. The theme defines color, type, and spacing | The default Media3 control bar is not the product UI |
| TR-9.3 | iOS controls are UIKit views. Colors, fonts, and layout are set on those views | The system transport bar is not the product UI |
| TR-9.4 | React Native controls use a `StyleSheet` | There is no CSS file in the mobile app |
| TR-9.5 | The pause control is shown only while the engine reports a playing state, and the play control only while it reports paused | Toggling the engine updates the label |
| TR-9.6 | Seek is disabled for the duration of a CSAI ad | Dragging the bar during the mid-roll does not move the film |

Details: [ux-controls.md](ux-controls.md).

## Phase 10 — Monitor

| ID | Requirement | Observation |
|---|---|---|
| TR-10.1 | Every app posts the JSON document defined in [playback-events.md](playback-events.md) | A schema check accepts a sample from TypeScript, Kotlin, and Swift |
| TR-10.2 | The document includes startup, stall, bitrate, ad, and DRM fields when those things happen | One session of the happy path produces at least `startup` and `ad`, plus `drm` on an encrypted play, plus `bitrate` when the rung changes |
| TR-10.3 | Event names and units are identical across platforms | `startupMs` is milliseconds everywhere. Heights are pixels. Bandwidths are bits per second |
| TR-10.4 | Logs and events omit the content key, license response body, and any credential | Emitted events contain none of those bytes |

## Local ports

These are the planned development ports. They are reserved here so later READMEs do not invent a second map.

| Service | Address |
|---|---|
| Origin A | `http://127.0.0.1:8080` |
| Origin B | `http://127.0.0.1:8081` |
| License | `http://127.0.0.1:8082` |
| Ads (SSAI and VAST) | `http://127.0.0.1:8083` |
| Web app | `http://127.0.0.1:5173` |

## Languages and modules

| Path | Language | May do | Must not do |
|---|---|---|---|
| `pipeline/` | Shell or Go driving the packager | Build the mezzanine into menus | Run inside the app |
| `services/origin` | Go | Serve bytes | Choose a bitrate |
| `services/license` | Go | Answer a key request, or fail | Return clear media when the key is missing |
| `services/ads` | Go | Stitch a menu, or serve VAST | Decode video |
| `apps/web` | TypeScript, React, CSS | Shaka, hls.js, controls, events | Hold the content key |
| `apps/android` | Kotlin, Compose | Media3, controls, events | Package or encrypt |
| `apps/ios` | Swift, UIKit | AVPlayer, controls, events | Package or encrypt |
| `apps/mobile` | TypeScript, React Native | Controls and a native player view | Reimplement ExoPlayer or AVPlayer |
| `packages/playback-events` | TypeScript schema, plus the same schema for Kotlin and Swift | Validate the JSON | Play media |
