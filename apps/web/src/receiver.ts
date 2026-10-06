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
};

/** The desktop page cannot play here. Certification is a different runtime. */
export class ReceiverUnsupported extends Error {
  constructor() {
    super("This browser cannot play the title.");
    this.name = "ReceiverUnsupported";
  }
}

let current: ReceiverPlayer | undefined;

export async function loadReceiver(
  video: HTMLMediaElement,
  createPlayer: () => ReceiverPlayer = createShakaPlayer,
): Promise<void> {
  const player = createPlayer();
  current = player;
  try {
    await player.attach(video);
    const applied = player.configure({
      drm: { servers: { ...drmServers() } },
    });
    if (!applied) {
      throw new Error("configure");
    }
    await player.load(protectedMenus.dash);
  } catch (err) {
    await destroyCurrent();
    throw err;
  }
}

export async function stopReceiver(): Promise<void> {
  await destroyCurrent();
}

export function receiverFailure(err: unknown): string {
  if (err instanceof ReceiverUnsupported) {
    return err.message;
  }
  if (categoryOf(err) === shaka.util.Error.Category.DRM) {
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

async function destroyCurrent(): Promise<void> {
  const player = current;
  current = undefined;
  if (player !== undefined) {
    await player.destroy();
  }
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
