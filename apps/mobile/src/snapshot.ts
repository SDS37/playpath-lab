export type PlaybackState = "playing" | "paused" | "seeking" | "ended";

/** The latest engine snapshot. Controls draw this and do not read the player. */
export type PlaybackSnapshot = {
  playbackState: PlaybackState;
  stalled: boolean;
  adPlaying: boolean;
  positionMs: number;
  durationMs: number;
  error: string | undefined;
};

export const initialSnapshot: PlaybackSnapshot = {
  playbackState: "paused",
  stalled: false,
  adPlaying: false,
  positionMs: 0,
  durationMs: 0,
  error: undefined,
};

export type SnapshotPayload = {
  playbackState: string;
  stalled: boolean;
  adPlaying: boolean;
  positionMs: number;
  durationMs: number;
  error: string;
};

export function snapshotFromPayload(payload: SnapshotPayload): PlaybackSnapshot {
  return {
    playbackState: playbackStateOf(payload.playbackState),
    stalled: payload.stalled,
    adPlaying: payload.adPlaying,
    positionMs: Math.max(0, payload.positionMs),
    durationMs: Math.max(0, payload.durationMs),
    error: payload.error === "" ? undefined : payload.error,
  };
}

function playbackStateOf(value: string): PlaybackState {
  if (
    value === "playing" ||
    value === "paused" ||
    value === "seeking" ||
    value === "ended"
  ) {
    return value;
  }
  return "paused";
}
