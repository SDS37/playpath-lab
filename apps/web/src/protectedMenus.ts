export const protectedMenus = {
  dash: "http://127.0.0.1:8080/manifest.mpd",
  hls: "http://127.0.0.1:8080/master.m3u8",
} as const;

export type ProtectedMenu = keyof typeof protectedMenus;
