// Same roots as services/origin/session.json. A failed media segment
// keeps its path. The title does not start again at the first segment.
export const primaryOrigin = "http://127.0.0.1:8080";
export const backupOrigin = "http://127.0.0.1:8081";

export function backupSegmentUrl(failed: string): string | undefined {
  let parsed: URL;
  try {
    parsed = new URL(failed);
  } catch {
    return undefined;
  }
  const primary = new URL(primaryOrigin);
  if (parsed.protocol !== primary.protocol || parsed.host !== primary.host) {
    return undefined;
  }
  if (
    parsed.pathname === "/" ||
    parsed.pathname.endsWith("/") ||
    !parsed.pathname.endsWith(".m4s")
  ) {
    return undefined;
  }
  const next = new URL(backupOrigin);
  next.pathname = parsed.pathname;
  next.search = parsed.search;
  return next.toString();
}

export function segmentUriForAttempt(uri: string, attempt: number): string {
  if (attempt < 1) {
    return uri;
  }
  return backupSegmentUrl(uri) ?? uri;
}
