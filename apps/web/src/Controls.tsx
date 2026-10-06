import type { PlaybackSnapshot } from "./PlaybackSession";

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
  const progress =
    snapshot.durationMs === 0
      ? "0%"
      : `${Math.min(100, (snapshot.positionMs / snapshot.durationMs) * 100)}%`;

  return (
    <div
      className="control-bar"
      data-stalled={snapshot.stalled ? "true" : "false"}
      style={{ "--progress": progress }}
    >
      <button
        type="button"
        className="control"
        onClick={showPause ? onPause : onPlay}
      >
        {showPause ? "Pause" : "Play"}
      </button>
      <input
        className="control seek"
        type="range"
        min={0}
        max={snapshot.durationMs}
        value={Math.min(snapshot.positionMs, snapshot.durationMs)}
        aria-label="Seek"
        aria-valuetext={formatTime(snapshot.positionMs)}
        onChange={(event) => {
          onSeek(Number(event.target.value));
        }}
      />
      <span className="time">
        {formatTime(snapshot.positionMs)} / {formatTime(snapshot.durationMs)}
      </span>
      {snapshot.stalled ? <span className="stall">Buffering</span> : null}
      {snapshot.error !== undefined ? (
        <p className="error" role="alert">
          {snapshot.error}
        </p>
      ) : null}
    </div>
  );
}

function formatTime(positionMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(positionMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}
