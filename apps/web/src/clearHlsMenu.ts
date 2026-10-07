import { configuredUrl } from "./configuredUrl";

export const clearHlsMenu = configuredUrl(
  import.meta.env.VITE_CLEAR_HLS,
  "http://127.0.0.1:8084/master.m3u8",
);
