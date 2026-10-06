import { describe, expect, it } from "vitest";
import { chooseEngine } from "./chooseEngine";
import { clearHlsMenu } from "./clearHlsMenu";
import { protectedMenus } from "./protectedMenus";

describe("engine choice", () => {
  it("plays clear HLS with hls.js when the element cannot", () => {
    expect(chooseEngine(clearHlsMenu, { hlsJs: true, nativeHls: false })).toBe(
      "hlsjs",
    );
  });

  it("plays clear HLS on the media element when hls.js is not supported", () => {
    expect(chooseEngine(clearHlsMenu, { hlsJs: true, nativeHls: true })).toBe(
      "hlsjs",
    );
    expect(chooseEngine(clearHlsMenu, { hlsJs: false, nativeHls: true })).toBe(
      "nativeHls",
    );
  });

  it("does not load the protected package through hls.js", () => {
    expect(clearHlsMenu).toBe("http://127.0.0.1:8084/master.m3u8");
    expect(clearHlsMenu).not.toBe(protectedMenus.hls);
    expect(
      chooseEngine(protectedMenus.hls, { hlsJs: true, nativeHls: false }),
    ).toBe("shaka");
    expect(
      chooseEngine(protectedMenus.dash, { hlsJs: true, nativeHls: true }),
    ).toBe("shaka");
  });

  it("has no engine for clear HLS when the browser supports neither path", () => {
    expect(
      chooseEngine(clearHlsMenu, { hlsJs: false, nativeHls: false }),
    ).toBeUndefined();
  });
});
