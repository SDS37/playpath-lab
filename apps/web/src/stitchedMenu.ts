// The stitcher inserts this clear pre-roll, then the film, in one menu.
// The VAST cue is 10 seconds into the film, so a stitched timeline adds the lead.
export const stitchedDash = "http://127.0.0.1:8083/ssai/dash/manifest.mpd";

export const cleanDash = "http://127.0.0.1:8080/manifest.mpd";

export const stitchedLeadMs = 5_000;

export function isStitched(manifestUrl: string): boolean {
  return manifestUrl === stitchedDash;
}

/** The film menu when the stitched URL cannot be loaded. Not an impression URL. */
export function cleanMenu(failed: string): string | undefined {
  if (failed === stitchedDash) {
    return cleanDash;
  }
  return undefined;
}

export function presentationCueMs(cueMs: number, manifestUrl: string): number {
  return isStitched(manifestUrl) ? cueMs + stitchedLeadMs : cueMs;
}
