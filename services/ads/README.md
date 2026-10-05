# Ads

The ads service stitches a clear pre-roll of about 5 seconds in front of `playpath-bars` and returns that presentation on port 8083. It also serves the VAST mid-roll. It is not a player.

The module is `github.com/SDS37/playpath-lab/services/ads`, one module for this service. The repository `go.work` includes that module so the command below runs from the repository root. `main.go` and `stitch.go` share this directory, so the command package is `main`.

From the repository root, after `./pipeline/encrypt.sh` and `./pipeline/preroll.sh`:

```bash
go run ./services/ads
```

That listens on `http://127.0.0.1:8083`.

- `GET /ssai/hls/master.m3u8` is the stitched HLS menu.
- `GET /ssai/dash/manifest.mpd` is the stitched DASH menu.

Both start with the pre-roll and then the film. Film segment URLs point at origin A, `http://127.0.0.1:8080`. The clean film menus stay there: `/master.m3u8` and `/manifest.mpd`. This service answers 404 for those paths.

`GET /vast/midroll.xml` is a VAST 4.2 document with one linear creative and one impression URL. The creative is the progressive file from `./pipeline/preroll.sh`, at `/preroll/creative.mp4` on this service. The impression URL is `/vast/impression` on this service. Both use the `-public` base, which defaults to `http://127.0.0.1:8083`. The cue in that document is `00:00:10.000`, which is 10 seconds into `playpath-bars`. `GET /vast/impression` answers 204. The film menu is unchanged.

The playback session, when an app exists, emits an `ad` event for the pre-roll with `breakId` `preroll`, `mode` `ssai`, and `action` `impression`, and one for this break with `breakId` `midroll` and `mode` `csai`. That schema is [playback events](../../docs/playback-events.md). No app emits either event yet, and no app has played the creative or returned to the cued second.
