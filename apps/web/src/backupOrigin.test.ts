import { describe, expect, it } from "vitest";
import {
  backupOrigin,
  backupSegmentUrl,
  primaryOrigin,
  segmentUriForAttempt,
} from "./backupOrigin";

describe("backup origin", () => {
  it("keeps the failed segment path on origin B", () => {
    expect(backupSegmentUrl(`${primaryOrigin}/720p/seg_5.m4s`)).toBe(
      `${backupOrigin}/720p/seg_5.m4s`,
    );
    expect(backupSegmentUrl(`${primaryOrigin}/audio/seg_3.m4s?x=1`)).toBe(
      `${backupOrigin}/audio/seg_3.m4s?x=1`,
    );
  });

  it("leaves menus, init segments, and other hosts on their own URL", () => {
    expect(backupSegmentUrl(`${primaryOrigin}/manifest.mpd`)).toBeUndefined();
    expect(
      backupSegmentUrl(`${primaryOrigin}/720p/init_0.mp4`),
    ).toBeUndefined();
    expect(backupSegmentUrl(`${backupOrigin}/720p/seg_5.m4s`)).toBeUndefined();
    expect(
      backupSegmentUrl(
        "http://127.0.0.1:8082/?keyId=00112233445566778899aabbccddeeff",
      ),
    ).toBeUndefined();
    expect(
      backupSegmentUrl("http://127.0.0.1:8083/preroll/creative.mp4"),
    ).toBeUndefined();
  });

  it("switches only after the primary attempt fails", () => {
    const segment = `${primaryOrigin}/1080p/seg_3.m4s`;
    expect(segmentUriForAttempt(segment, 0)).toBe(segment);
    expect(segmentUriForAttempt(segment, 1)).toBe(
      `${backupOrigin}/1080p/seg_3.m4s`,
    );
    expect(segmentUriForAttempt(`${primaryOrigin}/manifest.mpd`, 1)).toBe(
      `${primaryOrigin}/manifest.mpd`,
    );
  });

  it("does not carry key material", () => {
    const mapped = backupSegmentUrl(`${primaryOrigin}/720p/seg_0.m4s`);
    expect(mapped).not.toContain("ffefcdab");
  });
});
