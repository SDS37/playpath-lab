import { configuredUrl } from "./configuredUrl";

export const protectedMenus = {
  dash: configuredUrl(
    import.meta.env.VITE_PROTECTED_DASH,
    "http://127.0.0.1:8080/manifest.mpd",
  ),
  hls: configuredUrl(
    import.meta.env.VITE_PROTECTED_HLS,
    "http://127.0.0.1:8080/master.m3u8",
  ),
} as const;

export type ProtectedMenu = keyof typeof protectedMenus;
