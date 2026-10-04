# React Native standards

React Native is the shared TypeScript UI for a phone app that still plays with Media3 and `AVPlayer`. [ADR-009](../architecture-decision-records.md).

The [Rules of React](react.md) apply in full. This file adds the native and style rules.

## Primary sources

1. [React Native](https://reactnative.dev/)
2. [Style](https://reactnative.dev/docs/style) and [`StyleSheet`](https://reactnative.dev/docs/stylesheet)
3. [Platform-specific code](https://reactnative.dev/docs/platform-specific-code)
4. [Fabric native components](https://reactnative.dev/docs/fabric-native-components-introduction), [Android](https://reactnative.dev/docs/fabric-native-components-android) and [iOS](https://reactnative.dev/docs/fabric-native-components-ios)
5. [Accessibility](https://reactnative.dev/docs/accessibility)
6. [Rules of React](https://react.dev/reference/rules)

## The split

| Layer | Technology |
|---|---|
| Controls, layout, intents | TypeScript, React Native |
| Frames, ABR, DRM, decode on Android | Media3, written from Kotlin or the existing Media3 Java API, inside a native view |
| Frames, ABR, decode on iOS | `AVPlayer`, written from Swift, inside a native view |
| Events across the bridge | The JSON in [playback-events.md](../playback-events.md) |

JavaScript does not decode, and it does not implement EME by hand inside Hermes.

## Style

React Native styles are JavaScript objects. Names are camel case (`backgroundColor`). There is no CSS file in `apps/mobile`.

- Define styles with `StyleSheet.create`.
- Pass an array of styles when a control needs a base style and a state style. The later entry wins, which is the documented array behaviour.
- A component may accept a `style` prop and apply it to its root view.
- Flexbox defaults to `column`. Spell `flexDirection: "row"` when the bar is horizontal.
- Do not assume every CSS property exists. Negative margin and overflow differ from the web; the style doc lists the known gaps. Check the control on both platforms.

Tokens from [ux-controls.md](../ux-controls.md) (`background`, `control`, `text`, `accent`, `danger`) live in one module, `theme.ts`, as values the `StyleSheet` reads.

## Platform files

Use `PlayerView.android.tsx` and `PlayerView.ios.tsx` when the native view’s props diverge. Shared controls stay in `Controls.tsx` and receive the snapshot, so the bar does not fork.

`Platform.OS` is for a small branch. A file that is half Android and half iOS becomes two platform files.

## Native view

Follow the Fabric native-component guide for the React Native version we pin. The legacy view-manager bridge is not the template for new code.

The native side:

- Creates and releases the player with the view’s lifecycle
- Accepts `manifestUrl` and commands `play`, `pause`, and `seek`
- Emits the playback-event names

The TypeScript side types those commands and events. It does not pass a content key as a prop.

## Components

- Function components and Hooks, same as web.
- The player object on the native side is not React state.
- Lists and keys follow the Rules of React.
- Touch targets use the platform accessibility props (`accessibilityRole`, `accessibilityLabel`).

## What we do not add

- A WebView of `apps/web` as the phone player. That hides the native engine this milestone exists to prove.
- A new JavaScript player package as a shortcut when the native build fails. The roadmap says to record the blocker.

## Tooling

- TypeScript `strict`, as in [typescript.md](typescript.md)
- ESLint with the React Hooks plugin
- Format with Prettier

## Review rejects

- `StyleSheet` rules copied by hand into every component instead of `theme.ts`
- A `seek` prop that the native view ignores while the slider moves a local number only
- Logging the license response in the bridge
- CSS files, styled-components web syntax, or `className`
