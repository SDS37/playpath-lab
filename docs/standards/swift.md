# Swift standards

Swift is the iOS app: UIKit for controls, AVFoundation for playback. Older AVFoundation types are Objective-C. We call them from Swift. We do not rewrite them. See [dependencies.md](dependencies.md).

## Primary sources

1. [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
2. [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/)
3. [swift-format](https://github.com/apple/swift-format), Apple’s formatter
4. [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) and [AVContentKeySession](https://developer.apple.com/documentation/avfoundation/avcontentkeysession)
5. [UIKit](https://developer.apple.com/documentation/uikit) and [Accessibility for UIKit](https://developer.apple.com/documentation/uikit/accessibility-for-uikit)
6. [HTTP Live Streaming](https://developer.apple.com/documentation/http-live-streaming)

Naming and documentation comments follow the API Design Guidelines. Layout and whitespace follow `swift-format` with its default configuration. Xcode’s indentation is four spaces.

## API design

Clarity at the point of use comes first. Clarity beats brevity. Every public declaration has a documentation comment whose summary is a fragment ending with a period, in Swift Markdown, describing what the declaration is or what it does.

- Types are upper camel case. Methods and properties are lower camel case.
- Methods are verbs. A mutating method reads as a verb in the imperative (`play`). A non-mutating method reads as a noun or a participle when that is the natural name.
- Omit words that repeat the type. Keep words that remove ambiguity at the call site (`seek(to:)`).
- Factory methods begin with `make`.
- Boolean properties and methods read as assertions (`isStalled`, `isAdPlaying`).
- Argument labels make the call read as a phrase. The first label is omitted only when the name already carries it (`play(url:)` keeps `url` because the type alone would be unclear if we later add a second parameter).
- Use `Optional` for absence. Do not use sentinel positions (`-1`) for “no time”.

```swift
/// Plays the HLS URL and publishes engine state.
final class PlaybackSession {
    func play(url: URL) {}

    /// Seeks to `positionMs` on the film timeline.
    func seek(to positionMs: Int) {}
}
```

Positions in the app are milliseconds, named `positionMs`, matching [playback events](../playback-events.md).

## Ownership of the player

- `PlaybackSession` owns `AVPlayer` and observes `timeControlStatus`, item status, and the access log for variant changes.
- A view controller owns the session and the UIKit control views.
- Views draw the snapshot. They do not import playback policy.
- Play, pause, and seek are methods on the session.
- The PoC does not create an `AVContentKeySession`. The session type is the place that method will live when FairPlay credentials exist, so the view controller never grows a key callback.

KVO and notifications are removed in `deinit` or when the item changes. A leaked observer is a bug.

## UIKit

- Colors, fonts, and constraints are set on the views, from named constants (`PlayerColors.accent`).
- Auto Layout is the layout system. Frames are not hand-calculated for the bar.
- Buttons use accessibility labels that match the visible action.
- The system transport controls of `AVPlayerViewController` are not the product bar. An `AVPlayerLayer` (or a player view with transport hidden) shows the picture.

## Concurrency

New code uses Swift concurrency (`async`/`await`) for our own HTTP, such as posting playback events. AVFoundation callbacks arrive on the queue the observer was registered on. Hop to the main actor before touching UIKit.

Do not block the main thread on a segment fetch. The player does its own fetching.

## Errors

AVFoundation errors become a playback `error` or `drm` event in the session. The view shows the short message. `try!` is rejected. `try?` is allowed only when absence is the real outcome and the next line handles it.

## Files

| Type | File |
|---|---|
| `PlaybackSession` | `PlaybackSession.swift` |
| Control views | `PlaybackControlsView.swift` |
| Screen | `PlayerViewController.swift` |

One primary type per file. A small private type used only there may share the file.

## Review rejects

- A view controller that seeks by setting `currentItem` time without going through the session’s method the bar also uses
- Force-unwrapping `currentItem`
- Logging an SPC, CKC, or key response if a future FairPlay path is added
- Objective-C source files for new app code
- A second style guide inside the target. `swift-format` is the format
