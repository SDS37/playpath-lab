import { useEffect, useRef, useState } from "react";
import {
  initialSnapshot,
  PlaybackSession,
  type PlaybackSnapshot,
} from "./PlaybackSession";

export function usePlaybackSession(
  video: HTMLVideoElement | null,
  manifestUrl: string,
): {
  snapshot: PlaybackSnapshot;
  play: () => void;
  pause: () => void;
  seek: (positionMs: number) => void;
  setCaptions: (enabled: boolean) => void;
} {
  const sessionRef = useRef<PlaybackSession | null>(null);
  const chainRef = useRef<Promise<void>>(Promise.resolve());
  const [snapshot, setSnapshot] = useState<PlaybackSnapshot>(initialSnapshot);

  useEffect(() => {
    if (video === null || manifestUrl === "") {
      return;
    }
    const session = new PlaybackSession(video);
    let active = true;
    sessionRef.current = session;
    const unsubscribe = session.subscribe((next) => {
      if (active) {
        setSnapshot(next);
      }
    });
    const loading = chainRef.current
      .catch(() => {
        // The next load still has to run after a rejected destroy.
        return undefined;
      })
      .then(async () => {
        if (!active) {
          return;
        }
        await session.load(manifestUrl);
      });
    chainRef.current = loading;
    return () => {
      active = false;
      unsubscribe();
      if (sessionRef.current === session) {
        sessionRef.current = null;
      }
      // Destroy starts now. A load blocked on the origin or the license
      // service must not hold the next menu behind it.
      const destroyed = session.destroy().catch(() => {
        // The next load still has to run after a rejected destroy.
        return undefined;
      });
      chainRef.current = destroyed;
      void loading.catch(() => {
        // Destroy can reject the load it cancelled.
        return undefined;
      });
    };
  }, [video, manifestUrl]);

  return {
    snapshot,
    play: () => {
      sessionRef.current?.play();
    },
    pause: () => {
      sessionRef.current?.pause();
    },
    seek: (positionMs: number) => {
      sessionRef.current?.seek(positionMs);
    },
    setCaptions: (enabled: boolean) => {
      sessionRef.current?.setCaptions(enabled);
    },
  };
}
