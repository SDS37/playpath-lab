import { describe, expect, it } from "vitest";
import {
  adEvent,
  bitrateEvent,
  drmCodeOf,
  drmEvent,
  manifestUrlForEvent,
  startupEvent,
} from "./bitrateEvent";

describe("bitrate event", () => {
  it("records the lower rung the engine selected", () => {
    const event = bitrateEvent({
      engine: "hlsjs",
      sessionId: "session",
      at: "2026-10-06T13:00:00Z",
      positionMs: 4000,
      height: 720,
      bandwidthBps: 2157897,
      codecs: "avc1.64001f,mp4a.40.2",
    });
    expect(event).toContain('"event":"bitrate"');
    expect(event).toContain('"engine":"hlsjs"');
    expect(event).toContain('"height":720');
    expect(event).toContain('"bandwidthBps":2157897');
    expect(event).not.toContain("ffefcdab");
  });

  it("keeps a newline inside one JSON line", () => {
    const event = bitrateEvent({
      engine: "shaka",
      sessionId: "session",
      at: "2026-10-06T13:00:00Z",
      positionMs: 0,
      height: 720,
      bandwidthBps: undefined,
      codecs: "avc1\nmp4a\r",
    });
    expect(event).not.toMatch(/[\n\r]/);
    expect(JSON.parse(event).codecs).toBe("avc1\nmp4a\r");
  });

  it("records startup and the mid-roll with the same field names", () => {
    const startup = startupEvent({
      engine: "shaka",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 0,
      startupMs: 840,
      manifestUrl: "http://user:pass@127.0.0.1:8080/manifest.mpd?k=ffefcdab",
    });
    expect(JSON.parse(startup)).toMatchObject({
      version: 1,
      titleId: "playpath-bars",
      platform: "web",
      engine: "shaka",
      event: "startup",
      startupMs: 840,
      manifestUrl: "http://127.0.0.1:8080/manifest.mpd",
    });
    expect(startup).not.toContain("ffefcdab");
    expect(startup).not.toContain("user:pass");
    const ad = adEvent({
      engine: "hlsjs",
      sessionId: "session",
      at: "2026-10-06T09:00:10Z",
      positionMs: 10000,
      action: "start",
    });
    expect(JSON.parse(ad)).toMatchObject({
      event: "ad",
      breakId: "midroll",
      mode: "csai",
      action: "start",
      positionMs: 10000,
    });
    const impression = adEvent({
      engine: "shaka",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 0,
      action: "impression",
      breakId: "preroll",
      mode: "ssai",
    });
    expect(JSON.parse(impression)).toMatchObject({
      event: "ad",
      breakId: "preroll",
      mode: "ssai",
      action: "impression",
    });
    expect(impression).not.toContain("vast/impression");
    const midrollImpression = adEvent({
      engine: "shaka",
      sessionId: "session",
      at: "2026-10-06T09:00:10Z",
      positionMs: 10000,
      action: "impression",
    });
    expect(JSON.parse(midrollImpression)).toMatchObject({
      breakId: "midroll",
      mode: "csai",
      action: "impression",
    });
    expect(midrollImpression).not.toContain("vast/impression");
    expect(manifestUrlForEvent("http://127.0.0.1:8084/master.m3u8")).toBe(
      "http://127.0.0.1:8084/master.m3u8",
    );
  });

  it("records a drm result without the license body", () => {
    const code = drmCodeOf({
      detail: { category: 6, code: 6001, data: ["ffefcdab"] },
    });
    const event = drmEvent({
      engine: "shaka",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 0,
      result: "error",
      code,
    });
    expect(JSON.parse(event)).toMatchObject({
      event: "drm",
      keySystem: "org.w3.clearkey",
      result: "error",
      code: "6001",
    });
    expect(event).not.toContain("ffefcdab");
  });
});
