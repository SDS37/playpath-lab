# Beyond the PoC

The [Definition of Done](DoD.md) is a local happy path. The items below are the production shape of the same architecture. They are not quietly in scope. Add one only when its trigger is true, and write an ADR when it changes a decision.

## 1. Production DRM

**Trigger:** a FairPlay certificate and key-server module, a Widevine license entitlement, or a PlayReady license server is actually available.

**Work:** keep CENC. Point Shaka, Media3, or `AVContentKeySession` at that license server and that key system. Prefer one cbcs encryption if the vendor matrix for that title allows a single ciphertext for FairPlay, Widevine, and PlayReady. If a platform requires a second encryption scheme, record it as a second package and say why “encrypt once” no longer holds.

**Still true:** the app does not hold the key. Failure stays closed.

## 2. A real CDN

**Trigger:** the title is played by clients outside the laptop, or a single origin’s bandwidth is exhausted.

**Work:** put the same package on a provider network, keep a second provider, and keep the backup-base-URL behaviour from [ADR-010](architecture-decision-records.md). Add tokenised URLs in the origin layer, not in Compose or React.

## 3. Live

**Trigger:** the product must play a channel rather than `playpath-bars`.

**Work:** a live window, a slate when an ad is late, and key rotation on the license service. The event schema gains a live flag. VOD requirements stay as they are.

## 4. Downloads

**Trigger:** a product requirement for offline playback.

**Work:** platform download APIs (Media3 offline, `AVAssetDownloadTask`, EME persistent licenses where the CDM allows them) and an expiry the license server enforces. The UI shows expiry. It does not store the key.

## 5. Output protection

**Trigger:** a content contract requires HDCP or an analogue-output policy.

**Work:** platform DRM policy on the license. The control bar does not implement HDCP.

## 6. Certified receivers

**Trigger:** a Chromecast, Tizen, or webOS device is a launch target.

**Work:** the receiver page from M10 becomes a registered receiver. The event schema’s `platform` gains a value. Certification suites are the proof, not a desktop browser.

## 7. More renditions and codecs

**Trigger:** a device matrix needs HEVC, AV1, or a third rung.

**Work:** extend the ladder in the pipeline. Keep one timeline. Update both menus. H.264 remains until every in-scope engine can play the new codec, or the menu marks the new rung so older engines skip it.

## 8. Accounts and a catalogue

**Trigger:** more than one title, or a viewer identity.

**Work:** a service in front of the manifest URL. Playback sessions still receive a URL. They do not grow a catalogue database.

## Explicitly not a follow-up

- Rewriting Shaka, hls.js, Media3, or AVFoundation
- Decrypting in application code
- Fixing ABR in CSS, Compose modifiers, or UIKit layout
- A fifth player written in TypeScript so React Native can avoid native code
