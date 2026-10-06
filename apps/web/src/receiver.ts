import shaka from "shaka-player";
import { drmServers } from "./drmServers";
import { protectedMenus } from "./protectedMenus";

export type ReceiverPlayer = {
  attach(video: HTMLMediaElement): Promise<void>;
  configure(config: {
    drm: { servers: { "org.w3.clearkey": string } };
  }): boolean;
  load(manifestUrl: string): Promise<unknown>;
  destroy(): Promise<void>;
  addEventListener?(type: "error", listener: (event: Event) => void): void;
};

export class ReceiverUnsupported extends Error {
  constructor() {
    super("This browser cannot play the title.");
    this.name = "ReceiverUnsupported";
  }
}

export class ReceiverSuperseded extends Error {
  constructor() {
    super("superseded");
    this.name = "ReceiverSuperseded";
  }
}

let current: ReceiverPlayer | undefined;
let generation = 0;

export async function loadReceiver(
  video: HTMLMediaElement,
  createPlayer: () => ReceiverPlayer = createShakaPlayer,
  onError?: (err: unknown) => void,
): Promise<void> {
  const token = ++generation;
  await releaseCurrent();
  if (token !== generation) {
    throw new ReceiverSuperseded();
  }
  const player = createPlayer();
  current = player;
  player.addEventListener?.("error", (event) => {
    if (current !== player || !isCritical(event)) {
      return;
    }
    onError?.(event);
  });
  try {
    await player.attach(video);
    if (token !== generation) {
      throw new ReceiverSuperseded();
    }
    const applied = player.configure({
      drm: { servers: { ...drmServers() } },
    });
    if (!applied) {
      throw new Error("configure");
    }
    await player.load(protectedMenus.dash);
    if (token !== generation) {
      throw new ReceiverSuperseded();
    }
  } catch (err) {
    await releasePlayer(player);
    throw err;
  }
}

export async function stopReceiver(): Promise<void> {
  generation += 1;
  await releaseCurrent();
}

export function receiverFailure(err: unknown): string {
  if (err instanceof ReceiverUnsupported) {
    return err.message;
  }
  if (numberField(err, "category") === shaka.util.Error.Category.DRM) {
    return "The title cannot be played.";
  }
  return "Playback failed.";
}

function createShakaPlayer(): ReceiverPlayer {
  shaka.polyfill.installAll();
  if (!shaka.Player.isBrowserSupported()) {
    throw new ReceiverUnsupported();
  }
  return new shaka.Player();
}

async function releaseCurrent(): Promise<void> {
  const player = current;
  if (player === undefined) {
    return;
  }
  await releasePlayer(player);
}

async function releasePlayer(player: ReceiverPlayer): Promise<void> {
  if (current === player) {
    current = undefined;
  }
  await player.destroy().catch(() => undefined);
}

function isCritical(err: unknown): boolean {
  return numberField(err, "severity") === shaka.util.Error.Severity.CRITICAL;
}

function numberField(
  err: unknown,
  name: "category" | "severity",
  depth = 0,
): number | undefined {
  if (depth > 4 || typeof err !== "object" || err === null) {
    return undefined;
  }
  if ("detail" in err && err.detail !== err) {
    const nested = numberField(err.detail, name, depth + 1);
    if (nested !== undefined) {
      return nested;
    }
  }
  const value: unknown = (err as Record<string, unknown>)[name];
  if (typeof value === "number") {
    return value;
  }
  return undefined;
}
