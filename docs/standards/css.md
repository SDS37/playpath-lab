# CSS standards

Web styling is CSS next to the React app. TypeScript attaches a class. It does not carry the theme in inline style objects.

## Primary sources

1. [MDN CSS](https://developer.mozilla.org/en-US/docs/Web/CSS)
2. [CSS custom properties](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_cascading_variables/Using_CSS_custom_properties)
3. [WAI-ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) for control behaviour that CSS must not fight (focus, contrast)

## Rules

- One player region owns the tokens: `--background`, `--control`, `--text`, `--accent`, `--danger`. Names match [ux-controls.md](../ux-controls.md).
- Components use classes (`.control-bar`, `.control`). IDs are not a styling hook.
- Custom properties carry the theme. A class switches a state (`.control-bar[data-stalled="true"]`).
- The cascade stays shallow. A control does not depend on a long chain of element selectors.
- Units are `rem` for type and spacing that should follow the user’s font size, and percentages or `px` only where the media layout needs a physical pixel (the 1px focus outline is fine).
- Colour contrast for text on `--control` meets WCAG AA as documented by W3C (at least 4.5:1 for normal text).
- `:focus-visible` shows a focus ring. Do not remove the outline without replacing it.
- Motion: a buffering indicator may animate. Respect `prefers-reduced-motion`.

## What stays out of CSS

- Playback position is a width set from the snapshot (a custom property `--progress` written by the component is allowed). The stylesheet does not guess the time.
- No `animation` that pretends to be playback.
- No background image of a fake video frame.

## Files

```
apps/web/src/player/player.css
```

The React component imports that file once. Class names are stable strings. CSS modules are acceptable if the whole web app uses them; do not mix modules and global classes in the bar.

## Inline styles

An inline `style` is allowed for the progress width and for nothing else. Colors, fonts, gaps, and layout live in the stylesheet.

## Review rejects

- A stall fix that is only a CSS change
- Duplicated hex values that ignore the custom properties
- `!important`
- A second design system for one control bar
