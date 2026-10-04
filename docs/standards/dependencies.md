# Dependencies we do not author

These technologies are on the path. We pin them, call them the way their manuals say, and we do not write a house style for them. [ADR-008](../architecture-decision-records.md).

| Technology | Role | Primary source | Our rule |
|---|---|---|---|
| C++ in Shaka Packager or ffmpeg | Phase 2 and phase 3. Cut the mezzanine, write CMAF, encrypt | [Shaka Packager](https://github.com/shaka-project/shaka-packager), [ffmpeg documentation](https://ffmpeg.org/documentation.html) | Shell out from `pipeline/`. Do not vendor a fork |
| C++ decoders and CDMs | Phase 8 decode, phase 7 decrypt | The platform and the engine | Never linked by our Kotlin, Swift, or TypeScript |
| Java inside Media3 | The player implementation ExoPlayer grew up as | [Media3](https://developer.android.com/media/media3/exoplayer) | Configure it from Kotlin. New Android UI code is Kotlin, per the [Android Kotlin style guide](https://developer.android.com/kotlin/style-guide) |
| Objective-C inside AVFoundation | Apple’s media APIs | [AVFoundation](https://developer.apple.com/documentation/avfoundation) | Call them from Swift. New iOS code is Swift |
| Shaka Player and hls.js | Web engines | Their manuals, linked from [engines.md](../engines.md) | Configure. Do not fork for ABR |
| Platform DRM | FairPlay, Widevine, PlayReady | Vendor docs linked from [architecture.md](../architecture.md) | Not in the PoC until credentials exist |

## Pipeline scripts

Shell in `pipeline/` is a sequence of packager commands with pinned versions. It is not an application language. Scripts are `set -euo pipefail` (or the PowerShell equivalent if one is ever required; the lab assumes a Unix shell). Comments say which phase the command belongs to.

## When a bug is in a dependency

- An invalid menu is a pipeline bug if our flags produced it.
- A black screen with a DRM error is a license or key-id bug until the engine’s own issue tracker says otherwise.
- A stall with a healthy license is phase 8: ABR configuration or the network, including origin response time.
- A control that lies while the engine event is correct is phase 9.

Fix the phase that owns the fault. Do not patch around it in another language.
