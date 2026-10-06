# Origin

Origin A serves the protected `playpath-bars` package over HTTP. It is a stand-in for a CDN, not a CDN provider. See [ADR-010](../../docs/architecture-decision-records.md).

The module is `github.com/SDS37/playpath-lab/services/origin`, one module for this service. The repository `go.work` includes that module so the command below runs from the repository root. `main.go` and `server.go` share this directory, so the command package is `main`.

From the repository root, after `./pipeline/encrypt.sh`:

```bash
go run ./services/origin
```

That listens on `http://127.0.0.1:8080`. Origin B is the same server on the backup base URL:

```bash
go run ./services/origin -addr 127.0.0.1:8081
```

[`session.json`](session.json) records both URLs. `BackupURL` keeps the segment path, so a failed `seg_5` is requested as `seg_5` on origin B. `-refuse-segments` answers 503 for `.m4s` and still serves menus and init segments. `GET` and `HEAD` of a menu or segment return a content type and `Last-Modified`. `.m3u8` is `application/vnd.apple.mpegurl` and `.mpd` is `application/dash+xml`. Video fMP4 is `video/mp4`. fMP4 in the `audio` rendition is `audio/mp4`, matching the DASH menu. Any other method gets `405` with `Allow: GET, HEAD, OPTIONS`. A directory and `lab-key.json` get `404`, including a different case or a backslash in the path. A page on exactly `http://127.0.0.1:5173` can read menus and segments. The response then carries `Access-Control-Allow-Origin` for that origin, methods `GET, HEAD, OPTIONS`, and the range and content headers a player reads. Any other origin gets no `Access-Control-Allow-Origin`. Every response sends `Vary: Origin`. `OPTIONS` of a real file is 204. `OPTIONS` of `lab-key.json` or a missing path is 404. The process does not list files and does not serve the content key.
