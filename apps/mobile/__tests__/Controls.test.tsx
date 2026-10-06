import React from "react";
import ReactTestRenderer from "react-test-renderer";
import { Text } from "react-native";
import { Controls } from "../src/Controls";
import { initialSnapshot, type PlaybackSnapshot } from "../src/snapshot";

function render(snapshot: PlaybackSnapshot, handlers?: {
  onPlay?: () => void;
  onPause?: () => void;
  onSeek?: (positionMs: number) => void;
}) {
  const onPlay = handlers?.onPlay ?? jest.fn();
  const onPause = handlers?.onPause ?? jest.fn();
  const onSeek = handlers?.onSeek ?? jest.fn();
  let renderer: ReactTestRenderer.ReactTestRenderer;
  ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(
      <Controls
        snapshot={snapshot}
        onPlay={onPlay}
        onPause={onPause}
        onSeek={onSeek}
      />,
    );
  });
  return { renderer: renderer!, onPlay, onPause, onSeek };
}

test("shows Play while paused and Pause while playing", () => {
  const paused = render(initialSnapshot);
  expect(paused.renderer.root.findByProps({ accessibilityLabel: "Play" })).toBeTruthy();
  paused.renderer.root.findByProps({ accessibilityLabel: "Play" }).props.onPress();
  expect(paused.onPlay).toHaveBeenCalledTimes(1);

  const playing = render({ ...initialSnapshot, playbackState: "playing" });
  playing.renderer.root.findByProps({ accessibilityLabel: "Pause" }).props.onPress();
  expect(playing.onPause).toHaveBeenCalledTimes(1);
});

test("seek calls the session and stays disabled during an ad", () => {
  const onSeek = jest.fn();
  const open = render(
    { ...initialSnapshot, durationMs: 60_000, positionMs: 0 },
    { onSeek },
  );
  const seek = open.renderer.root.findByProps({ accessibilityLabel: "Seek" });
  ReactTestRenderer.act(() => {
    seek.props.onLayout({
      nativeEvent: { layout: { width: 100, height: 4, x: 0, y: 0 } },
    });
  });
  const next = open.renderer.root.findByProps({ accessibilityLabel: "Seek" });
  next.props.onPress({ nativeEvent: { locationX: 50 } });
  expect(onSeek).toHaveBeenCalledWith(30_000);

  const ad = render({
    ...initialSnapshot,
    adPlaying: true,
    durationMs: 5_000,
    positionMs: 1_000,
  });
  const adSeek = ad.renderer.root.findByProps({ accessibilityLabel: "Seek" });
  adSeek.props.onPress({ nativeEvent: { locationX: 10 } });
  expect(ad.onSeek).not.toHaveBeenCalled();
  const text = ad.renderer.root
    .findAllByType(Text)
    .map((node) => node.props.children)
    .flat(2)
    .join("");
  expect(text).toContain("Ad ");
});

test("shows Buffering and the error without a key", () => {
  const view = render({
    ...initialSnapshot,
    stalled: true,
    error: "The title cannot be played.",
  });
  const labels = view.renderer.root.findAllByType(Text);
  const text = labels.map((node) => node.props.children).join("");
  expect(text).toContain("Buffering");
  expect(text).toContain("The title cannot be played.");
  expect(text).not.toContain("ffefcdab");
});
