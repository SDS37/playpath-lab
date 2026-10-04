# Architecture decision records

Decisions for the PlayPath PoC. Each one is accepted. Change them by a new ADR that supersedes the old id, not by a silent edit.

| ID | Title | Status |
|---|---|---|
| 001 | One repository for the whole path | Accepted |
| 002 | One CMAF ladder and two menus | Accepted |
| 003 | Lab DRM is CENC plus Clear Key | Accepted |
| 004 | The session owns the engine | Accepted |
| 005 | Shaka for web DRM, hls.js for clear HLS | Accepted |
| 006 | One playback event schema | Accepted |
| 007 | A failed ad menu plays the clean film | Accepted |
| 008 | App languages stop at the engine | Accepted |
| 009 | React Native shares UI and calls the native engine | Accepted |
| 010 | Two local origins stand in for a second CDN | Accepted |
| 011 | The programme is generated | Accepted |

---

## ADR-001: One repository for the whole path

Date: 2026-10-04
Status: Accepted

### Context

The proof runs from a master file to playback. Splitting the packager, the license stub, and the apps across repositories would hide the path the lab exists to show.

### Decision

Keep pipeline, services, apps, the event schema, and docs in `playpath-lab`.

### Alternatives

- One repository per app
- A media repository and an app repository

### Consequences

- A reviewer can see which language owns which phase
- Local setup is one clone
- The repository will contain generated media notes, Go services, and three app toolchains
- Independent versioning of each app is weaker, which is acceptable for a lab

---

## ADR-002: One CMAF ladder and two menus

Date: 2026-10-04
Status: Accepted

### Context

Safari, iOS, and tvOS play HLS natively. Android, Chrome, and most TV stacks expect DASH. Encoding the film twice doubles the files that can be wrong. The devices disagree about the menu, not about fragmented MP4.

The subtitle of the architecture is “package once, encrypt once”.

### Decision

