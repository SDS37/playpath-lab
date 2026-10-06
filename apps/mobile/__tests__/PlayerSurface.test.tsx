import React, { createRef } from "react";
import ReactTestRenderer from "react-test-renderer";
import { Commands } from "../specs/PlaypathPlayerViewNativeComponent";
import { PlayerSurface, type PlayerCommands } from "../src/PlayerSurface";

test("play, pause, and seek are the native commands", () => {
  const ref = createRef<PlayerCommands>();
  ReactTestRenderer.act(() => {
    ReactTestRenderer.create(
      <PlayerSurface
        ref={ref}
        manifestUrl="http://127.0.0.1:8080/manifest.mpd"
        onSnapshot={() => undefined}
        onPlaybackEvent={() => undefined}
      />,
    );
  });
  ref.current?.play();
  ref.current?.pause();
  ref.current?.seek(10000);
  expect(Commands.play).toHaveBeenCalledTimes(1);
  expect(Commands.pause).toHaveBeenCalledTimes(1);
  expect(Commands.seek).toHaveBeenCalledTimes(1);
  const seekCall = (Commands.seek as jest.Mock).mock.calls[0] as unknown[];
  expect(seekCall[1]).toBe(10000);
});
