# License

The license service answers a Clear Key request for the published lab key. It is not a player, and it does not serve the film.

The module is `github.com/SDS37/playpath-lab/services/license`, one module for this service. The repository `go.work` includes that module so the command below runs from the repository root. `main.go` and `clearkey.go` share this directory, so the command package is `main`.

From the repository root:

```bash
go run ./services/license
```

That listens on `http://127.0.0.1:8082`. `POST /` with a Clear Key license request returns a JSON Web Key set for key id `00112233445566778899aabbccddeeff`. The request `kids` value may be that id in hex, as the protected menus write it, or the base64url form the CDM sends. The response uses `kty` `oct` and `type` `temporary`. The format is the [Clear Key license format](https://www.w3.org/TR/encrypted-media/#clear-key-license-format) in Encrypted Media Extensions.

An unknown key id, or a request that is not that JSON, gets a non-success status. The body does not name the clear package, and the response has no `Location` header. `GET` is `405`. Any other path, including `/master.m3u8`, is `404`. The log line is the method, the path, the status, and the key id. It does not include the key.

A page on `http://127.0.0.1:5173` can read the response. Other origins do not get that header. The web app calls this URL through Shaka. The Android app calls it through a Media3 DRM session. A wrong key id on that app is `POST / 403`, a black picture, and a `drm` error. Stopping this process, then playing encrypted DASH on Android, is a black picture and a `drm` error with `ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED`. The clear package is not requested. The iOS app plays clear HLS and does not call this URL.
