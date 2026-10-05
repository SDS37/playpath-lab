# Origin

Origin A serves the protected `playpath-bars` package over HTTP. It is a stand-in for a CDN, not a CDN provider. See [ADR-010](../../docs/architecture-decision-records.md).

The module is `github.com/SDS37/playpath-lab/services/origin`, one module for this service. The repository `go.work` includes that module so the command below runs from the repository root. `main.go` and `server.go` share this directory, so the command package is `main`.

From the repository root, after `./pipeline/encrypt.sh`:

```bash
go run ./services/origin
```

That listens on `http://127.0.0.1:8080`. `GET` of a menu or segment returns a content type and `Last-Modified`. `.m3u8` is `application/vnd.apple.mpegurl`, `.mpd` is `application/dash+xml`, and fMP4 (`.mp4`, `.m4s`) is `video/mp4`. Other methods get `405`. A directory and `lab-key.json` get `404`. The process does not list files and does not serve the content key.
