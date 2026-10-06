import { bitrateEvent, drmEvent, startupEvent } from "../src/playbackEvent";

test("startup, drm, and bitrate use the shared field names", () => {
  const startup = JSON.parse(
    startupEvent({
      engine: "media3",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 0,
      startupMs: 840,
      manifestUrl: "http://user:pass@127.0.0.1:8080/manifest.mpd?k=ffefcdab",
    }),
  ) as Record<string, unknown>;
  expect(startup).toMatchObject({
    version: 1,
    titleId: "playpath-bars",
    platform: "react-native",
    engine: "media3",
    event: "startup",
    startupMs: 840,
    manifestUrl: "http://127.0.0.1:8080/manifest.mpd",
  });
  expect(JSON.stringify(startup)).not.toContain("ffefcdab");
  expect(JSON.stringify(startup)).not.toContain("user:pass");

  const drm = JSON.parse(
    drmEvent({
      engine: "media3",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 0,
      result: "ok",
      code: "",
    }),
  ) as Record<string, unknown>;
  expect(drm).toMatchObject({
    event: "drm",
    keySystem: "org.w3.clearkey",
    result: "ok",
    code: "",
  });

  const bitrate = JSON.parse(
    bitrateEvent({
      engine: "avplayer",
      sessionId: "session",
      at: "2026-10-06T09:00:00Z",
      positionMs: 1000,
      height: 720,
      bandwidthBps: 2157897,
    }),
  ) as Record<string, unknown>;
  expect(bitrate).toMatchObject({
    platform: "react-native",
    engine: "avplayer",
    event: "bitrate",
    height: 720,
    bandwidthBps: 2157897,
  });
});
