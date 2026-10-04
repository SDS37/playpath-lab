# Controls and UX

Phase 9. The person sees the title, the picture, and a control bar. The engines do not own the bar. A default control bar from Shaka, hls.js, Media3, or `AVPlayerViewController` is replaced.

Stalls, quality, and ad cuts are phase 8 and phase 5. This document does not change them.

## What the bar does

| Control | Intent | When it is shown |
|---|---|---|
| Play | `play` | Engine state is paused or ended |
| Pause | `pause` | Engine state is playing |
| Seek | `seek` to a position in milliseconds | Always visible, disabled while a CSAI creative is playing |
| Time | none | Current position and duration from the engine |
| Title | none | `playpath-bars` |

Captions are a toggle that selects the text track the menu already contains. The toggle calls the session. It does not swap the master file.

## State

The bar is a function of the latest session snapshot:

- `playbackState`: `playing`, `paused`, `seeking`, `ended`
- `stalled`: boolean
- `adPlaying`: boolean
- `positionMs`, `durationMs`
- `error`: optional short message, with no key material

A stalled overlay may say that playback is buffering. It uses the same layout. It does not change theme, hide the bar, or reload the app.

A DRM error says that the title cannot be played. It does not offer a clear-media retry.

## Where styling lives

| Platform | Source of truth | Official guide |
|---|---|---|
| Web | CSS classes and custom properties. React sets `className` | [MDN CSS](https://developer.mozilla.org/en-US/docs/Web/CSS), and [standards/css.md](standards/css.md) |
| Android | Compose `MaterialTheme` and modifiers | [Material Design 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3) |
| iOS | Colors, fonts, and Auto Layout on UIKit views | [UIKit](https://developer.apple.com/documentation/uikit) |
| React Native | `StyleSheet.create` | [Style](https://reactnative.dev/docs/style) |

Semantic names, so the four UIs can be compared in review:

| Token | Use |
|---|---|
| `background` | Page or screen behind the picture |
| `control` | Bar surface |
| `text` | Labels and time |
| `accent` | Play progress |
| `danger` | DRM and fatal error text |

Web defines them as CSS custom properties on the player region. Compose defines them in the theme. UIKit defines them as named colors. React Native defines them once in the style module. There is no shared widget library across these toolkits. [ADR-009](architecture-decision-records.md) is the same idea for React Native: share behaviour, not views.

## Accessibility

Follow the platform’s accessibility guide for the controls that a person must reach.

| Platform | Source |
|---|---|
| Web | [WAI-ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) for a button and a slider, plus visible focus |
| Android | [Compose accessibility](https://developer.android.com/develop/ui/compose/accessibility) |
| iOS | [Accessibility for UIKit](https://developer.apple.com/documentation/uikit/accessibility-for-uikit) |
| React Native | [Accessibility](https://reactnative.dev/docs/accessibility) |

The play and pause buttons have accessible names that match the visible action. The seek control exposes its value as a position. Colour is not the only signal for a stalled or error state.

## Ad behaviour

- During SSAI, the bar treats the stitched presentation as the film. Tracking is an event, not a second player UI.
- During CSAI, `adPlaying` is true, seek is disabled, and the time label shows the creative or a simple “Ad” label. When the creative ends, the session seeks to the cue and clears `adPlaying`.
- Skip is out of scope. The demo creative is short and plays through.

## What a review rejects

- A pause glyph while `playbackState` is `paused`
- Seek implemented by changing a React or Compose slider state without calling the session
- A loading spinner that remounts the engine
- Inline styles on the web that duplicate the CSS tokens
- A CSS or Compose change described as the fix for a stall
