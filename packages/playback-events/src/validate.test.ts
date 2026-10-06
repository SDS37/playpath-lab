import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import schema from "../schema/playback-event.v1.json" with { type: "json" };
import startup from "../fixtures/startup.json" with { type: "json" };
import { playbackEventErrors } from "./validate";

const here = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(here, "../fixtures");

function fixture(name: string): unknown {
  return JSON.parse(readFileSync(join(fixturesDir, name), "utf8")) as unknown;
}

describe("playback event schema", () => {
  it("accepts a startup, a drm error, and a bitrate", () => {
    for (const name of ["startup.json", "drm-error.json", "bitrate.json"]) {
      expect(playbackEventErrors(fixture(name)), name).toEqual([]);
    }
  });

  it("rejects a startup that renames startupMs", () => {
    const renamed: Record<string, unknown> = {
      ...startup,
      timeToFirstFrameMs: startup.startupMs,
    };
    delete renamed.startupMs;
    expect(playbackEventErrors(renamed).length).toBeGreaterThan(0);
  });

  it("rejects a field that is not in the document", () => {
    const extra: Record<string, unknown> = {
      ...startup,
      licenseBody: "secret",
    };
    expect(playbackEventErrors(extra).length).toBeGreaterThan(0);
  });

  it("names milliseconds, pixels, and bits per second", () => {
    expect(schema.properties.positionMs.description).toMatch(/milliseconds/i);
    expect(schema.properties.startupMs.description).toMatch(/milliseconds/i);
    expect(schema.properties.stallMs.description).toMatch(/milliseconds/i);
    expect(schema.properties.height.description).toMatch(/pixels/i);
    expect(schema.properties.bandwidthBps.description).toMatch(
      /bits per second/i,
    );
    const bitrate = fixture("bitrate.json") as {
      positionMs: number;
      height: number;
      bandwidthBps: number;
    };
    expect(Number.isInteger(bitrate.positionMs)).toBe(true);
    expect(bitrate.height).toBe(720);
    expect(bitrate.bandwidthBps).toBe(2157897);
  });

  it("keeps keys and license bodies out of the fixtures", () => {
    const names = readdirSync(fixturesDir);
    expect(names.length).toBeGreaterThan(0);
    for (const name of names) {
      const text = readFileSync(join(fixturesDir, name), "utf8");
      expect(text, name).not.toContain("ffefcdab");
      const event = JSON.parse(text) as Record<string, unknown>;
      for (const field of Object.keys(event)) {
        expect(
          ["license", "credential", "spc", "ckc", "contentKey"],
          name,
        ).not.toContain(field);
      }
    }
  });
});
