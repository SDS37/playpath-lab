export const midrollVastUrl = "http://127.0.0.1:8083/vast/midroll.xml";

export type Midroll = {
  cueMs: number;
  mediaUrl: string;
};

const clock = /timeOffset="(\d{2}):(\d{2}):(\d{2})\.(\d{3})"/;
const mediaFile =
  /<MediaFile\b[^>]*>\s*<!\[CDATA\[(https?:\/\/[^\]\s]+)\]\]>\s*<\/MediaFile>/;

export function readMidroll(xml: string): Midroll | undefined {
  const time = clock.exec(xml);
  const media = mediaFile.exec(xml);
  if (time === null || media === null) {
    return undefined;
  }
  const hours = time[1];
  const minutes = time[2];
  const seconds = time[3];
  const millis = time[4];
  const mediaUrl = media[1];
  if (
    hours === undefined ||
    minutes === undefined ||
    seconds === undefined ||
    millis === undefined ||
    mediaUrl === undefined
  ) {
    return undefined;
  }
  const cueMs =
    (Number(hours) * 60 * 60 + Number(minutes) * 60 + Number(seconds)) * 1000 +
    Number(millis);
  if (!Number.isFinite(cueMs)) {
    return undefined;
  }
  return { cueMs, mediaUrl };
}

export function playingAtCue(
  currentTimeMs: number,
  cueMs: number,
  paused: boolean,
  ended: boolean,
): boolean {
  if (paused || ended) {
    return false;
  }
  if (!Number.isFinite(currentTimeMs) || !Number.isFinite(cueMs)) {
    return false;
  }
  return currentTimeMs >= cueMs;
}

export async function fetchMidroll(): Promise<Midroll | undefined> {
  try {
    const response = await fetch(midrollVastUrl, {
      signal: AbortSignal.timeout(2000),
    });
    if (!response.ok) {
      return undefined;
    }
    return readMidroll(await response.text());
  } catch {
    return undefined;
  }
}
