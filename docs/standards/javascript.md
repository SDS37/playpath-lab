# JavaScript standards

JavaScript is the web runtime. Shaka Player and hls.js are written in it. The browser executes the compiled TypeScript. A TV or Cast receiver page may be authored in JavaScript when that runtime has no TypeScript build.

We still **author** product UI in TypeScript. See [typescript.md](typescript.md).

## Primary sources

1. [MDN JavaScript Guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide)
2. [ECMA-262](https://tc39.es/ecma262/)
3. [W3C Media Source Extensions](https://www.w3.org/TR/media-source/)
4. [W3C Encrypted Media Extensions](https://www.w3.org/TR/encrypted-media/)
5. [Shaka Player docs](https://shaka-project.github.io/shaka-player/docs/api/tutorial-welcome.html)
6. [hls.js README](https://github.com/video-dev/hls.js/)

MDN is the reference for the language the browser implements. The W3C specs are the reference for the media element, MSE, and EME. Library docs are the reference for how those players expect to be called.

## What application JavaScript may do

A receiver page that cannot be TypeScript:

- Creates a media element
- Loads Shaka the way its tutorial describes
- Posts [playback events](../playback-events.md) with `fetch`
- Contains no second player implementation

Everything else in `apps/web` and `apps/mobile` is TypeScript.

## Language rules

These follow MDN’s current guidance for ordinary scripts.

- `"use strict"` is implicit in modules. Receivers are ES modules where the device allows them.
- `const` by default. `let` when the binding is reassigned. `var` is not used.
- `===` and `!==`.
- Promises and `async`/`await` for the license and ads HTTP calls a page makes itself. The player’s own network stack stays inside Shaka or hls.js.
- Errors are thrown or returned. They are not swallowed.
- No global `player` on `window` except where a device receiver template requires a named hook. That hook constructs the session and returns.

## EME and MSE

Application code does not call `MediaKeys` to stash a key in a closure we control. Shaka’s DRM configuration points at the license URL. The CDM is the browser’s.

Application code does not append `SourceBuffer`s for the film when Shaka or hls.js is the engine. Those libraries are the MSE clients. A hand-written buffer is a new engine, and [ADR-008](../architecture-decision-records.md) forbids it.

## Dependencies

- Pin Shaka and hls.js to exact versions in the web app manifest.
- Upgrade them on purpose, in a commit that says which engine behaviour changed.
- Do not fork either library to adjust ABR. Configure the public ABR API or file the behaviour as an engine limit in the event `extra` object.

## Receiver formatting

If a file is plain JavaScript, it still uses two-space indentation, semicolons, and `const`/`let`, so it matches the TypeScript style a colleague already reads. JSDoc types are added on exported functions when the file is not checked by `tsc`.

## Review rejects

- A `MediaKeySession` whose `ArrayBuffer` is logged
- hls.js pointed at the protected manifest
- A polyfill copied into the repo when the engine already documents the one it supports
- `eval`, `new Function`, or string-built script tags