Encode one H.264/AAC ladder as CMAF fragmented MP4. Write an HLS master playlist and a DASH MPD that reference that media and the same timeline. Follow the [HLS Authoring Specification for Apple Devices](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices) and the [DASH-IF guidelines](https://dashif.org/guidelines/).

### Alternatives

- Two independent encodes, one TS-based HLS and one fMP4 DASH
- HLS only, and a JavaScript player on Android
- DASH only, and no native Apple player

### Consequences

- A bad caption or a bad rung is fixed once
- Both menus must be checked when the pipeline changes
- Apple devices still receive HLS. Android and Chrome can receive DASH
- The packager is C++ (Shaka Packager or ffmpeg). Apps do not grow a segmenter

---

## ADR-003: Lab DRM is CENC plus Clear Key

Date: 2026-10-04
Status: Accepted

### Context

Production playback uses three DRM systems because no single system is accepted on every device: FairPlay on Apple, Widevine on Chrome and Android, PlayReady on many TVs and on Edge. Each one needs a vendor license relationship. The encrypt step and the license step are still separate: files are locked in advance, and the key is requested per device at play time.

W3C Encrypted Media Extensions defines the Clear Key system `org.w3.clearkey` for this request shape. MPEG Common Encryption is the segment encryption Widevine and PlayReady use. Media3 and Shaka both speak Clear Key.

### Decision

Encrypt the PoC segments once with CENC. Serve a Clear Key license from `services/license`. Use that path on Shaka and on Media3.

Name FairPlay, Widevine, and PlayReady in the engine map. Do not claim they pass. iOS plays clear HLS. The iOS app documents `AVContentKeySession` as the production seam and does not invent a fake FairPlay success.

The content key stays in the license service configuration. Apps do not log license bodies.

### Alternatives

- Clear media only, and a written description of DRM
- A hosted Widevine test vendor from day one
- Stubbing all three production key systems with a shared “success” boolean

### Consequences

- The happy path includes a real encrypt step and a real key request
- A down license service can be shown to fail closed
- The PoC does not prove CDM security level, output protection, or offline licenses
- Adding a production key system later replaces the license URL and the key-system id. It does not move decryption into Kotlin, Swift, or TypeScript

---

## ADR-004: The session owns the engine

Date: 2026-10-04
Status: Accepted

### Context

Each official player is a long-lived object the application configures and then listens to. Compose, UIKit, and React render snapshots. If a control imports the engine, phase 9 and phase 8 collapse into each other, and a layout change can break license calls.

### Decision

Each app has a playback session as the only type that calls load, play, pause, and seek, and the only type that subscribes to engine events. Controls receive view state and send intents. The session emits [playback events](playback-events.md).

On the web the player instance lives in a ref or an equivalent holder outside render state. On Android it is released when the screen leaves composition. On iOS it is owned by the controller, not by a SwiftUI experiment in this PoC (the UI is UIKit, matching the platform map).

### Alternatives

- Call Shaka, Media3, or `AVPlayer` from button handlers
- Store the engine object in React state or in a Compose snapshot

### Consequences

- The same intent names exist on every platform
- Engine upgrades touch the session
- A pause icon that lies is a session bug when an event was dropped, and a control bug when the event arrived and the widget ignored it

---

## ADR-005: Shaka for web DRM, hls.js for clear HLS

Date: 2026-10-04
Status: Accepted

### Context

Shaka Player plays DASH and HLS and integrates with EME for Widevine, PlayReady, and FairPlay on Safari. hls.js exists because Chrome and Firefox do not play HLS natively: it transmuxes segments into Media Source Extensions. DRM and DASH are outside its job. Safari plays HLS without hls.js.

### Decision

- Protected DASH and protected HLS on the web go through Shaka.
- Clear HLS on browsers that need a polyfill goes through hls.js.
- Safari uses the native media element for clear HLS.
- The protected title is never loaded with hls.js.

### Alternatives

- hls.js for every web playback
- Shaka for clear HLS as well, and no hls.js proof
- A single in-house MSE player

### Consequences

- The lab demonstrates both web engines the architecture names
- Two web entry points must be tested
- ABR behaviour will differ between them, which is why both emit the same event schema

---

## ADR-006: One playback event schema

Date: 2026-10-04
Status: Accepted

### Context

The four engines fail differently. If Android logs “rebuffer” and the web logs “waiting”, an operator cannot tell a stall from a license error, and a team will restyle the control bar.

### Decision

Adopt the schema in [playback-events.md](playback-events.md). Kotlin, Swift, and TypeScript emit those field names and units. Platform-specific diagnostics may be added only under `extra`, as strings that contain no secrets.

### Alternatives

- Each app logs in its engine’s native event names
- A third-party analytics SDK as the contract

### Consequences

- Mappers exist in every session
- A schema test can reject a drifted payload
- The lab does not depend on a vendor dashboard to be “monitored”

---

## ADR-007: A failed ad menu plays the clean film

Date: 2026-10-04
Status: Accepted

### Context

SSAI gives every viewer a menu the stitcher just wrote. If that service is slow or down, failing the playback punishes the viewer for an ad. CSAI can fail at the seam: wrong resume time, a double request, a black frame. The film URL must remain independently playable.

### Decision

Keep a stable clean manifest that the stitcher does not own. If the stitched URL fails, the session loads the clean URL. CSAI seeks to the advertised cue after the creative ends. Seek is disabled while the creative is playing.

### Alternatives

- Fail playback when the stitcher fails
- Let the client invent an ad break with no VAST document

### Consequences

- The demo includes a down stitcher
- Tracking impressions are best-effort and must not block the fallback
- Personalisation is a query on the stitcher, not a rewrite inside the player

---

## ADR-008: App languages stop at the engine

Date: 2026-10-04
Status: Accepted

### Context

Kotlin, Swift, TypeScript, and JavaScript own the apps. Packaging, the CDM, decoders, and the segment host are other runtimes. Putting that work in an app “so there is one language” fights every platform.

### Decision

Application code configures engines and draws controls. It does not implement a packager, a CDM, a video decoder, or a CDN. Go owns origin, license, and the ad menu. C++ tools own packaging. Standards for languages we do not author are out of scope: [standards/dependencies.md](standards/dependencies.md).

### Alternatives

- A TypeScript segmenter in the web app
- Decrypting samples in Kotlin or Swift and rendering with a custom decoder

### Consequences

- Contributors need the engine docs, not a homemade media stack
- A bug in encryption is fixed in the pipeline even when the symptom is a black screen in Compose

---

## ADR-009: React Native shares UI and calls the native engine

Date: 2026-10-04
Status: Accepted

### Context

React Native can share a TypeScript control layer. It cannot share the decoder. Android still needs Media3. iOS still needs `AVPlayer`. A JavaScript player inside React Native would be a fifth engine with none of the platform DRM hooks.

### Decision

`apps/mobile` renders controls in React Native and hosts a native view. That view is Media3 on Android and `AVPlayer` on iOS. DRM, ABR, and decode stay in those engines. The TypeScript layer uses the same intents and the same event schema as the other apps.

### Alternatives

- `react-native-video` as an unexamined dependency, with DRM left implicit
- A WebView around the web player

### Consequences

- M10 needs a native module or native component on both platforms
- The mobile app can slip without taking web, Android, and iOS with it
- Styling is a `StyleSheet`, not the web CSS file

---

## ADR-010: Two local origins stand in for a second CDN

Date: 2026-10-04
Status: Accepted

### Context

A production player uses more than one CDN so one provider can fail. This lab cannot honestly operate two commercial networks. It can serve the same files on two ports and teach the session to switch base URL when a segment fetch fails.

### Decision

Run the same package tree on origin A (`127.0.0.1:8080`) and origin B (`127.0.0.1:8081`). Configure the session with a backup base URL. Do not describe this as a CDN provider integration.

### Alternatives

- A single origin, and a paragraph about CDNs
- Sign up for two commercial CDNs in the PoC

### Consequences

- Retry and failover are demonstrable on a laptop
- Cache hierarchy, tokenised URLs, and origin shielding stay in [beyond-poc.md](beyond-poc.md)

---

## ADR-011: The programme is generated

Date: 2026-10-04
Status: Accepted

### Context

The lab must be rebuildable and redistributable. A retail film cannot sit in the repository, and a missing master blocks every later phase.

### Decision

Generate `playpath-bars` with ffmpeg: video test pattern, audio tone, and a WebVTT the pipeline also writes. Commit the commands. Treat large outputs as build products. Commit small manifest fixtures when a test needs them.

### Alternatives

- Check in a downloaded clip
- Require each developer to supply their own film

### Consequences

- Captions and edit points are ours to break on purpose
- The picture is not a drama. The path is the product
- Codec choices stay on H.264 and AAC so every engine in the map can decode them
