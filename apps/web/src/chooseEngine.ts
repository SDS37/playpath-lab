import { clearHlsMenu } from "./clearHlsMenu";

export type EngineChoice = "shaka" | "hlsjs" | "nativeHls";

export function chooseEngine(
  manifestUrl: string,
  support: {
    readonly hlsJs: boolean;
    readonly nativeHls: boolean;
    readonly safari: boolean;
  },
): EngineChoice | undefined {
  if (manifestUrl !== clearHlsMenu) {
    return "shaka";
  }
  // Safari plays HLS without hls.js, including when hls.js also reports
  // support. Chromium's canPlayType returns "maybe" for that type, so the
  // vendor is what keeps Chrome and Firefox on hls.js.
  if (support.safari && support.nativeHls) {
    return "nativeHls";
  }
  if (support.hlsJs) {
    return "hlsjs";
  }
  if (support.nativeHls) {
    return "nativeHls";
  }
  return undefined;
}
