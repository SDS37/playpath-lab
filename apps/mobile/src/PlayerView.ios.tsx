import { forwardRef } from "react";
import {
  PlayerSurface,
  type PlayerCommands,
  type PlayerSurfaceProps,
} from "./PlayerSurface";

type PlayerViewProps = Omit<PlayerSurfaceProps, "manifestUrl">;

/** Clear HLS. This play does not open a DRM session. */
const HLS_MANIFEST = "http://127.0.0.1:8084/master.m3u8";

export const PlayerView = forwardRef<PlayerCommands, PlayerViewProps>(
  function PlayerView(props, ref) {
    return <PlayerSurface ref={ref} {...props} manifestUrl={HLS_MANIFEST} />;
  },
);
