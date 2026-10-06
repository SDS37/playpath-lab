import { describe, expect, it } from "vitest";
import { bitrateEvent } from "./bitrateEvent";

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
});
