import { describe, expect, it } from "vitest";
import { chooseEngine } from "./chooseEngine";
import { clearHlsMenu } from "./clearHlsMenu";
import { protectedMenus } from "./protectedMenus";

const chrome = { hlsJs: true, nativeHls: true, safari: false };
const safari = { hlsJs: true, nativeHls: true, safari: true };

describe("engine choice", () => {
  it("plays clear HLS with hls.js on Chrome and Firefox", () => {
    expect(chooseEngine(clearHlsMenu, chrome)).toBe("hlsjs");
    expect(
      chooseEngine(clearHlsMenu, {
        hlsJs: true,
        nativeHls: false,
        safari: false,
      }),
    ).toBe("hlsjs");
  });

  it("plays clear HLS on the media element on Safari", () => {
    expect(chooseEngine(clearHlsMenu, safari)).toBe("nativeHls");
    expect(
      chooseEngine(clearHlsMenu, {
        hlsJs: false,
        nativeHls: true,
        safari: true,
      }),
    ).toBe("nativeHls");
  });

  it("plays clear HLS on the media element when hls.js is not supported", () => {
    expect(
      chooseEngine(clearHlsMenu, {
        hlsJs: false,
        nativeHls: true,
        safari: false,
      }),
    ).toBe("nativeHls");
  });

  it("does not load the protected package through hls.js", () => {
    expect(clearHlsMenu).toBe("http://127.0.0.1:8084/master.m3u8");
    expect(clearHlsMenu).not.toBe(protectedMenus.hls);
    expect(chooseEngine(protectedMenus.hls, chrome)).toBe("shaka");
    expect(chooseEngine(protectedMenus.dash, safari)).toBe("shaka");
  });

  it("has no engine for clear HLS when the browser supports neither path", () => {
    expect(
      chooseEngine(clearHlsMenu, {
        hlsJs: false,
        nativeHls: false,
        safari: false,
      }),
    ).toBeUndefined();
  });
});
