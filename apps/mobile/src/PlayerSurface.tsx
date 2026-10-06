import { forwardRef, useImperativeHandle, useRef, type ElementRef } from "react";
import { StyleSheet } from "react-native";
import NativePlayer, {
  Commands,
} from "../specs/PlaypathPlayerViewNativeComponent";
import {
  snapshotFromPayload,
  type PlaybackSnapshot,
  type SnapshotPayload,
} from "./snapshot";
import { theme } from "./theme";

export type PlayerCommands = {
  play: () => void;
  pause: () => void;
  seek: (positionMs: number) => void;
};

export type PlayerSurfaceProps = {
  manifestUrl: string;
  onSnapshot: (snapshot: PlaybackSnapshot) => void;
  onPlaybackEvent: (json: string) => void;
};

/**
 * Hosts the Fabric view. Frames, ABR, and DRM stay in that view.
 * This module does not decode samples.
 */
export const PlayerSurface = forwardRef<PlayerCommands, PlayerSurfaceProps>(
  function PlayerSurface({ manifestUrl, onSnapshot, onPlaybackEvent }, ref) {
    const nativeRef = useRef<ElementRef<typeof NativePlayer>>(null);

    useImperativeHandle(ref, () => ({
      play() {
        const view = nativeRef.current;
        if (view) {
          Commands.play(view);
        }
      },
      pause() {
        const view = nativeRef.current;
        if (view) {
          Commands.pause(view);
        }
      },
      seek(positionMs: number) {
        const view = nativeRef.current;
        if (view) {
          Commands.seek(view, positionMs);
        }
      },
    }));

    return (
      <NativePlayer
        ref={nativeRef}
        style={styles.picture}
        manifestUrl={manifestUrl}
        onSnapshot={(event) => {
          onSnapshot(snapshotFromPayload(event.nativeEvent as SnapshotPayload));
        }}
        onPlaybackEvent={(event) => {
          onPlaybackEvent(event.nativeEvent.json);
        }}
      />
    );
  },
);

const styles = StyleSheet.create({
  picture: {
    backgroundColor: theme.background,
    flex: 1,
  },
});
