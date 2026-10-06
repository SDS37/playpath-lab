import Hls from "hls.js";
import shaka from "shaka-player";
import { chooseEngine } from "./chooseEngine";
import { clearKeyLicenseUrl, drmServers } from "./drmServers";
import { rewriteClearKeyPlaylist } from "./hlsClearKey";

export type PlaybackState = "playing" | "paused" | "seeking" | "ended";

export type PlaybackSnapshot = {
  playbackState: PlaybackState;
  stalled: boolean;
  positionMs: number;
  durationMs: number;
  error: string | undefined;
};

const videoEvents = [
  "play",
  "pause",
  "playing",
  "waiting",
  "seeking",
  "seeked",
  "ended",
  "durationchange",
  "timeupdate",
] as const;

export const initialSnapshot: PlaybackSnapshot = {
  playbackState: "paused",
  stalled: false,
  positionMs: 0,
  durationMs: 0,
  error: undefined,
};

export class PlaybackSession {
  #video: HTMLVideoElement;
  #player: shaka.Player | null = null;
  #hls: Hls | null = null;
  #native = false;
  #nativeGeneration = 0;
  #generation = 0;
  #bound = false;
  #listeners = new Set<(snapshot: PlaybackSnapshot) => void>();
  #snapshot: PlaybackSnapshot = initialSnapshot;
  #onVideo = (): void => {
    this.#publishFromVideo();
  };
  #onNativeError = (): void => {
    if (!this.#native || this.#nativeGeneration !== this.#generation) {
      return;
    }
    this.#fail(this.#video.error);
  };

  constructor(video: HTMLVideoElement) {
    this.#video = video;
  }

  subscribe(listener: (snapshot: PlaybackSnapshot) => void): () => void {
    this.#listeners.add(listener);
    listener(this.#snapshot);
    return () => {
      this.#listeners.delete(listener);
    };
  }

  async load(manifestUrl: string): Promise<void> {
    this.#generation += 1;
    const generation = this.#generation;
    await this.#releasePlayer();
    if (generation !== this.#generation) {
      return;
    }
    this.#set({ ...initialSnapshot });

    const choice = chooseEngine(manifestUrl, {
      hlsJs: Hls.isSupported(),
      nativeHls:
        this.#video.canPlayType("application/vnd.apple.mpegurl") !== "",
      safari: navigator.vendor === "Apple Computer, Inc.",
    });
    if (choice === "hlsjs") {
      this.#loadHlsJs(manifestUrl, generation);
      return;
    }
    if (choice === "nativeHls") {
      this.#loadNativeHls(manifestUrl, generation);
      return;
    }
    if (choice === undefined) {
      this.#set({
        ...this.#snapshot,
        error: "This browser cannot play the title.",
      });
      return;
    }

    shaka.polyfill.installAll();
    if (!shaka.Player.isBrowserSupported()) {
      this.#set({
        ...this.#snapshot,
        error: "This browser cannot play the title.",
      });
      return;
    }

    const player = new shaka.Player();
    this.#player = player;
    try {
      await player.attach(this.#video);
      if (generation !== this.#generation) {
        return;
      }
      const applied = player.configure({
        drm: {
          servers: {
            ...drmServers(),
            "com.widevine.alpha": clearKeyLicenseUrl,
          },
          // Shaka does not map the lab HLS key format to Clear Key. The playlist
          // rewrite below presents that same key id as a format Shaka does map,
          // and this sends the license request to org.w3.clearkey.
          keySystemsMapping: {
            "com.widevine.alpha": "org.w3.clearkey",
          },
          // The packaged init box uses the lab scheme id. The Clear Key CDM
          // only accepts the common system id, which the playlist rewrite supplies.
          parseInbandPsshEnabled: false,
        },
      });
      if (!applied) {
        this.#set({ ...this.#snapshot, error: "Playback failed." });
        return;
      }
      const network = player.getNetworkingEngine();
      if (network === null) {
        this.#set({ ...this.#snapshot, error: "Playback failed." });
        return;
      }
      network.registerResponseFilter((_type, response) => {
        if (!response.uri.endsWith(".m3u8")) {
          return;
        }
        const bytes = new Uint8Array(
          response.data instanceof ArrayBuffer
            ? response.data
            : response.data.buffer.slice(
                response.data.byteOffset,
                response.data.byteOffset + response.data.byteLength,
              ),
        );
        const next = rewriteClearKeyPlaylist(new TextDecoder().decode(bytes));
        response.data = new TextEncoder().encode(next);
      });
      player.addEventListener("error", (event) => {
        if (generation !== this.#generation) {
          return;
        }
        this.#fail(event);
      });
      player.addEventListener("buffering", (event) => {
        if (generation !== this.#generation) {
          return;
        }
        this.#set({ ...this.#snapshot, stalled: isBuffering(event) });
      });
      this.#bindVideo();
      await player.load(manifestUrl);
      if (generation !== this.#generation) {
        return;
      }
      this.#publishFromVideo();
    } catch (err) {
      if (generation !== this.#generation) {
        return;
      }
      this.#fail(err);
    }
  }

  play(): void {
    void this.#video.play().catch((err: unknown) => {
      this.#fail(err);
    });
  }

  pause(): void {
    this.#video.pause();
  }

  seek(positionMs: number): void {
    this.#video.currentTime = positionMs / 1000;
  }

  async destroy(): Promise<void> {
    this.#generation += 1;
    this.#unbindVideo();
    await this.#releasePlayer();
  }

  #loadHlsJs(manifestUrl: string, generation: number): void {
    const hls = new Hls();
    this.#hls = hls;
    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (generation !== this.#generation || !data.fatal) {
        return;
      }
      this.#fail(data);
    });
    hls.loadSource(manifestUrl);
    hls.attachMedia(this.#video);
    this.#bindVideo();
  }

  #loadNativeHls(manifestUrl: string, generation: number): void {
    this.#native = true;
    this.#nativeGeneration = generation;
    this.#video.addEventListener("error", this.#onNativeError);
    this.#video.src = manifestUrl;
    this.#bindVideo();
  }

  async #releasePlayer(): Promise<void> {
    const hls = this.#hls;
    this.#hls = null;
    if (hls) {
      hls.destroy();
    }
    const player = this.#player;
    this.#player = null;
    if (player) {
      await player.destroy();
    }
    if (this.#native) {
      this.#video.removeEventListener("error", this.#onNativeError);
      this.#native = false;
      this.#video.removeAttribute("src");
      this.#video.load();
    }
  }

  #bindVideo(): void {
    if (this.#bound) {
      return;
    }
    this.#bound = true;
    for (const name of videoEvents) {
      this.#video.addEventListener(name, this.#onVideo);
    }
  }

  #unbindVideo(): void {
    if (!this.#bound) {
      return;
    }
    this.#bound = false;
    for (const name of videoEvents) {
      this.#video.removeEventListener(name, this.#onVideo);
    }
  }

  #publishFromVideo(): void {
    const duration = this.#video.duration;
    this.#set({
      ...this.#snapshot,
      playbackState: stateOf(this.#video),
      stalled:
        this.#video.readyState < HTMLMediaElement.HAVE_FUTURE_DATA &&
        !this.#video.paused,
      positionMs: Math.round(this.#video.currentTime * 1000),
      durationMs: Number.isFinite(duration) ? Math.round(duration * 1000) : 0,
    });
  }

  #fail(err: unknown): void {
    const message =
      categoryOf(err) === shaka.util.Error.Category.DRM
        ? "The title cannot be played."
        : "Playback failed.";
    this.#set({
      ...this.#snapshot,
      error: message,
    });
  }

  #set(snapshot: PlaybackSnapshot): void {
    this.#snapshot = snapshot;
    for (const listener of this.#listeners) {
      listener(snapshot);
    }
  }
}

function stateOf(video: HTMLVideoElement): PlaybackState {
  if (video.ended) {
    return "ended";
  }
  if (video.paused) {
    return "paused";
  }
  if (video.seeking) {
    return "seeking";
  }
  return "playing";
}

function isBuffering(event: Event): boolean {
  if (!("buffering" in event)) {
    return false;
  }
  return event.buffering === true;
}

function categoryOf(err: unknown): number | undefined {
  if (typeof err !== "object" || err === null) {
    return undefined;
  }
  if ("detail" in err) {
    return categoryOf(err.detail);
  }
  if ("category" in err && typeof err.category === "number") {
    return err.category;
  }
  return undefined;
}
