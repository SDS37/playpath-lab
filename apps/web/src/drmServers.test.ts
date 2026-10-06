import { describe, expect, it } from "vitest";
import { clearKeyLicenseUrl, drmServers } from "./drmServers";
import { protectedMenus } from "./protectedMenus";

describe("Clear Key configuration", () => {
  it("points Shaka at the license service and does not carry the key", () => {
    const servers = drmServers();
    expect(servers["org.w3.clearkey"]).toBe(clearKeyLicenseUrl);
    expect(Object.keys(servers)).toEqual(["org.w3.clearkey"]);
    expect(JSON.stringify(servers)).not.toContain("clearKeys");
    expect(JSON.stringify(servers)).not.toContain("ffefcdab");
  });

  it("loads the protected menus from origin A", () => {
    expect(protectedMenus.dash).toBe("http://127.0.0.1:8080/manifest.mpd");
    expect(protectedMenus.hls).toBe("http://127.0.0.1:8080/master.m3u8");
  });
});
