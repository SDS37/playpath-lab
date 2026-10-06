export type MobileEngine = "media3" | "avplayer";

type EventFields = {
  engine: MobileEngine;
  sessionId: string;
  at: string;
  positionMs: number;
};

export function startupEvent(
  input: EventFields & { startupMs: number; manifestUrl: string },
): string {
  return eventLine(input, "startup", [
    `"startupMs":${Math.max(0, Math.round(input.startupMs))}`,
    `"manifestUrl":${jsonString(manifestUrlForEvent(input.manifestUrl))}`,
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

export function bitrateEvent(
  input: EventFields & {
    height: number | undefined;
    bandwidthBps: number | undefined;
  },
): string {
  const fields: string[] = [];
  if (input.height !== undefined && input.height > 0) {
    fields.push(`"height":${input.height}`);
  }
  if (input.bandwidthBps !== undefined && input.bandwidthBps > 0) {
    fields.push(`"bandwidthBps":${input.bandwidthBps}`);
  }
  return eventLine(input, "bitrate", fields);
}

/** Drops userinfo and the query so a manifest URL cannot carry a credential. */
export function manifestUrlForEvent(url: string): string {
  const withoutFragment = url.split("#")[0] ?? url;
  const withoutQuery = withoutFragment.split("?")[0] ?? withoutFragment;
  return withoutQuery.replace(/^(https?:\/\/)[^/@\s]+@/, "$1");
}

function eventLine(
  input: EventFields,
  event: string,
  fields: string[],
): string {
  const line = [
    '"version":1',
    '"titleId":"playpath-bars"',
    `"sessionId":${jsonString(input.sessionId)}`,
    '"platform":"react-native"',
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
