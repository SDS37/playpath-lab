import Hls from "hls.js";
import shaka from "shaka-player";
import {
  adEvent,
  bitrateEvent,
  drmCodeOf,
  drmEvent,
  startupEvent,
  type BitrateEngine,
} from "./bitrateEvent";
import { chooseEngine } from "./chooseEngine";
import { clearKeyLicenseUrl, drmServers } from "./drmServers";
import { rewriteClearKeyPlaylist } from "./hlsClearKey";
import { fetchMidroll, playingAtCue } from "./midroll";

export type PlaybackState = "playing" | "paused" | "seeking" | "ended";

type EngineKind = "shaka" | "hlsjs" | "native";

type AdPhase = "off" | "creative" | "resume";

export type PlaybackSnapshot = {
  playbackState: PlaybackState;
  stalled: boolean;
  adPlaying: boolean;
  positionMs: number;
  durationMs: number;
  height: number | undefined;
  bandwidthBps: number | undefined;
  captions: boolean;
  error: string | undefined;
};

const metadataTimeoutMs = 5000;

type NativeAudioTrack = {
  language: string;
  enabled: boolean;
};

type NativeAudioTrackList = {
  readonly length: number;
  [index: number]: NativeAudioTrack | undefined;
  addEventListener(type: "addtrack", listener: () => void): void;
  removeEventListener(type: "addtrack", listener: () => void): void;
};

function nativeAudioTracks(
  video: HTMLVideoElement,
): NativeAudioTrackList | undefined {
  const host = video as HTMLVideoElement & {
    audioTracks?: NativeAudioTrackList;
  };
  return host.audioTracks;
}

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
  adPlaying: false,
  positionMs: 0,
  durationMs: 0,
  height: undefined,
  bandwidthBps: undefined,
  captions: true,
  error: undefined,
};

