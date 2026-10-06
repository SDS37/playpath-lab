# PlayPath documentation

The lab proves one happy path: a single title goes from a master file to a picture on screen, through packaging, encryption, delivery, ads, and a different playback engine on each device.

Read in this order if you are new. Dip in by phase if you are implementing one.

| Document | What it decides |
|---|---|
| [Business requirements](business-requirements.md) | Who the lab is for, and what “play” means |
| [Technical requirements](technical-requirements.md) | The proof each phase must produce |
| [Happy path](happy-path.md) | The demo, in order, from press-play back to the master |
| [Architecture](architecture.md) | Phases, engines, languages, and failure rules |
| [Engines](engines.md) | Which player runs on which device, and why |
| [Roadmap](roadmap.md) | The order we build the proof |
| [Definition of Done](DoD.md) | When the proof is complete |
| [Beyond the PoC](beyond-poc.md) | Production DRM, real CDNs, live, downloads |
| [Architecture decision records](architecture-decision-records.md) | Choices already made |
| [Playback events](playback-events.md) | The one JSON shape every app emits |
| [Controls and UX](ux-controls.md) | Phase 9: controls that match engine state |
| [Commits](commits.md) | Commit messages |

## Code standards

Each file takes its rules from that technology’s official documentation. Repo rules under those sources exist only to keep the player boundary intact.

| Standard | Applies to | Primary source |
|---|---|---|
| [TypeScript](standards/typescript.md) | `apps/web`, `apps/mobile`, `packages/playback-events` | TypeScript handbook and compiler guidelines |
| [JavaScript](standards/javascript.md) | Runtime, Shaka, hls.js, TV and Cast receivers | MDN and ECMA-262 |
| [React](standards/react.md) | `apps/web` | react.dev |
| [React Native](standards/react-native.md) | `apps/mobile` | reactnative.dev, plus the Rules of React |
| [CSS](standards/css.md) | Web control bar | MDN CSS |
| [Kotlin](standards/kotlin.md) | `apps/android` | kotlinlang.org and Android developer docs |
| [Swift](standards/swift.md) | `apps/ios` | Swift.org API Design Guidelines and Apple docs |
| [Go](standards/go.md) | `services/origin`, `services/license`, `services/ads` | go.dev Effective Go |
| [Dependencies we do not author](standards/dependencies.md) | Packager, decoders, CDM, Media3 Java, Objective-C under AVFoundation | Vendor docs |

## Status

Documentation for the PoC is in this folder. The pipeline writes the mezzanine, both menus, and a CENC protected copy. Origin A serves that copy on `http://127.0.0.1:8080` and origin B serves it on `http://127.0.0.1:8081`. The ads service stitches a pre-roll in front of the film on `http://127.0.0.1:8083`, serves a VAST mid-roll, and records the clean menu for a failed stitched URL. The license service answers Clear Key on `http://127.0.0.1:8082`. `apps/web` plays the protected menus with Shaka, and clear HLS with hls.js, on `http://127.0.0.1:5173`. On Safari 26.6.2 the clear menu plays on the media element: the picture is the color bars, and that play does not call the license service. `apps/android` plays encrypted DASH with Media3. A wrong key id stays black and logs a `drm` error. Stopping the license service, then playing encrypted DASH, is the same black picture and `drm` error. `apps/ios` plays clear HLS with `AVPlayer` and does not report FairPlay as passing. On Chrome, restricting throughput after hls.js has selected 1080p moves clear HLS to 720p, and the session logs that `bitrate` event. React Native is M10 and is not built yet. M6 is done. M1 stays planned until a rebuilt caption file is shown on every player. M2 stays planned until a player selects the text track. M3 is done. M7 stays planned. M8 is started: the web bar draws play, pause, seek, time, and Buffering, and the Android and iOS bars draw play, pause, seek, and time. M8 stays planned until React Native styles have an observation. On the web, on Android, and on iOS, the mid-roll disables seek and the film returns to the cue. The shared package for M9 is not started. M10 is not started.
