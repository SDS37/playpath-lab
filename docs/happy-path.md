# Happy path

This is the demo of PlayPath, in the order a viewer and an engineer actually meet the system. Phases 1 to 4 are already done before anyone presses play. The script is the proof behind the [Definition of Done](DoD.md). Requirements IDs point at [technical-requirements.md](technical-requirements.md).

The title is `playpath-bars`, a generated programme of about 60 seconds with picture, tone, and captions. A pre-roll is stitched into the menu. A mid-roll cue sits at 10 seconds.

Nothing in this script runs until the [roadmap](roadmap.md) builds it. When a step lands, the app README for that step links the command.

## Before play

1. **Master.** A pipeline command writes the mezzanine and a WebVTT file. Open the master directory and confirm there is no playlist (TR-1.1).
2. **Package.** `./pipeline/hls.sh` writes one CMAF ladder and the HLS menu. `./pipeline/dash.sh` writes the DASH menu from those same files. `./pipeline/timelines.sh` fails if the segment times or the presentation duration diverge (TR-2.1 to TR-2.4).
3. **Encrypt.** `./pipeline/encrypt.sh` writes a CENC copy of that ladder under `pipeline/protected/playpath-bars/`. The clear package stays. A player with no key cannot decode a protected segment. The protected menus name the lab key id (TR-3.1, TR-3.2). A play with the license service down stays black once a player exists (TR-7.3).
4. **Origin.** Origin A on port 8080 and origin B on port 8081 both serve that tree (TR-4.4).

## Press play

5. **Ads, server side.** The app requests the stitched menu from the ads service. The first pictures are the pre-roll. The film follows without a second play press. The event log records an impression (TR-5.1, TR-5.6).
6. **Engine.** The web build uses Shaka for the protected DASH menu. Chrome or Firefox, in the clear-HLS build, uses hls.js. Safari uses native HLS for the clear menu. Android uses Media3. iOS uses `AVPlayer` (TR-6.1 to TR-6.5).
7. **License.** On the protected web and Android plays, the engine calls the license service. The control code never prints the key. Startup time includes that round trip (TR-7.1, TR-7.2, TR-10.4).
8. **Buffer and ABR.** Picture starts before the whole file has arrived. Restricting the network moves the player to the lower rung, and a bitrate event is logged (TR-8.2, TR-10.2).
9. **Controls.** Pause shows a play icon only after the engine reports paused. Seek moves the film. During the mid-roll, seek does nothing to the film (TR-9.5, TR-9.6).
10. **Mid-roll.** At 10 seconds the film pauses, the VAST creative plays, and the film returns to that second. An impression is logged (TR-5.5, TR-5.6).
11. **Monitor.** The session’s JSON from web, Android, and iOS shares field names. Startup, the ad events, and the bitrate change are all present (TR-10.1 to TR-10.3).

## The failures that are part of the happy path

These are the designed failures. A demo that only shows the sunny path has not proved the architecture.

| Step | What you do | What you see |
|---|---|---|
| License down | Stop the license service and press play on the protected menu | Black picture, a `drm` error event, no clear-media fallback |
| Stitcher down | Stop the ads service and press play | The clean film plays |
| Origin A down | Play with a backup base URL and refuse segments on origin A | Playback continues from origin B |
| Stall | Drop throughput to a crawl | A stall or a bitrate event. The control layout is the same one as before |

## What this demo does not show

FairPlay’s certificate exchange, a Widevine or PlayReady license, a commercial CDN, live key rotation, and a certified TV receiver. Those are [beyond the PoC](beyond-poc.md).
