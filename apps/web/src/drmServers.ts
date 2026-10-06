export const clearKeyLicenseUrl = "http://127.0.0.1:8082/";

export function drmServers(): { "org.w3.clearkey": string } {
  return { "org.w3.clearkey": clearKeyLicenseUrl };
}
