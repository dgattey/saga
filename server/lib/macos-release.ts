export type MacOSRelease = {
  version: string;
  build: string;
  /** Pathname for the zip, e.g. `/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip`. */
  zipPath: string;
  /** Absolute URL used for download redirects. */
  downloadUrl: string;
  /** True when a valid download URL is resolved. */
  downloadReady: boolean;
};

export const DEFAULT_APPCAST_URL = "https://saga.gattey.com/appcast.xml";

export const FALLBACK_MACOS_RELEASE: MacOSRelease = {
  version: "1.4.1",
  build: "22346",
  zipPath: "/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip",
  downloadUrl: "https://github.com/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip",
  downloadReady: true,
};

export function parseAppcastXml(xml: string): Omit<MacOSRelease, "downloadReady"> | null {
  const version =
    xml.match(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/)?.[1] ??
    xml.match(/<title>([^<]+)<\/title>/)?.[1];
  const build = xml.match(/<sparkle:version>([^<]+)<\/sparkle:version>/)?.[1] ?? "";
  const enclosure = xml.match(/<enclosure\s+url="([^"]+)"/)?.[1];
  if (!version || !enclosure) return null;

  let downloadUrl = enclosure;
  let zipPath: string;
  try {
    const url = new URL(enclosure);
    downloadUrl = url.href;
    zipPath = url.pathname;
  } catch {
    zipPath = enclosure.startsWith("/") ? enclosure : `/${enclosure}`;
    downloadUrl = `${getSiteOrigin()}${zipPath}`;
  }

  return { version, build, zipPath, downloadUrl };
}

export function getSiteOrigin(): string {
  if (process.env.SAGA_SITE_ORIGIN) {
    return process.env.SAGA_SITE_ORIGIN.replace(/\/$/, "");
  }
  if (process.env.VERCEL_ENV === "production") {
    return "https://saga.gattey.com";
  }
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }
  return `http://localhost:${process.env.PORT ?? 3000}`;
}

export function getAppcastUrl(): string {
  return process.env.SAGA_APPCAST_URL || DEFAULT_APPCAST_URL;
}

/**
 * Fetches the site's Sparkle `appcast.xml` (revalidated every 60s). release-kit deploys it with each
 * release rather than committing it, so the version label and `/download/macos` redirect read it at
 * request time.
 * Falls back to `FALLBACK_MACOS_RELEASE` (`v1.4.1`).
 */
export async function getMacOSRelease(): Promise<MacOSRelease> {
  try {
    const response = await fetch(getAppcastUrl(), {
      next: { revalidate: 60 },
      headers: { Accept: "application/rss+xml, application/xml, text/xml" },
    });
    if (response.ok) {
      const xml = await response.text();
      const parsed = parseAppcastXml(xml);
      if (parsed) {
        return { ...parsed, downloadReady: true };
      }
    }
  } catch {
    // Fall through to the static fallback.
  }

  return FALLBACK_MACOS_RELEASE;
}
