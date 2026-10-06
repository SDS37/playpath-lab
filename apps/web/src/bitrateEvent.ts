export type BitrateEngine = "shaka" | "hlsjs";

type EventFields = {
  engine: BitrateEngine;
  sessionId: string;
  at: string;
  positionMs: number;
};

export function bitrateEvent(
  input: EventFields & {
    height: number | undefined;
    bandwidthBps: number | undefined;
    codecs: string | undefined;
  },
): string {
  const fields: string[] = [];
  if (input.height !== undefined) {
    fields.push(`"height":${input.height}`);
  }
  if (input.bandwidthBps !== undefined) {
    fields.push(`"bandwidthBps":${input.bandwidthBps}`);
  }
  if (input.codecs !== undefined && input.codecs !== "") {
    fields.push(`"codecs":${jsonString(input.codecs)}`);
  }
  return eventLine(input, "bitrate", fields);
}

export function startupEvent(
  input: EventFields & { startupMs: number; manifestUrl: string },
): string {
  return eventLine(input, "startup", [
    `"startupMs":${Math.max(0, Math.round(input.startupMs))}`,
    `"manifestUrl":${jsonString(manifestUrlForEvent(input.manifestUrl))}`,
  ]);
}

export function adEvent(
  input: EventFields & {
    action: "start" | "impression" | "complete" | "error";
    breakId?: "preroll" | "midroll";
    mode?: "ssai" | "csai";
  },
): string {
  return eventLine(input, "ad", [
    `"breakId":${jsonString(input.breakId ?? "midroll")}`,
    `"mode":${jsonString(input.mode ?? "csai")}`,
    `"action":${jsonString(input.action)}`,
  ]);
}

export function drmEvent(
  input: EventFields & { result: "ok" | "error"; code: string },
): string {
  return eventLine(input, "drm", [
    '"keySystem":"org.w3.clearkey"',
    `"result":${jsonString(input.result)}`,
    `"code":${jsonString(input.code)}`,
  ]);
}

/** Drops userinfo and the query so a manifest URL cannot carry a credential. */
export function manifestUrlForEvent(url: string): string {
  const withoutFragment = url.split("#")[0] ?? url;
  const withoutQuery = withoutFragment.split("?")[0] ?? withoutFragment;
  return withoutQuery.replace(/^(https?:\/\/)[^/@\s]+@/, "$1");
}

/** The engine code only. `data` can hold a license body, so it stays out of the event. */
export function drmCodeOf(err: unknown): string {
  const code = codeOf(err);
  return code === undefined ? "" : String(code);
}

function codeOf(err: unknown): number | undefined {
  if (typeof err !== "object" || err === null) {
    return undefined;
  }
  if ("detail" in err) {
    const nested = codeOf(err.detail);
    if (nested !== undefined) {
      return nested;
    }
  }
  if ("code" in err && typeof err.code === "number") {
    return err.code;
  }
  return undefined;
}

function eventLine(
  input: EventFields,
  event: string,
  fields: string[],
): string {
  const line = [
    '"version":1',
    `"titleId":${jsonString("playpath-bars")}`,
    `"sessionId":${jsonString(input.sessionId)}`,
    '"platform":"web"',
    `"engine":${jsonString(input.engine)}`,
    `"event":${jsonString(event)}`,
    `"at":${jsonString(input.at)}`,
    `"positionMs":${Math.max(0, Math.round(input.positionMs))}`,
    ...fields,
  ];
  return `{${line.join(",")}}`;
}

function jsonString(value: string): string {
  return `"${value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")}"`;
}
