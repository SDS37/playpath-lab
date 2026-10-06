import { clearHlsMenu } from "./clearHlsMenu";

export type EngineChoice = "shaka" | "hlsjs" | "nativeHls";

export function chooseEngine(
  manifestUrl: string,
  support: { readonly hlsJs: boolean; readonly nativeHls: boolean },
): EngineChoice | undefined {
  if (manifestUrl !== clearHlsMenu) {
    return "shaka";
  }
  if (support.hlsJs) {
    return "hlsjs";
  }
  // Safari plays HLS without hls.js.
  if (support.nativeHls) {
    return "nativeHls";
  }
  return undefined;
}
