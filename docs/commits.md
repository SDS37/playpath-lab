# Commits

Messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

```
type(scope): short description
```

The description is the reason, in the imperative, and it fits on one line.

## Types

| Type | When |
|---|---|
| feat | A new slice of the path (a phase, an engine, a control) |
| fix | A bug fix |
| docs | Documentation only |
| style | Formatting only |
| refactor | A change that neither fixes a bug nor adds a feature |
| perf | A performance change |
| test | Tests only |
| build | Build system or dependencies |
| ci | CI configuration |
| chore | Tooling and other housekeeping |
| revert | Reverts a previous commit |

## Scopes

Use the area the change lives in.

| Scope | Area |
|---|---|
| pipeline | Master, packager, encrypt |
| origin | HTTP segment host |
| license | Clear Key license service |
| ads | SSAI rewriter and VAST |
| web | React player |
| android | Compose and Media3 |
| ios | UIKit and AVFoundation |
| mobile | React Native |
| events | Shared playback JSON |
| docs | Documentation |
| infra | Local run wiring |

Omit the scope when the change is the whole repo (`docs: add the PoC requirements`).

## Examples

```
feat(pipeline): write HLS and DASH menus from the mezzanine
feat(web): play the DASH manifest with Shaka
fix(ads): resume the film at the mid-roll cue
docs: describe the Clear Key license boundary
test(events): reject a payload that omits startup time
```

## What a commit contains

- One phase step or one engine change. A commit that packages the master and also skins the control bar is two commits.
- No content keys from a real DRM vendor, no certificates, and no `.env` secrets.
- The lab Clear Key used by the PoC is a published test key, named as such in the pipeline docs when it lands.
