import { useState } from "react";
import { Controls } from "./Controls";
import { protectedMenus, type ProtectedMenu } from "./protectedMenus";
import { usePlaybackSession } from "./usePlaybackSession";

export function PlayerScreen() {
  const [video, setVideo] = useState<HTMLVideoElement | null>(null);
  const [menu, setMenu] = useState<ProtectedMenu>("dash");
  const { snapshot, play, pause, seek } = usePlaybackSession(
    video,
    protectedMenus[menu],
  );

  return (
    <main className="player">
      <h1>playpath-bars</h1>
      <div className="menus">
        <button
          type="button"
          className="control"
          aria-pressed={menu === "dash"}
          onClick={() => {
            setMenu("dash");
          }}
        >
          DASH
        </button>
        <button
          type="button"
          className="control"
          aria-pressed={menu === "hls"}
          onClick={() => {
            setMenu("hls");
          }}
        >
          HLS
        </button>
      </div>
      <video ref={setVideo} className="picture" playsInline />
      <Controls
        snapshot={snapshot}
        onPlay={play}
        onPause={pause}
        onSeek={seek}
      />
    </main>
  );
}
