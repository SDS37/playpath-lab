import { describe, expect, it, vi } from "vitest";

vi.mock("shaka-player", () => ({
  default: {
    polyfill: { installAll: () => undefined },
    Player: class Player {
      static isBrowserSupported(): boolean {
        return true;
      }
    },
    util: {
      Error: {
        Category: { DRM: 6 },
        Severity: { CRITICAL: 2, RECOVERABLE: 1 },
      },
    },
  },
}));
import { clearKeyLicenseUrl } from "./drmServers";
import { protectedMenus } from "./protectedMenus";
import {
  loadReceiver,
  receiverFailure,
  ReceiverSuperseded,
  ReceiverUnsupported,
  stopReceiver,
  type ReceiverPlayer,
} from "./receiver";

function fakePlayer(applied = true): {
  player: ReceiverPlayer;
  attach: ReturnType<typeof vi.fn>;
  configure: ReturnType<typeof vi.fn>;
  load: ReturnType<typeof vi.fn>;
  destroy: ReturnType<typeof vi.fn>;
} {
  const attach = vi.fn().mockResolvedValue(undefined);
  const configure = vi.fn().mockReturnValue(applied);
  const load = vi.fn().mockResolvedValue(undefined);
  const destroy = vi.fn().mockResolvedValue(undefined);
  return {
    player: { attach, configure, load, destroy },
    attach,
    configure,
    load,
    destroy,
  };
}

describe("receiver page", () => {
  it("loads the protected DASH manifest with Clear Key and no content key", async () => {
    const { player, attach, load, configure, destroy } = fakePlayer();
    const video = {} as HTMLMediaElement;
    await loadReceiver(video, () => player);
    expect(attach).toHaveBeenCalledWith(video);
    expect(load).toHaveBeenCalledWith(protectedMenus.dash);
    const config = configure.mock.calls[0]?.[0] as {
      drm: { servers: Record<string, string> };
    };
    expect(config.drm.servers).toEqual({
      "org.w3.clearkey": clearKeyLicenseUrl,
    });
    expect(JSON.stringify(config)).not.toContain("ffefcdab");
    expect(JSON.stringify(config)).not.toContain("clearKeys");
    await stopReceiver();
    expect(destroy).toHaveBeenCalledTimes(1);
  });

  it("destroys the player when the manifest load fails", async () => {
    const { player, load, destroy } = fakePlayer();
    load.mockRejectedValue(new Error("ffefcdab"));
    await expect(
      loadReceiver({} as HTMLMediaElement, () => player),
    ).rejects.toThrow("ffefcdab");
    expect(destroy).toHaveBeenCalledTimes(1);
    expect(receiverFailure(new Error("ffefcdab"))).toBe("Playback failed.");
    expect(receiverFailure(new ReceiverUnsupported())).toBe(
      "This browser cannot play the title.",
    );
    expect(
      receiverFailure({
        category: 6,
        data: ["ffefcdab"],
      }),
    ).toBe("The title cannot be played.");
  });

  it("keeps the original failure when destroy rejects", async () => {
    const { player, load, destroy } = fakePlayer();
    load.mockRejectedValue(new Error("ffefcdab"));
    destroy.mockRejectedValue(new Error("destroy failed"));
    await expect(
      loadReceiver({} as HTMLMediaElement, () => player),
    ).rejects.toThrow("ffefcdab");
  });

  it("lets the newer load own the player", async () => {
    const first = fakePlayer();
    let finishAttach: () => void = () => undefined;
    first.attach.mockReturnValue(
      new Promise<void>((resolve) => {
        finishAttach = resolve;
      }),
    );
    const video = {} as HTMLMediaElement;
    const pending = loadReceiver(video, () => first.player);
    await Promise.resolve();
    const second = fakePlayer();
    const next = loadReceiver(video, () => second.player);
    finishAttach();
    await expect(pending).rejects.toBeInstanceOf(ReceiverSuperseded);
    await next;
    expect(second.destroy).not.toHaveBeenCalled();
    await stopReceiver();
    expect(second.destroy).toHaveBeenCalledTimes(1);
  });

  it("reports a critical error and ignores a recoverable one", async () => {
    const seen: unknown[] = [];
    let onShakaError: ((event: Event) => void) | undefined;
    const { player } = fakePlayer();
    player.addEventListener = (_type, listener) => {
      onShakaError = listener;
    };
    await loadReceiver(
      {} as HTMLMediaElement,
      () => player,
      (err) => {
        seen.push(err);
      },
    );
    const recoverable = { detail: { severity: 1, category: 6 } };
    onShakaError?.(recoverable as unknown as Event);
    expect(seen).toEqual([]);
    const critical = {
      detail: { severity: 2, category: 6, data: ["ffefcdab"] },
    };
    onShakaError?.(critical as unknown as Event);
    expect(seen).toEqual([critical]);
    expect(receiverFailure(critical)).toBe("The title cannot be played.");
    await stopReceiver();
  });
});
