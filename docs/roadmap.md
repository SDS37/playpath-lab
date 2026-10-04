# Roadmap

The PoC is built in the order the film is built. Later milestones may start once their input exists. A milestone is done when its [technical requirements](technical-requirements.md) have an observation, not when the code compiles.

**Today:** M0 is done. `./pipeline/master.sh` writes the mezzanine. `./pipeline/hls.sh` and `./pipeline/dash.sh` write the CMAF ladder and both menus. `./pipeline/timelines.sh` fails if those menus diverge. The services and the apps are not built.

| Milestone | Status | Phase | Goal | Requirements | Checkpoint |
|---|---|---|---|---|---|
| [M0](https://github.com/SDS37/playpath-lab/issues/1) | Done | — | Requirements, architecture, standards, event contract | This folder | A colleague can read the path without asking which engine owns DRM |
| [M1](https://github.com/SDS37/playpath-lab/issues/2) | Planned | 1 | Generated mezzanine and captions | TR-1.1–TR-1.3 | Master directory has no playlist |
| [M2](https://github.com/SDS37/playpath-lab/issues/3) | Planned | 2 | CMAF ladder, HLS menu, DASH menu | TR-2.1–TR-2.5 | Both menus describe one timeline and two rungs |
| [M3](https://github.com/SDS37/playpath-lab/issues/4) | Planned | 3 | One CENC encryption and a Clear Key config | TR-3.1–TR-3.5 | A clear player cannot decode the protected segments |
| [M4](https://github.com/SDS37/playpath-lab/issues/5) | Planned | 4 | Two HTTP origins | TR-4.1–TR-4.5 | The same URL path works on ports 8080 and 8081 |
| [M5](https://github.com/SDS37/playpath-lab/issues/6) | Planned | 5 | SSAI pre-roll, VAST mid-roll, clean fallback | TR-5.1–TR-5.6 | Stitcher failure still plays the film |
| [M6](https://github.com/SDS37/playpath-lab/issues/7) | Planned | 6 and 7 | Shaka, hls.js, Media3, AVPlayer, license service | TR-6.1–TR-6.5, TR-7.1–TR-7.5 | Web and Android play encrypted DASH. iOS plays clear HLS. hls.js plays clear HLS |
| [M7](https://github.com/SDS37/playpath-lab/issues/8) | Planned | 8 | ABR and stall events | TR-8.1–TR-8.4 | A constrained network changes rung |
| [M8](https://github.com/SDS37/playpath-lab/issues/9) | Planned | 9 | Controls on web, Android, and iOS | TR-9.1–TR-9.6 | Pause, play, and seek match the engine |
| [M9](https://github.com/SDS37/playpath-lab/issues/10) | Planned | 10 | One JSON schema emitted by all three apps | TR-10.1–TR-10.4 | A validator accepts all three samples |
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
