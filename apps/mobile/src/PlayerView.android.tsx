import { forwardRef } from "react";
import {
  PlayerSurface,
  type PlayerCommands,
  type PlayerSurfaceProps,
} from "./PlayerSurface";

type PlayerViewProps = Omit<PlayerSurfaceProps, "manifestUrl">;

/** Protected DASH. Clear Key stays inside the Media3 view. */
const DASH_MANIFEST = "http://127.0.0.1:8080/manifest.mpd";

export const PlayerView = forwardRef<PlayerCommands, PlayerViewProps>(
  function PlayerView(props, ref) {
    return <PlayerSurface ref={ref} {...props} manifestUrl={DASH_MANIFEST} />;
  },
);
