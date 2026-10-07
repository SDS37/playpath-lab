# Roadmap

The PoC is built in the order the film is built. Later milestones may start once their input exists. A milestone is done when its [technical requirements](technical-requirements.md) have an observation, not when the code compiles.

**Today:** M0 is done. `./pipeline/master.sh` writes the mezzanine. `./pipeline/hls.sh` and `./pipeline/dash.sh` write the CMAF ladder and both menus. `./pipeline/timelines.sh` fails if those menus diverge. `./pipeline/encrypt.sh` writes a CENC copy and the menus name the lab key id. `go run ./services/origin` serves that copy on `http://127.0.0.1:8080`, and the same command on `127.0.0.1:8081` is origin B. `services/origin/session.json` names the backup base URL. The web session and the Android session continue from origin B when origin A returns 503 for a media segment. On Chrome the label reached 0:25. On the emulator it reached 0:50. M4 is done. `./pipeline/preroll.sh` writes a clear pre-roll, and `go run ./services/ads` stitches it in front of the film on `http://127.0.0.1:8083`. The same service serves a VAST mid-roll whose cue is 10 seconds into the film. The clean menus stay on origin A. `services/ads/session.json` names that clean menu when the stitched URL fails. On Chrome, Stitched shows the green pre-roll and then the color bars, and the session logs both impressions. With the ads service stopped, Stitched on Chrome reaches 0:16 / 1:00 of color bars, and on the emulator the label is 0:05 / 1:00. Both startup events name the clean manifest on origin A. The impression URL is not requested. M5 is done. On the web, on Android, and on iOS, the VAST creative plays at 10 seconds and the film returns to that second. `go run ./services/license` answers Clear Key on `http://127.0.0.1:8082` for the lab key id. An unknown key id is a non-success status. `apps/web` plays either protected menu with Shaka on `http://127.0.0.1:5173` after that response. Play, pause, and seek go through the session. Clear HLS plays through hls.js from `http://127.0.0.1:8084/master.m3u8`. On Safari 26.6.2 the clear menu plays on the media element: the picture is the color bars, and that play does not call the license service. `apps/android` plays encrypted DASH with Media3: the license log shows `POST / 200` and the lab key id, and the Compose screen shows the picture. A wrong key id is `POST / 403`, a black picture, and a `drm` event with `result: "error"`. `apps/ios` plays clear HLS with `AVPlayer`: the simulator shows the picture, and the license log has no request from that play. FairPlay is not reported as passing. Stopping the license service, then playing encrypted DASH, is a black picture and a `drm` error. Back from the Android Compose screen releases that ExoPlayer instance. On Chrome, restricting throughput after hls.js has selected 1080p moves clear HLS to 720p, and the session logs that `bitrate` event. M6 is done: its listed engine and license plays each have an observation. React Native on Android shows the color bars. On the simulator the `AVPlayer` view shows the color bars. A replaced WebVTT, rebuilt through the pipeline, showed Rebuilt cue alpha on Android and iOS and Rebuilt cue at ten on the web (TR-1.3). On Chrome, protected DASH showed Pause and the color bars at 0:10 / 1:00, and the control reached 1:00 / 1:00. That origin log is `manifest.mpd`, `subtitles/playpath-bars.vtt`, init `.mp4` files, and `.m4s` segments. The license log is `POST / 200`. On the emulator the label was 0:28 / 1:00 with Pause, and the picture was the color bars. That origin log is `manifest.mpd`, the same subtitle file, init `.mp4` files, and `.m4s` segments. The license log is `POST / 200`. On the simulator the label was 0:11 / 1:00 with Pause, and the picture was the color bars. That origin log is `master.m3u8`, media playlists, init `.mp4` files, `.m4s` segments, and `subtitles/playpath-bars.vtt`. The license log has no request from that play. `playpath-bars.mp4` is not in any of those logs (TR-1.2). M1 is done. The web, Android, and iOS sessions select the English audio rendition and the English text track from the menus (TR-2.4). M2 is done. M3 is done: a player with no key stays on a black picture and does not take the clear package. M7 stays planned until the Android and iOS step down is observed. M8 is done: the web bar draws play, pause, seek, time, and Buffering, and the Android and iOS bars draw play, pause, seek, and time. The React Native bar uses `StyleSheet` and `apps/mobile` has no CSS file. On the web, on Android, and on iOS, the mid-roll disables seek and the film returns to the cue. M9 is done: `packages/playback-events` holds the version 1 JSON Schema. It accepts a web startup, an Android drm error, and an iOS bitrate, and it rejects a startup that renames `startupMs`. The web, Android, and iOS sessions log `startup` and `ad` with the same field names. An encrypted play logs `drm`. A rung change logs `bitrate`. A schema check accepts those samples. The impression URL is not requested. On Chrome, one protected DASH session included `startup`, `drm` with `result` `ok`, a mid-roll `ad`, and a `bitrate` change from `height` 720 and `bandwidthBps` 2164878 to `height` 1080 and `bandwidthBps` 4677870. The picture was the color bars at 0:23 / 1:00. On the emulator, one DASH session included `startup`, `drm` with `result` `ok`, that mid-roll `ad`, and `bitrate` with `height` 1080 and `bandwidthBps` 4545011. The label was 0:21 / 1:00. On the simulator, one clear HLS session included `startup`, `bitrate` with `height` 720 and `bandwidthBps` 2157897, and that mid-roll `ad`, and it did not log `drm`. The label was 0:24 / 1:00. M10 is started: `apps/mobile` renders the TypeScript controls and hosts a Fabric view. That view is Media3 on Android and `AVPlayer` on iOS. The Android project compiles. CocoaPods 1.15.2 on Homebrew Ruby 4.0.7 built the iOS app. JavaScript does not decode samples. On the emulator the TypeScript controls show Pause and 0:04 / 1:00, and the Media3 view shows the color bars. That session logs `startup` for `http://127.0.0.1:8080/manifest.mpd`, `drm` with `result` `ok`, and `bitrate` with `height` 1080 and `bandwidthBps` 4545011. On the simulator the TypeScript controls show Play and 0:00 / 1:00, and the `AVPlayer` view shows the color bars. `http://127.0.0.1:5173/receiver.html` loads `http://127.0.0.1:8080/manifest.mpd` with Shaka, and opening it shows the color bars. Chromecast, Tizen, and webOS certification stay out of scope. M10 stays planned.

