import { describe, expect, it } from "vitest";
import {
  cleanDash,
  cleanMenu,
  isStitched,
  presentationCueMs,
  stitchedDash,
  stitchedLeadMs,
} from "./stitchedMenu";

describe("stitched menu", () => {
  it("keeps the film cue on a clean menu and adds the pre-roll on the stitch", () => {
    expect(stitchedDash).toBe("http://127.0.0.1:8083/ssai/dash/manifest.mpd");
    expect(isStitched(stitchedDash)).toBe(true);
    expect(isStitched("http://127.0.0.1:8080/manifest.mpd")).toBe(false);
    expect(
      presentationCueMs(10_000, "http://127.0.0.1:8080/manifest.mpd"),
    ).toBe(10_000);
    expect(presentationCueMs(10_000, stitchedDash)).toBe(
      10_000 + stitchedLeadMs,
    );
    expect(stitchedDash).not.toContain("vast/impression");
    expect(stitchedDash).not.toContain("ffefcdab");
  });

  it("uses the clean film when the stitched menu cannot be loaded", () => {
    expect(cleanMenu(stitchedDash)).toBe(cleanDash);
    expect(cleanDash).toBe("http://127.0.0.1:8080/manifest.mpd");
    expect(cleanMenu(cleanDash)).toBeUndefined();
    expect(cleanMenu("http://127.0.0.1:8083/vast/impression")).toBeUndefined();
    expect(cleanDash).not.toContain("vast/impression");
    expect(cleanDash).not.toContain("8083");
    expect(cleanDash).not.toContain("ffefcdab");
  });
});