export class PlaybackSession {
  #video: HTMLVideoElement;
  #player: shaka.Player | null = null;
  #hls: Hls | null = null;
  #native = false;
  #nativeGeneration = 0;
  #generation = 0;
  #sessionId = "";
  #shakaBuffering = false;
  #manifestUrl = "";
  #engine: EngineKind | undefined = undefined;
  #cueMs: number | undefined = undefined;
  #creativeUrl: string | undefined = undefined;
  #adPlayed = false;
  #adPhase: AdPhase = "off";
  #adAttempt = 0;
  #creativeAssigned = false;
  #creativeStarted = false;
  #playWhenReady = false;
  #captions = true;
  #loadStartedMs = 0;
  #firstFrameMs: number | undefined = undefined;
  #startupLogged = false;
  #drmLogged = false;
  #bound = false;
  #listeners = new Set<(snapshot: PlaybackSnapshot) => void>();
  #snapshot: PlaybackSnapshot = initialSnapshot;
  #onPlaying = (): void => {
    this.#noteStartup();
  };
  #onVideo = (): void => {
    if (this.#adPhase === "resume") {
      return;
    }
    if (this.#adPhase === "creative") {
      this.#publishFromVideo();
      return;
    }
    if (this.#crossedCue()) {
      void this.#playCreative();
      return;
    }
    this.#publishFromVideo();
  };
  #onCreativeError = (): void => {
    if (this.#adPhase !== "creative" || !this.#creativeAssigned) {
      return;
    }
    const src = this.#video.currentSrc;
    if (src !== "" && src !== this.#creativeUrl) {
      return;
    }
    void this.#resumeFilm(false);
  };
  #onCreativeEnded = (): void => {
    if (this.#adPhase !== "creative" || !this.#creativeStarted) {
      return;
    }
    if (this.#video.currentSrc !== this.#creativeUrl || !this.#video.ended) {
      return;
    }
    void this.#resumeFilm(true);
  };
  #onFirstFrame = (): void => {
    if (this.#firstFrameMs !== undefined || this.#adPhase !== "off") {
      return;
    }
    if (this.#video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
      return;
    }
    this.#firstFrameMs = performance.now();
  };
  #onNativeError = (): void => {
    if (
      !this.#native ||
      this.#nativeGeneration !== this.#generation ||
      this.#adPhase !== "off"
    ) {
      return;
    }
    this.#fail(this.#video.error);
  };
  #onTextTrack = (): void => {
    if (this.#engine !== "native" || this.#adPhase === "creative") {
      return;
    }
    this.#applyCaptions();
    this.#applyAudio();
  };
  #onAudioTrack = (): void => {
    if (this.#engine !== "native" || this.#adPhase === "creative") {
      return;
    }
    this.#applyAudio();
  };
  #onNativeResize = (): void => {
    if (!this.#native || this.#nativeGeneration !== this.#generation) {
      return;
    }
    if (this.#adPhase === "creative") {
      return;
    }
    const height = this.#video.videoHeight;
    if (height > 0 && height !== this.#snapshot.height) {
      this.#set({ ...this.#snapshot, height, bandwidthBps: undefined });
    }
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
    this.#sessionId = crypto.randomUUID();
    this.#loadStartedMs = performance.now();
    this.#firstFrameMs = undefined;
    this.#startupLogged = false;
    this.#drmLogged = false;
    this.#shakaBuffering = false;
    this.#manifestUrl = manifestUrl;
    this.#engine = undefined;
    this.#cueMs = undefined;
    this.#creativeUrl = undefined;
    this.#adPlayed = false;
    this.#adPhase = "off";
    this.#adAttempt += 1;
    this.#creativeAssigned = false;
    this.#creativeStarted = false;
    this.#playWhenReady = false;
    await this.#releasePlayer();
    if (generation !== this.#generation) {
      return;
    }
    this.#set({ ...initialSnapshot, captions: this.#captions });
    await this.#readCue(generation);
    if (generation !== this.#generation) {
      return;
    }

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
    this.#engine = "shaka";
    try {
      await player.attach(this.#video);
      if (generation !== this.#generation) {
        return;
      }
      const frame = this.#video.parentElement;
      player.setVideoContainer(frame);
      const applied = player.configure({
        textDisplayFactory: (
          active: shaka.Player,
        ): shaka.extern.TextDisplayer =>
          frame === null
            ? new shaka.text.NativeTextDisplayer(active)
            : new shaka.text.UITextDisplayer(active),
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
        if (generation !== this.#generation || this.#adPhase !== "off") {
          return;
        }
        this.#fail(event);
      });
      player.addEventListener("buffering", (event) => {
        if (generation !== this.#generation || this.#adPhase !== "off") {
          return;
        }
        this.#shakaBuffering = isBuffering(event);
        this.#publishFromVideo();
      });
      player.addEventListener("adaptation", () => {
        if (generation !== this.#generation || this.#adPhase === "creative") {
          return;
        }
        this.#noteShaka(player);
      });
      this.#bindVideo();
      await player.load(manifestUrl);
      if (generation !== this.#generation) {
        return;
      }
      this.#noteShaka(player);
      this.#applyCaptions();
      this.#applyAudio();
      this.#publishFromVideo();
    } catch (err) {
      if (generation !== this.#generation) {
        return;
      }
      this.#fail(err);
    }
  }

  play(): void {
    this.#playWhenReady = true;
    void this.#video.play().catch((err: unknown) => {
      if (this.#adPhase !== "off") {
        return;
      }
      this.#fail(err);
    });
  }

  pause(): void {
    this.#playWhenReady = false;
    this.#video.pause();
  }

  seek(positionMs: number): void {
    if (this.#adPhase !== "off") {
      return;
    }
    this.#video.currentTime = positionMs / 1000;
  }

  setCaptions(enabled: boolean): void {
    this.#captions = enabled;
    this.#applyCaptions();
    this.#applyAudio();
    this.#set({ ...this.#snapshot, captions: enabled });
  }

  async destroy(): Promise<void> {
    this.#generation += 1;
    this.#unbindVideo();
    await this.#releasePlayer();
  }

  #loadHlsJs(manifestUrl: string, generation: number): void {
    const hls = new Hls();
    this.#hls = hls;
    this.#engine = "hlsjs";
    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (
        generation !== this.#generation ||
        this.#adPhase !== "off" ||
        !data.fatal
      ) {
        return;
      }
      this.#fail(data);
    });
    hls.on(Hls.Events.LEVEL_SWITCHED, (_event, data) => {
      if (generation !== this.#generation || this.#adPhase === "creative") {
        return;
      }
      const level = hls.levels[data.level];
      if (level === undefined) {
        return;
      }
      this.#noteRendition("hlsjs", level.height, level.bitrate, level.codecs);
    });
    hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED, () => {
      if (generation !== this.#generation || this.#adPhase === "creative") {
        return;
      }
      this.#applyCaptions();
    });
    hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, () => {
      if (generation !== this.#generation || this.#adPhase === "creative") {
        return;
      }
      this.#applyAudio();
    });
    hls.loadSource(manifestUrl);
    hls.attachMedia(this.#video);
    this.#bindVideo();
    this.#applyCaptions();
    this.#applyAudio();
  }

  #loadNativeHls(manifestUrl: string, generation: number): void {
    this.#engine = "native";
    this.#native = true;
    this.#nativeGeneration = generation;
    this.#video.addEventListener("error", this.#onNativeError);
    this.#video.addEventListener("resize", this.#onNativeResize);
    this.#video.textTracks.addEventListener("addtrack", this.#onTextTrack);
    const audioTracks = nativeAudioTracks(this.#video);
    if (audioTracks !== undefined) {
      audioTracks.addEventListener("addtrack", this.#onAudioTrack);
    }
    this.#video.src = manifestUrl;
    this.#bindVideo();
    this.#applyCaptions();
    this.#applyAudio();
  }

  #applyCaptions(): void {
    if (this.#adPhase === "creative") {
      return;
    }
    const player = this.#player;
    if (player !== null) {
      if (!this.#captions) {
        player.selectTextTrack(null);
        return;
      }
      const tracks = player.getTextTracks();
      const track =
        tracks.find(
          (item) => item.language === "en" || item.language === "eng",
        ) ?? tracks[0];
      if (track !== undefined) {
        player.selectTextTrack(track);
      }
      return;
    }
    const hls = this.#hls;
    if (hls !== null) {
      hls.subtitleDisplay = this.#captions;
      if (!this.#captions) {
        hls.subtitleTrack = -1;
        return;
      }
      const english = hls.subtitleTracks.findIndex(
        (item) =>
          item.lang === "en" || item.lang === "eng" || item.name === "English",
      );
      if (hls.subtitleTracks.length > 0) {
        hls.subtitleTrack = english >= 0 ? english : 0;
      }
      return;
    }
    if (!this.#native) {
      return;
    }
    const mode = this.#captions ? "showing" : "disabled";
    const tracks = this.#video.textTracks;
    for (let index = 0; index < tracks.length; index += 1) {
      const track = tracks[index];
      if (track === undefined) {
        continue;
      }
      if (track.kind !== "subtitles" && track.kind !== "captions") {
        continue;
      }
      track.mode = mode;
    }
  }

  #applyAudio(): void {
    if (this.#adPhase === "creative") {
      return;
    }
    const player = this.#player;
    if (player !== null) {
      const tracks = player.getAudioTracks();
      const track =
        tracks.find(
          (item) => item.language === "en" || item.language === "eng",
        ) ?? tracks[0];
      if (track !== undefined && !track.active) {
        player.selectAudioTrack(track);
      }
      return;
    }
    const hls = this.#hls;
    if (hls !== null) {
      const english = hls.audioTracks.findIndex(
        (item) =>
          item.lang === "en" || item.lang === "eng" || item.name === "English",
      );
      if (english >= 0 && hls.audioTrack !== english) {
        hls.audioTrack = english;
      }
      return;
    }
    if (!this.#native) {
      return;
    }
    const tracks = nativeAudioTracks(this.#video);
    if (tracks === undefined) {
      return;
    }
    let chosen = -1;
    for (let index = 0; index < tracks.length; index += 1) {
      const track = tracks[index];
      if (track === undefined) {
        continue;
      }
      const language = track.language.toLowerCase();
      if (
        language === "en" ||
        language === "eng" ||
        language.startsWith("en-")
      ) {
        chosen = index;
        break;
      }
    }
    if (chosen < 0 && tracks.length > 0) {
      chosen = 0;
    }
    const selected = chosen >= 0 ? tracks[chosen] : undefined;
    if (selected !== undefined && !selected.enabled) {
      selected.enabled = true;
    }
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
    this.#video.removeEventListener("error", this.#onCreativeError);
    this.#video.removeEventListener("ended", this.#onCreativeEnded);
    if (this.#native) {
      this.#video.removeEventListener("error", this.#onNativeError);
      this.#video.removeEventListener("resize", this.#onNativeResize);
      this.#video.textTracks.removeEventListener("addtrack", this.#onTextTrack);
      nativeAudioTracks(this.#video)?.removeEventListener(
        "addtrack",
        this.#onAudioTrack,
      );
      this.#native = false;
      this.#video.removeAttribute("src");
      this.#video.load();
    } else if (this.#video.getAttribute("src") !== null) {
      this.#video.removeAttribute("src");
      this.#video.load();
    }
  }

  #bindVideo(): void {
    if (this.#bound) {
      return;
    }
    this.#bound = true;
    // `playing` is registered first so startup is logged before a cue starts the ad.
    this.#video.addEventListener("playing", this.#onPlaying);
    this.#video.addEventListener("loadeddata", this.#onFirstFrame);
    for (const name of videoEvents) {
      this.#video.addEventListener(name, this.#onVideo);
    }
    this.#onFirstFrame();
  }

  #unbindVideo(): void {
    if (!this.#bound) {
      return;
    }
    this.#bound = false;
    this.#video.removeEventListener("playing", this.#onPlaying);
    this.#video.removeEventListener("loadeddata", this.#onFirstFrame);
    for (const name of videoEvents) {
      this.#video.removeEventListener(name, this.#onVideo);
    }
  }

  #noteShaka(player: shaka.Player): void {
    const active = player.getVariantTracks().find((track) => track.active);
    if (active === undefined) {
      return;
    }
    this.#noteRendition(
      "shaka",
      active.height ?? undefined,
      active.bandwidth,
      active.codecs ?? undefined,
    );
  }

  #noteRendition(
    engine: BitrateEngine,
    height: number | undefined,
    bandwidthBps: number | undefined,
    codecs: string | undefined,
  ): void {
    if (this.#adPhase === "creative") {
      return;
    }
    const nextHeight = height !== undefined && height > 0 ? height : undefined;
    const nextBandwidth =
      bandwidthBps !== undefined && bandwidthBps > 0 ? bandwidthBps : undefined;
    if (nextHeight === undefined && nextBandwidth === undefined) {
      return;
    }
    if (
      nextHeight === this.#snapshot.height &&
      nextBandwidth === this.#snapshot.bandwidthBps
    ) {
      return;
    }
    this.#set({
      ...this.#snapshot,
      height: nextHeight,
      bandwidthBps: nextBandwidth,
    });
    console.info(
      bitrateEvent({
        engine,
        sessionId: this.#sessionId,
        at: utcNow(),
        positionMs: Math.round(this.#video.currentTime * 1000),
        height: nextHeight,
        bandwidthBps: nextBandwidth,
        codecs,
      }),
    );
  }

  #noteStartup(): void {
    if (this.#startupLogged || this.#adPhase !== "off") {
      return;
    }
    const engine = this.#engine;
    if (engine !== "shaka" && engine !== "hlsjs") {
      return;
    }
    this.#startupLogged = true;
    const positionMs = Math.round(this.#video.currentTime * 1000);
    const frameAt = this.#firstFrameMs ?? performance.now();
    console.info(
      startupEvent({
        engine,
        sessionId: this.#sessionId,
        at: utcNow(),
        positionMs,
        startupMs: frameAt - this.#loadStartedMs,
        manifestUrl: this.#manifestUrl,
      }),
    );
    if (engine === "shaka" && !this.#drmLogged) {
      this.#drmLogged = true;
      console.info(
        drmEvent({
          engine,
          sessionId: this.#sessionId,
          at: utcNow(),
          positionMs,
          result: "ok",
          code: "",
        }),
      );
    }
  }

  #logAd(action: "start" | "complete" | "error"): void {
    const engine = this.#engine;
    if (engine !== "shaka" && engine !== "hlsjs") {
      return;
    }
    console.info(
      adEvent({
        engine,
        sessionId: this.#sessionId,
        at: utcNow(),
        positionMs: this.#cueMs ?? 0,
        action,
      }),
    );
  }

  #publishFromVideo(): void {
    const duration = this.#video.duration;
    const adPlaying = this.#adPhase !== "off";
    this.#set({
      ...this.#snapshot,
      playbackState: stateOf(this.#video),
      stalled:
        this.#shakaBuffering ||
        (this.#video.readyState < HTMLMediaElement.HAVE_FUTURE_DATA &&
          !this.#video.paused),
      adPlaying,
      positionMs: Math.round(this.#video.currentTime * 1000),
      durationMs: Number.isFinite(duration) ? Math.round(duration * 1000) : 0,
    });
  }

  async #readCue(generation: number): Promise<void> {
    const midroll = await fetchMidroll();
    if (generation !== this.#generation || midroll === undefined) {
      return;
    }
    this.#cueMs = midroll.cueMs;
    this.#creativeUrl = midroll.mediaUrl;
  }

  #crossedCue(): boolean {
    if (this.#adPlayed || this.#adPhase !== "off") {
      return false;
    }
    if (this.#cueMs === undefined || this.#creativeUrl === undefined) {
      return false;
    }
    return playingAtCue(
      this.#video.currentTime * 1000,
      this.#cueMs,
      this.#video.paused,
      this.#video.ended,
    );
  }

  async #playCreative(): Promise<void> {
    if (this.#adPlayed || this.#adPhase !== "off") {
      return;
    }
    const url = this.#creativeUrl;
    const engine = this.#engine;
    if (url === undefined || engine === undefined) {
      return;
    }
    this.#adPlayed = true;
    this.#adPhase = "creative";
    this.#creativeAssigned = false;
    this.#shakaBuffering = false;
    const generation = this.#generation;
    const attempt = this.#adAttempt;
    this.#video.addEventListener("error", this.#onCreativeError);
    this.#video.addEventListener("ended", this.#onCreativeEnded);
    try {
      if (engine === "shaka" && this.#player !== null) {
        await this.#player.detach();
      } else if (engine === "hlsjs" && this.#hls !== null) {
        this.#hls.stopLoad();
        this.#hls.detachMedia();
      }
      if (!this.#ownsCreative(generation, attempt)) {
        return;
      }
      this.#video.src = url;
      this.#creativeAssigned = true;
      const ready = await this.#waitForMetadata(generation, true);
      if (!this.#ownsCreative(generation, attempt)) {
        return;
      }
      if (!ready) {
        await this.#resumeFilm(false);
        return;
      }
      this.#creativeStarted = true;
      this.#publishFromVideo();
      await this.#video.play();
      if (!this.#ownsCreative(generation, attempt)) {
        return;
      }
      this.#logAd("start");
    } catch {
      if (!this.#ownsCreative(generation, attempt)) {
        return;
      }
      await this.#resumeFilm(false);
    }
  }

  #ownsCreative(generation: number, attempt: number): boolean {
    return (
      generation === this.#generation &&
      attempt === this.#adAttempt &&
      this.#adPhase === "creative"
    );
  }

  async #resumeFilm(completed: boolean): Promise<void> {
    if (this.#adPhase !== "creative") {
      return;
    }
    this.#logAd(completed ? "complete" : "error");
    this.#adAttempt += 1;
    this.#adPhase = "resume";
    this.#creativeAssigned = false;
    this.#creativeStarted = false;
    this.#video.removeEventListener("error", this.#onCreativeError);
    this.#video.removeEventListener("ended", this.#onCreativeEnded);
    const generation = this.#generation;
    const cueSec = (this.#cueMs ?? 0) / 1000;
    this.#video.pause();
    this.#video.removeAttribute("src");
    this.#video.load();
    try {
      const engine = this.#engine;
      let restored = false;
      if (engine === "shaka" && this.#player !== null) {
        await this.#player.attach(this.#video);
        if (generation !== this.#generation) {
          return;
        }
        await this.#player.load(this.#manifestUrl, cueSec);
        if (generation !== this.#generation) {
          return;
        }
        this.#video.currentTime = cueSec;
        restored = true;
      } else if (engine === "hlsjs" && this.#hls !== null) {
        this.#hls.attachMedia(this.#video);
        this.#hls.startLoad(cueSec);
        if (!(await this.#filmReady(generation))) {
          return;
        }
        this.#video.currentTime = cueSec;
        restored = true;
      } else if (engine === "native") {
        this.#video.src = this.#manifestUrl;
        if (!(await this.#filmReady(generation, true))) {
          return;
        }
        this.#video.currentTime = cueSec;
        restored = true;
      }
      if (restored && generation === this.#generation) {
        this.#applyCaptions();
        this.#applyAudio();
      }
      if (!restored || generation !== this.#generation) {
        this.#unlockAd(generation);
        return;
      }
      this.#adPhase = "off";
      this.#publishFromVideo();
      if (this.#playWhenReady) {
        await this.#video.play();
      }
    } catch (err) {
      if (generation !== this.#generation) {
        return;
      }
      this.#adPhase = "off";
      this.#fail(err);
    }
  }

  async #filmReady(generation: number, nextEvent = false): Promise<boolean> {
    const ready = await this.#waitForMetadata(generation, nextEvent);
    if (generation !== this.#generation) {
      return false;
    }
    if (!ready) {
      this.#adPhase = "off";
      this.#fail(new Error("playback"));
    }
    return ready;
  }

  #unlockAd(generation: number): void {
    if (generation !== this.#generation || this.#adPhase === "off") {
      return;
    }
    this.#adPhase = "off";
    this.#fail(new Error("playback"));
  }

  #waitForMetadata(generation: number, nextEvent = false): Promise<boolean> {
    if (
      !nextEvent &&
      this.#video.readyState >= HTMLMediaElement.HAVE_METADATA
    ) {
      return Promise.resolve(generation === this.#generation);
    }
    return new Promise((resolve) => {
      let settled = false;
      const finish = (ready: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        this.#video.removeEventListener("loadedmetadata", onMetadata);
        resolve(ready && generation === this.#generation);
      };
      const onMetadata = (): void => {
        finish(true);
      };
      const timer = setTimeout(() => {
        finish(false);
      }, metadataTimeoutMs);
      this.#video.addEventListener("loadedmetadata", onMetadata);
    });
  }

  #fail(err: unknown): void {
    const drmFailed = categoryOf(err) === shaka.util.Error.Category.DRM;
    if (drmFailed && this.#engine === "shaka" && !this.#drmLogged) {
      this.#drmLogged = true;
      console.info(
        drmEvent({
          engine: "shaka",
          sessionId: this.#sessionId,
          at: utcNow(),
          positionMs: Math.round(this.#video.currentTime * 1000),
          result: "error",
          code: drmCodeOf(err),
        }),
      );
    }
    const message = drmFailed
      ? "The title cannot be played."
      : "Playback failed.";
    this.#set({
      ...this.#snapshot,
      adPlaying: this.#adPhase !== "off",
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

function utcNow(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
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
