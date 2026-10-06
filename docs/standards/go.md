# Go standards

Go is the origin, the Clear Key license service, and the ad service. It is not a player.

## Primary sources

1. [Effective Go](https://go.dev/doc/effective_go)
2. [Go Doc Comments](https://go.dev/doc/comment)
3. [Code Review Comments](https://go.dev/wiki/CodeReviewComments)
4. [Standard library](https://pkg.go.dev/std) for `net/http`, `context`, and `encoding/json`

`gofmt` is the format. A change that is not `gofmt`-clean is not ready. `go vet` runs with tests.

## Names

From Effective Go and the review comments:

- Package names are short, lower case, and single words: `origin`, `license`, `ads`. The import path carries the rest.
- Exported names are `MixedCaps`. Unexported names are `mixedCaps`. Underscores are not used in names.
- The package name is not repeated on every type (`license.Server`, not `license.LicenseServer`), except where omitting it would be unclear.
- Initialisms keep a consistent case: `keyID`, `HTTPServer`, `urlPath`.
- Interface names with one method are that method plus `-er` when the English works (`Handler` already exists in `net/http`; do not invent `HandleEr`).
- Errors are lowercase strings with no trailing punctuation, returned as values. `panic` is for programmer mistakes, not for a missing key.
- Context is the first parameter: `func (s *Server) ServeHTTP` already has a request context. Helpers take `ctx context.Context` first.

## Service behaviour

| Service | Happy path | Failure |
|---|---|---|
| `origin` | `GET` of a manifest or segment with a content type and a cache validator | `404` or `405`. No directory listing of the key file |
| `license` | Clear Key response for a known key id | Non-success status. No clear media, no empty key that still “succeeds” |
| `ads` | Stitched HLS and DASH, and a static VAST document | Stitcher error status. The clean URL is served by `origin`, not invented here |

Handlers are small. Parsing, stitching, and the key lookup are functions the handler calls. The handler writes the status.

```go
func (s *Server) handleLicense(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        return
    }
    // Look up the lab key. On failure, write a non-200 and return.
}
```

Log the status and the key id. Do not log the key.

## HTTP

- Use `net/http`. A third-party router needs a reason in the commit.
- Set timeouts on the `http.Server` (`ReadHeaderTimeout` at minimum).
- Pass `r.Context()` into any work that should cancel when the client leaves.
- Accept interfaces where the standard library already does (`io.Reader`, `http.Handler`). Return concrete types from constructors (`func New(dir string) *Server`).

## Layout

```
services/origin/
  main.go
  server.go
  session.go
services/license/
  main.go
  clearkey.go
services/ads/
  main.go
  stitch.go
  fallback.go
  vast/
    midroll.xml
```

`main` wires flags and listens. It does not contain stitch logic.

## Tests

Table-driven tests, as Effective Go and the standard library do. The license test covers a known key id and an unknown key id. The stitch test covers a menu in and a menu that still contains the film’s timeline. The origin test covers content type.

## Modules

One `go.mod` per service, or one module at `services/` if they share a tiny package. Decide in the first Go commit and record it in that service README. Do not introduce a framework.

## Review rejects

- A handler that serves the mezzanine
- A fallback inside `license` that redirects to the clear package
- Ignored errors (`_ =` on a write that can fail), except `Write` to a client that has gone away, which is still logged once
- `init` functions that start network listeners
- Global mutable key material
