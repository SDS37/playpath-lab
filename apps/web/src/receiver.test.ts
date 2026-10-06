import { describe, expect, it, vi } from "vitest";

vi.mock("shaka-player", () => ({
  default: {
    polyfill: { installAll: () => undefined },
    Player: class Player {
      static isBrowserSupported(): boolean {
        return true;
      }
    },
    util: { Error: { Category: { DRM: 6 } } },
  },
}));
import { clearKeyLicenseUrl } from "./drmServers";
import { protectedMenus } from "./protectedMenus";
import {
  loadReceiver,
  receiverFailure,
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
});
