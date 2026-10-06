import { useState } from "react";
import {
  Pressable,
  StyleSheet,
  Text,
  View,
  type GestureResponderEvent,
} from "react-native";
import type { PlaybackSnapshot } from "./snapshot";
import { theme } from "./theme";

type ControlsProps = {
  snapshot: PlaybackSnapshot;
  onPlay: () => void;
  onPause: () => void;
  onSeek: (positionMs: number) => void;
};

export function Controls({ snapshot, onPlay, onPause, onSeek }: ControlsProps) {
  const showPause =
    snapshot.playbackState === "playing" ||
    snapshot.playbackState === "seeking";
  const [trackWidth, setTrackWidth] = useState(0);
  const progress =
    snapshot.durationMs === 0
      ? 0
      : Math.min(100, (snapshot.positionMs / snapshot.durationMs) * 100);

  function seekAt(event: GestureResponderEvent) {
    if (snapshot.adPlaying || snapshot.durationMs <= 0 || trackWidth <= 0) {
      return;
    }
    const ratio = Math.min(1, Math.max(0, event.nativeEvent.locationX / trackWidth));
    onSeek(Math.round(ratio * snapshot.durationMs));
  }

  return (
    <View style={styles.bar}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={showPause ? "Pause" : "Play"}
        style={styles.button}
        onPress={showPause ? onPause : onPlay}
      >
        <Text style={styles.label}>{showPause ? "Pause" : "Play"}</Text>
      </Pressable>
      <Pressable
        accessibilityRole="adjustable"
        accessibilityLabel="Seek"
        accessibilityState={{ disabled: snapshot.adPlaying }}
        accessibilityValue={{
          min: 0,
          max: snapshot.durationMs,
          now: Math.min(snapshot.positionMs, snapshot.durationMs),
          text: formatTime(snapshot.positionMs),
        }}
        disabled={snapshot.adPlaying}
        style={styles.seek}
        onLayout={(event) => {
          setTrackWidth(event.nativeEvent.layout.width);
        }}
        onPress={seekAt}
      >
        <View style={styles.track}>
          <View style={[styles.progress, { width: `${progress}%` }]} />
        </View>
      </Pressable>
      <Text style={styles.time}>
        {snapshot.adPlaying ? "Ad " : ""}
        {formatTime(snapshot.positionMs)} / {formatTime(snapshot.durationMs)}
      </Text>
      {snapshot.stalled ? <Text style={styles.stall}>Buffering</Text> : null}
      {snapshot.error !== undefined ? (
        <Text accessibilityRole="alert" style={styles.error}>
          {snapshot.error}
        </Text>
      ) : null}
    </View>
  );
}

function formatTime(positionMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(positionMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

const styles = StyleSheet.create({
  bar: {
    backgroundColor: theme.control,
    padding: 12,
    gap: 8,
  },
  button: {
    alignSelf: "flex-start",
    backgroundColor: theme.background,
    borderColor: theme.text,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  label: {
    color: theme.text,
  },
  seek: {
    justifyContent: "center",
    minHeight: 44,
  },
  track: {
    backgroundColor: theme.background,
    height: 4,
    overflow: "hidden",
  },
  progress: {
    backgroundColor: theme.accent,
    height: 4,
  },
  time: {
    color: theme.text,
  },
  stall: {
    color: theme.text,
  },
  error: {
    color: theme.danger,
  },
});
