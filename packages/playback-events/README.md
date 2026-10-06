# Playback events

Version 1 of the [playback event](../../docs/playback-events.md) document, as one JSON Schema. Kotlin and Swift validate the same file. This package does not play media, and it does not emit events from the apps.

`schema/playback-event.v1.json` is the schema. `fixtures/startup.json` is a web startup. `fixtures/drm-error.json` is an Android drm error. `fixtures/bitrate.json` is an iOS rung change: `positionMs` and `startupMs` are milliseconds, `height` is pixels, and `bandwidthBps` is bits per second. A startup that renames `startupMs` fails validation. The fixtures do not carry a content key, a license body, or a credential.

```bash
npm test
npm run check
```
