# Playback events

Phase 10. Every engine reports the same facts, in the same JSON, or an outage on one device stays invisible.

The schema is the contract. Kotlin, Swift, and TypeScript map engine callbacks into it. They do not invent parallel names. [ADR-006](architecture-decision-records.md).

## Envelope

Every message is one JSON object.

| Field | Type | Rule |
|---|---|---|
| `version` | number | `1` until a breaking change |
| `titleId` | string | `playpath-bars` for this PoC |
| `sessionId` | string | One id per press of play |
| `platform` | string | `web`, `android`, `ios`, or `react-native` |
| `engine` | string | `shaka`, `hlsjs`, `media3`, or `avplayer` |
| `event` | string | One of the names below |
| `at` | string | ISO-8601 UTC timestamp |
| `positionMs` | number | Media time of the film when the event happened. `0` if playback never started |
| `extra` | object | Optional string notes. No keys, no license bodies, no cookies |

Units are fixed: time in milliseconds, video height in pixels, bandwidth in bits per second.

## Events

### `startup`

Sent once when the engine first reaches a playing state.

| Field | Type |
|---|---|
| `startupMs` | number, from the load call to the first frame |
| `manifestUrl` | string, the URL the engine was given, without query credentials |

### `state`

| Field | Type |
|---|---|
| `playbackState` | `playing`, `paused`, `seeking`, or `ended` |

The control bar renders from the latest `state` plus `stalled`. It does not keep a private boolean.

### `stalled`

| Field | Type |
|---|---|
| `stallMs` | number, how long the stall lasted, once it ends. Omit on the starting edge and send `started: true` |

Also send `started` (boolean). `true` when the stall begins, `false` when it ends.

### `bitrate`

| Field | Type |
|---|---|
| `height` | number |
| `bandwidthBps` | number |
| `codecs` | string, the playlist codec string when the engine provides it |

### `ad`

| Field | Type |
|---|---|
| `breakId` | string, `preroll` or `midroll` in this PoC |
| `mode` | `ssai` or `csai` |
| `action` | `start`, `impression`, `complete`, or `error` |

### `drm`

| Field | Type |
|---|---|
| `keySystem` | string, `org.w3.clearkey` in this PoC, or `com.widevine.alpha`, `com.microsoft.playready`, `com.apple.fps` when those exist |
| `result` | `ok` or `error` |
| `code` | string, engine error code. No response body |

Clear HLS on iOS and hls.js sends no `drm` event. That absence means the play was clear. A protected play that skips `drm` is a bug.

### `error`

| Field | Type |
|---|---|
| `phase` | number, `4`, `5`, `7`, or `8` |
| `message` | string, short, with no secrets |

Use `drm` for license failure. Use `error` with `phase: 7` only for a failure around the license call that is not itself a key-system error, such as a DNS failure before a challenge exists. Prefer `drm` when the engine reports a DRM error.

## Examples

Startup from the web player:

```json
{
  "version": 1,
  "titleId": "playpath-bars",
  "sessionId": "8f0c",
  "platform": "web",
  "engine": "shaka",
  "event": "startup",
  "at": "2026-10-04T12:00:00Z",
  "positionMs": 0,
  "startupMs": 840,
  "manifestUrl": "http://127.0.0.1:8083/ssai/dash/manifest.mpd"
}
```

A license failure:

```json
{
  "version": 1,
  "titleId": "playpath-bars",
  "sessionId": "8f0c",
  "platform": "android",
  "engine": "media3",
  "event": "drm",
  "at": "2026-10-04T12:00:01Z",
  "positionMs": 0,
  "keySystem": "org.w3.clearkey",
  "result": "error",
  "code": "ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED"
}
```

## Mapping

| Engine signal | Event |
|---|---|
| Shaka `buffering` and adaptation events | `stalled`, `bitrate` |
| Shaka DRM error via the player error event | `drm` |
| hls.js `LEVEL_SWITCHED`, `ERROR` | `bitrate`, `error` |
| Media3 `onPlaybackStateChanged`, `onTracksChanged`, DRM session error | `state`, `bitrate`, `drm` |
| `AVPlayer` `timeControlStatus`, access log, `presentationSize`, item error | `state`, `stalled`, `bitrate`, `error` |

The mapper lives in the playback session. Controls do not translate engine codes.

## Validation

`packages/playback-events` will hold a JSON Schema for this document when M9 starts. Until then this file is the schema. A sample that adds a required-looking field under a new name, or that renames `startupMs`, fails review.

## Privacy

Events may include a manifest URL on localhost and a session id the app generated. They must not include the content key, the Clear Key response, a FairPlay SPC or CKC, a device id from a vendor SDK, or an ad-tracking identifier. Impression URLs are requested by the app and are not copied into the event. The event records `action: "impression"`.
