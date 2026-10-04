# Business requirements

**Product:** PlayPath Lab
**Version:** PoC
**Last updated:** 2026-10-04
**Status:** Accepted for the proof of concept. Implementation follows [roadmap.md](roadmap.md).

## 1. Vision

One finished programme is prepared once and played on every device the service cares about. Packaging, encryption, and delivery happen before any app runs. Each device uses the engine its platform actually ships. A person presses play and gets picture, sound, captions, and a control bar that tells the truth. An operator can see startup, stalls, quality, ads, and DRM failures in the same shape on every platform.

The lab is a proof, not a consumer streaming service. It uses a generated title so the path can be rebuilt and shown without a licensed film.

## 2. Who it is for

| Role | What they need from the PoC |
|---|---|
| Viewer | Press play, watch the title, use play, pause, and seek, and sit through the ad breaks the demo includes |
| Engineer | Point at one phase, see the technology that owns it, and run the happy path for that phase |
| Operator | Read one event stream and tell a license failure from a stall from a bad ad cut |

## 3. Requirements

### 3.1 One title

- The lab has one programme, `playpath-bars`.
- Every device plays derivatives of that same master.
- A wrong audio mix, caption file, or edit is fixed in the master. Players do not patch the programme.

### 3.2 Play on the devices people actually use

- Web (Chrome, Edge, Firefox, and Safari) can play the title.
- Android can play the title.
- iOS can play the title.
- React Native is in scope where the native engine can be reached from a TypeScript screen.
- A TV or Cast web runtime is in scope only as a page that loads the same way a browser engine does. Device certification is out of the PoC.

### 3.3 Start before the file has finished downloading

- Playback starts from the first segments.
- Quality may drop when the network is poor, and the picture continues.
- A failed segment is fetched again. The title does not start over.

### 3.4 Protected media fails closed

- Encrypted segments are useless outside an allowed player.
- The control bar never receives the content key.
- If the license step does not return a key, the screen stays black.
- The PoC demonstrates that rule with Clear Key. Production FairPlay, Widevine, and PlayReady are the systems those platforms require, and they are specified in [beyond-poc.md](beyond-poc.md) until vendor credentials exist.

### 3.5 Ads have a defined failure

- The demo includes a pre-roll stitched into the menu, and a mid-roll played by the app from a VAST document.
- If the personalised ad menu cannot be built, the viewer gets the clean film.
- The app records that an ad was shown, including when the server stitched it in.
- A late ad must not leave the film at the wrong second.

### 3.6 Controls match the player

- Play, pause, and seek do what the engine is doing.
- A stall, a slow start, or a quality drop is a playback fault. Changing the layout is not the fix.
- During an ad, seek does not jump into the film at an arbitrary time.

### 3.7 One set of facts

- Startup time, stalls, bitrate, missed or played ad breaks, and DRM errors are reported from every app.
- An outage that hits only one engine is visible next to the others.

## 4. Out of scope for the PoC

- A catalogue, accounts, payments, or profiles
- A licensed film or third-party mezzanine
- Production FairPlay, Widevine, and PlayReady license services (see [ADR-003](architecture-decision-records.md))
- A commercial CDN, global traffic, or origin shielding in a provider network
- Live linear channels, slates, and key rotation
- Offline downloads and expiry
- HDMI and digital-output protection policy
- Multiple titles, audio languages beyond the single demo mix, or a second caption language
- Certified receivers for Chromecast, Tizen, or webOS
- Replacing a stall by restyling the control bar

Production-shaped follow-ups live in [beyond-poc.md](beyond-poc.md).

## 5. Success

A colleague can follow [happy-path.md](happy-path.md) and watch `playpath-bars` go from the master file to picture and sound on the web, on Android, and on iOS, with the ad breaks, the license step, and the same monitoring events the [Definition of Done](DoD.md) lists.
