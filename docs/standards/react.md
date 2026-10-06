# React standards

The web UI is React. The player is not a component tree. The component tree draws [controls](../ux-controls.md) from session state and sends intents back.

React Native follows these rules and the extra rules in [react-native.md](react-native.md).

## Primary sources

1. [Rules of React](https://react.dev/reference/rules)
2. [Thinking in React](https://react.dev/learn/thinking-in-react)
3. [Strict Mode](https://react.dev/reference/react/StrictMode)
4. [`eslint-plugin-react-hooks`](https://www.npmjs.com/package/eslint-plugin-react-hooks), which react.dev uses to enforce those rules
5. [Referencing values with refs](https://react.dev/learn/referencing-values-with-refs) for the player object

The Rules of React are rules. A break is a bug, which is how the React docs describe them.

## Rules we follow

- Components and Hooks are pure. The same props, state, and context produce the same output. Render does not load a manifest, seek, or write a log.
- Side effects run in event handlers or in effects, not during render.
- Props and state are immutable snapshots. Do not mutate them.
- Hooks run at the top level of a component or a custom Hook, not inside a condition or a loop.
- Components are used from JSX. They are not called as plain functions.
- The app root is wrapped in `StrictMode`.

## Thinking in React, applied to the player

Build the static control bar first. Identify the snapshot that changes: engine state, position, stalled, ad playing, error. Lift that snapshot to the session. Pass it down as props. Pass intents up.

```tsx
type ControlsProps = {
  playbackState: "playing" | "paused" | "seeking" | "ended";
  stalled: boolean;
  adPlaying: boolean;
  onPlay: () => void;
  onPause: () => void;
  onSeek: (positionMs: number) => void;
};

export function Controls({ playbackState, onPlay, onPause }: ControlsProps) {
  const showPause = playbackState === "playing" || playbackState === "seeking";
  return (
    <button type="button" className="control" onClick={showPause ? onPause : onPlay}>
      {showPause ? "Pause" : "Play"}
    </button>
  );
}
```

The snippet is the shape, not the finished bar. Styling is a class, from [css.md](css.md).

## The engine and effects

Shaka and hls.js objects are not React state. They are mutable engines with their own lifetime. Hold them in a ref inside the session hook, create them in an effect, and destroy them in the effect cleanup. State holds the snapshot the controls render.

An effect synchronises the engine with a URL or a license endpoint. It does not compute derived labels. Derived labels are variables in render.

Dependencies of that effect are real: the manifest URL and the engine kind. A missing cleanup that leaves two `shaka.Player` instances attached is a bug Strict Mode will provoke on purpose.

## Component shape

- Function components only.
- One component per file when it is a screen or the control bar. Small local components may share a file when they are used once.
- Props are a named type, not an inline object repeated at every call.
- Lists, if a list of events is ever shown, use a stable id as `key`. Index keys are rejected for reorderable data.
- No `dangerouslySetInnerHTML`.

## Data flow

```
engine events → session state → props → controls
controls → intents → session → engine methods
```

A button does not import `shaka` or `Hls`. A button does not call `video.play()` on a DOM node it found with `querySelector`.

## Files

| File | Role |
|---|---|
| `PlaybackSession.ts` | Engine lifetime and intents. No JSX |
| `usePlaybackSession.ts` | Hook that subscribes React to the session |
| `Controls.tsx` | Bar, time, seek, stall, and error text |
| `PlayerScreen.tsx` | Media element, menu, and bar |

The web app’s tree, and the responsibility of each of these files, is in [the web README](../../apps/web/README.md#page-structure).

## Tooling

- `eslint-plugin-react-hooks` on the recommended and compiler-facing rules current for the React version we pin
- React DevTools are for local diagnosis. They are not a runtime dependency

## Review rejects

- `useEffect` with an empty dependency list that reads props
- Storing `shaka.Player` in `useState`
- A control that copies `playbackState` into its own `useState` and then drifts
- Fetching the VAST document inside `Controls`
