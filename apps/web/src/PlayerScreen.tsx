import { useState } from "react";
import { clearHlsMenu } from "./clearHlsMenu";
import { Controls } from "./Controls";
import { protectedMenus } from "./protectedMenus";
import { usePlaybackSession } from "./usePlaybackSession";

const menus = {
  dash: protectedMenus.dash,
  hls: protectedMenus.hls,
  clearHls: clearHlsMenu,
} as const;

type MenuName = keyof typeof menus;

const menuLabels: Record<MenuName, string> = {
  dash: "DASH",
  hls: "HLS",
  clearHls: "Clear HLS",
};

export function PlayerScreen() {
  const [video, setVideo] = useState<HTMLVideoElement | null>(null);
  const [menu, setMenu] = useState<MenuName>("dash");
  const { snapshot, play, pause, seek } = usePlaybackSession(
    video,
    menus[menu],
  );

  return (
    <main className="player">
      <h1>playpath-bars</h1>
      <div className="menus">
        {(Object.keys(menus) as MenuName[]).map((name) => (
          <button
            key={name}
            type="button"
            className="control"
            aria-pressed={menu === name}
            onClick={() => {
              setMenu(name);
            }}
          >
            {menuLabels[name]}
          </button>
        ))}
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
