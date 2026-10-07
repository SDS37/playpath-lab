/** A build can replace a lab URL. An empty value keeps the lab default. */
export function configuredUrl(
  value: string | undefined,
  fallback: string,
): string {
  if (value === undefined || value === "") {
    return fallback;
  }
  return value;
}
