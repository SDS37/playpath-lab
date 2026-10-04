# Definition of Done

The PoC is done when a colleague can run the [happy path](happy-path.md) and every box below is true. Boxes stay open until the software exists. Documentation alone does not check them.

## Must

- [ ] `playpath-bars` exists only as a generated mezzanine with video, audio, and captions (phase 1)
- [ ] One CMAF ladder produces an HLS master playlist and a DASH manifest for the same timeline, with at least two video rungs (phase 2)
- [ ] Those segments are encrypted once with MPEG-CENC, and a Clear Key license answers the player (phases 3 and 7)
- [ ] The UI never logs, stores, or renders the content key (phase 7)
- [ ] A missing or rejected license leaves the picture black (phase 7)
- [ ] An HTTP origin serves the menus and segments, and a failed segment is retried (phase 4)
- [ ] A second local origin can serve the same bytes if the first origin refuses the request (phase 4)
- [ ] SSAI returns one menu that includes a pre-roll. If the stitcher fails, the clean film plays (phase 5)
- [ ] CSAI plays a VAST mid-roll and returns to the cued second of the film (phases 5 and 8)
- [ ] The web app plays encrypted DASH with Shaka, and clear HLS with hls.js (phase 6)
- [ ] Android plays the title with Media3, configured from Kotlin, with Compose controls (phase 6)
- [ ] iOS plays HLS with AVPlayer, with UIKit controls (phase 6)
- [ ] A forced bandwidth drop changes rendition, and the app reports it (phase 8)
- [ ] A stall is reported by the engine. The control layout is unchanged by that fix (phase 8)
- [ ] Play, pause, and seek on web, Android, and iOS match engine state (phase 9)
- [ ] Kotlin, Swift, and TypeScript emit [playback events](playback-events.md) with the same field names (phase 10)
- [ ] The root README is a runbook that starts the pipeline, the three services, and the three apps

## If the toolchain is available

These are part of the full claim (“every technology the path names, where a local run can reach it”). If one is blocked, record the blocker in the README and keep the Must list.

- [ ] React Native plays the title by calling the native engine (phase 6, [ADR-009](architecture-decision-records.md))
- [ ] Safari plays the HLS menu with the platform player (phase 6)
- [ ] A Cast or TV receiver page loads the same manifest in a desktop browser (phase 6)

## Not in this DoD

FairPlay Streaming certificates, Widevine and PlayReady license servers, a commercial CDN, live, downloads, and device certification: [beyond-poc.md](beyond-poc.md).
