# Ads

The ads service stitches a clear pre-roll of about 5 seconds in front of `playpath-bars` and returns that presentation on port 8083. It is not a player. The VAST mid-roll document is a later story.

The module is `github.com/SDS37/playpath-lab/services/ads`, one module for this service. The repository `go.work` includes that module so the command below runs from the repository root. `main.go` and `stitch.go` share this directory, so the command package is `main`.

From the repository root, after `./pipeline/encrypt.sh` and `./pipeline/preroll.sh`:

```bash
go run ./services/ads
```

That listens on `http://127.0.0.1:8083`.

- `GET /ssai/hls/master.m3u8` is the stitched HLS menu.
- `GET /ssai/dash/manifest.mpd` is the stitched DASH menu.

Both start with the pre-roll and then the film. Film segment URLs point at origin A, `http://127.0.0.1:8080`. The clean film menus stay there: `/master.m3u8` and `/manifest.mpd`. This service answers 404 for those paths.

The playback session, when an app exists, emits an `ad` event for this break with `breakId` `preroll`, `mode` `ssai`, and `action` `impression`. That schema is [playback events](../../docs/playback-events.md). No app emits it yet.