| Milestone | Status | Phase | Goal | Requirements | Checkpoint |
|---|---|---|---|---|---|
| [M0](https://github.com/SDS37/playpath-lab/issues/1) | Done | — | Requirements, architecture, standards, event contract | This folder | A colleague can read the path without asking which engine owns DRM |
| [M1](https://github.com/SDS37/playpath-lab/issues/2) | Done | 1 | Generated mezzanine and captions | TR-1.1–TR-1.3 | Master directory has no playlist |
| [M2](https://github.com/SDS37/playpath-lab/issues/3) | Done | 2 | CMAF ladder, HLS menu, DASH menu | TR-2.1–TR-2.5 | Both menus describe one timeline and two rungs |
| [M3](https://github.com/SDS37/playpath-lab/issues/4) | Done | 3 | One CENC encryption and a Clear Key config | TR-3.1–TR-3.5 | A clear player cannot decode the protected segments |
| [M4](https://github.com/SDS37/playpath-lab/issues/5) | Done | 4 | Two HTTP origins | TR-4.1–TR-4.5 | The same URL path works on ports 8080 and 8081 |
| [M5](https://github.com/SDS37/playpath-lab/issues/6) | Done | 5 | SSAI pre-roll, VAST mid-roll, clean fallback | TR-5.1–TR-5.6 | Stitcher failure still plays the film |
| [M6](https://github.com/SDS37/playpath-lab/issues/7) | Done | 6 and 7 | Shaka, hls.js, Media3, AVPlayer, license service | TR-6.1–TR-6.5, TR-7.1–TR-7.5 | Web and Android play encrypted DASH. iOS plays clear HLS. hls.js plays clear HLS |
| [M7](https://github.com/SDS37/playpath-lab/issues/8) | Planned | 8 | ABR and stall events | TR-8.1–TR-8.4 | A constrained network changes rung |
| [M8](https://github.com/SDS37/playpath-lab/issues/9) | Done | 9 | Controls on web, Android, and iOS | TR-9.1–TR-9.6 | Pause, play, and seek match the engine |
| [M9](https://github.com/SDS37/playpath-lab/issues/10) | Done | 10 | One JSON schema emitted by all three apps | TR-10.1–TR-10.4 | A validator accepts all three samples |
| [M10](https://github.com/SDS37/playpath-lab/issues/11) | Planned | 6 | React Native over the native engines, and a browser-loadable receiver page | TR-6.6 and the “if available” lines in [DoD.md](DoD.md) | TypeScript UI, native decode. Record a blocker if a toolchain is missing |

## Stories inside the milestones

Use these ids in commits and in the app READMEs when the work starts.

| Id | Milestone | Work |
|---|---|---|
| [PP-010](https://github.com/SDS37/playpath-lab/issues/12) | M1 | Generate `playpath-bars` video, audio, and WebVTT |
| [PP-020](https://github.com/SDS37/playpath-lab/issues/13) | M2 | Package HLS |
| [PP-021](https://github.com/SDS37/playpath-lab/issues/14) | M2 | Package DASH from the same CMAF media |
| [PP-022](https://github.com/SDS37/playpath-lab/issues/15) | M2 | Assert the timelines match |
| [PP-030](https://github.com/SDS37/playpath-lab/issues/16) | M3 | Encrypt with CENC and record the key id |
| [PP-040](https://github.com/SDS37/playpath-lab/issues/17) | M4 | Origin A |
| [PP-041](https://github.com/SDS37/playpath-lab/issues/18) | M4 | Origin B and backup base URL |
| [PP-050](https://github.com/SDS37/playpath-lab/issues/19) | M5 | SSAI stitcher |
| [PP-051](https://github.com/SDS37/playpath-lab/issues/20) | M5 | VAST mid-roll document |
| [PP-052](https://github.com/SDS37/playpath-lab/issues/21) | M5 | Fallback to the clean menu |
| [PP-060](https://github.com/SDS37/playpath-lab/issues/22) | M6 | Web Shaka, protected DASH and HLS |
| [PP-061](https://github.com/SDS37/playpath-lab/issues/23) | M6 | Web hls.js, clear HLS |
| [PP-062](https://github.com/SDS37/playpath-lab/issues/24) | M6 | Android Media3 |
| [PP-063](https://github.com/SDS37/playpath-lab/issues/25) | M6 | iOS AVPlayer, clear HLS, FairPlay boundary written down |
| [PP-070](https://github.com/SDS37/playpath-lab/issues/26) | M6 | Clear Key license service |
| [PP-071](https://github.com/SDS37/playpath-lab/issues/27) | M6 | Media3 Clear Key session |
| [PP-080](https://github.com/SDS37/playpath-lab/issues/28) | M7 | Map ABR and stall to session state |
| [PP-090](https://github.com/SDS37/playpath-lab/issues/29) | M8 | Web controls |
| [PP-091](https://github.com/SDS37/playpath-lab/issues/30) | M8 | Compose controls |
| [PP-092](https://github.com/SDS37/playpath-lab/issues/31) | M8 | UIKit controls |
| [PP-100](https://github.com/SDS37/playpath-lab/issues/32) | M9 | Event schema and fixtures |
| [PP-101](https://github.com/SDS37/playpath-lab/issues/33) | M9 | Emit the schema from each app |
| [PP-110](https://github.com/SDS37/playpath-lab/issues/34) | M10 | React Native native player view |
| [PP-111](https://github.com/SDS37/playpath-lab/issues/35) | M10 | Receiver page that loads in a desktop browser |

## Checkpoint questions

At the end of every milestone, answer:

1. What can a colleague watch right now?
2. Which technical requirement has no observation yet?
3. Did a failure mode (license, stitcher, origin) get proved, or only the sunny path?
4. Does any UI code now select a bitrate, parse a playlist, or touch a key?

## Time-control rules

- The floor is web (Shaka and hls.js), Android (Media3), and iOS (`AVPlayer`). M10 waits for them.
- If React Native has no build environment, ship M6–M9 and write the blocker in the README. Do not reimplement a player in JavaScript to finish M10.
- If Shaka Packager is unavailable, ffmpeg may produce the CMAF ladder, as TR-2.5 allows. The menus still have to match.
- If a FairPlay certificate appears, add it as a beyond-PoC slice. Do not block M6 on it.
- Do not add accounts, a catalogue, live, or a second title.

After the [Definition of Done](DoD.md), production follow-ups live in [beyond-poc.md](beyond-poc.md).
