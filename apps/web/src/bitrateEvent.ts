export type BitrateEngine = "shaka" | "hlsjs";

export function bitrateEvent(input: {
  engine: BitrateEngine;
  sessionId: string;
  at: string;
  positionMs: number;
  height: number | undefined;
  bandwidthBps: number | undefined;
  codecs: string | undefined;
}): string {
  const fields = [
    '"version":1',
    `"titleId":${jsonString("playpath-bars")}`,
    `"sessionId":${jsonString(input.sessionId)}`,
    '"platform":"web"',
    `"engine":${jsonString(input.engine)}`,
    '"event":"bitrate"',
    `"at":${jsonString(input.at)}`,
    `"positionMs":${Math.round(input.positionMs)}`,
  ];
  if (input.height !== undefined) {
    fields.push(`"height":${input.height}`);
  }
  if (input.bandwidthBps !== undefined) {
    fields.push(`"bandwidthBps":${input.bandwidthBps}`);
  }
  if (input.codecs !== undefined && input.codecs !== "") {
    fields.push(`"codecs":${jsonString(input.codecs)}`);
  }
  return `{${fields.join(",")}}`;
}

function jsonString(value: string): string {
  return `"${value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")}"`;
}
