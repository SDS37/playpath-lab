import { describe, expect, it } from "vitest";
import {
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
});
