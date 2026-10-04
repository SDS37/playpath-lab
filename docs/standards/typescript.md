# TypeScript standards

TypeScript is the authoring language for the web app, the React Native app, and the playback-event types. JavaScript is what the browser runs. See [javascript.md](javascript.md).

## Primary sources

1. [TypeScript handbook](https://www.typescriptlang.org/docs/handbook/intro.html), including [Do's and Don'ts](https://www.typescriptlang.org/docs/handbook/declaration-files/do-s-and-don-ts.html)
2. [tsconfig reference](https://www.typescriptlang.org/tsconfig/)
3. [TypeScript compiler coding guidelines](https://github.com/microsoft/TypeScript/wiki/Coding-guidelines) for naming only

The handbook is the language. It does not publish an application style guide. The compiler wiki states that its rules are for the TypeScript codebase, not a prescription for every project. We still adopt that page’s naming section, because it is the TypeScript team’s own rule for types and values: `PascalCase` types, `camelCase` functions and properties, no `I` prefix on interfaces, no `_` prefix on private fields. We also use `undefined` for absence we control. DOM and player APIs that return `null` stay `null` at that boundary and are narrowed before they enter our types.

Formatting of application code follows the examples on [react.dev](https://react.dev/): two spaces, semicolons, trailing commas in multiline literals. The compiler codebase indents with four spaces and uses its own brace style. Those layout rules stay with the compiler.

## Ownership

| May | Must not |
|---|---|
| Session types, engine wrappers, React components, event types | Playlist parsing to pick a bitrate |
| Map Shaka and hls.js callbacks into [playback events](../playback-events.md) | Read a content key or a license body into a string we log |
| Call the ads service for a manifest URL | Implement MSE by hand |

## Compiler

`strict` is on. That includes `strictNullChecks`, `noImplicitAny`, and `strictFunctionTypes`. `noUncheckedIndexedAccess` is on in app packages.

- `unknown` is the type for a value we have not checked. `any` is a migration tool, and this repo does not start from JavaScript.
- Callbacks whose return value is ignored are typed `void`, not `any`.
- Optional callback parameters are rare. A callback that may ignore a parameter still lists it as required on the type, which is the handbook rule.
- Overloads that differ only by a trailing parameter collapse to optional parameters. Overloads that differ in one argument position become a union. More specific overloads come first.
- Boxed types `String`, `Number`, `Boolean`, `Object` are not used. Use `string`, `number`, `boolean`, `object`.

## Naming

From the compiler guidelines:

- Types, classes, and enums are `PascalCase`.
- Values, functions, and properties are `camelCase`.
- Interfaces do not take an `I` prefix. `PlaybackSession`, not `IPlaybackSession`.
- Do not prefix private fields with `_` as a substitute for visibility. Use `#` or the `private` keyword when a field must be hidden.
- A file exports one main type when it has one. Name the file after that type (`PlaybackSession.ts`). A file of related functions is named for the job (`mapShakaEvents.ts`).

Acronyms follow the Kotlin and Swift habit only where the official TypeScript names already do. `HlsSource` is acceptable because the library is hls.js. Do not invent `DRMManager`.

## Types for this lab

```ts
type PlaybackIntent =
  | { type: "play" }
  | { type: "pause" }
  | { type: "seek"; positionMs: number };

type EngineName = "shaka" | "hlsjs";
```

Discriminated unions are the shape of intents and events. A boolean soup (`isPlaying`, `isPaused`, `isEnded`) is not a second source of truth next to `playbackState`.

Public functions that can fail return a result the caller must handle, or they throw a typed error the session maps into a playback event. Empty `catch` blocks are rejected.

## Modules

ES modules only. `import` and `export`. No `namespace` as an application module system. No `require`.

The Shaka and hls.js entry points are imported by the session module. Components import the session hook or props, not `shaka` or `Hls`.

## Comments

Comment why a platform branch exists (`Safari plays HLS without hls.js`). Do not comment what a type already says.

## Tooling

- `tsc --noEmit` is part of the web and mobile checks.
- ESLint uses `typescript-eslint` with type-checked rules, plus the React rules in [react.md](react.md).
- Prettier prints the files. It does not decide types.

## Review rejects

- `any`, `as any`, and `@ts-ignore` without a one-line reason and a linked issue
- Non-null assertions (`!`) on engine events
- The content key typed as a field on a React prop
- A generic that is never used
