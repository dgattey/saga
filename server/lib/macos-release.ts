export type MacOSRelease = {
  version: string;
  build: string;
  /** Pathname for the zip, e.g. `/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip`. */
  zipPath: string;
  /** Absolute URL used for download redirects. */
  downloadUrl: string;
  /** True when a valid download URL is resolved. */
  downloadReady: boolean;
};

export const DEFAULT_APPCAST_URL =
  "https://github.com/dgattey/saga/releases/latest/download/appcast.xml";

export const FALLBACK_MACOS_RELEASE: MacOSRelease = {
  version: "1.9.2",
  build: "22672",
  zipPath: "/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip",
  downloadUrl: "https://github.com/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip",
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
 * Fetches the latest Sparkle `appcast.xml` from GitHub Releases (revalidated every 60s)
 * so new releases published by `.github/workflows/release.yml` automatically update the
 * version label and `/download/macos` redirect without redeploying the site.
 * Falls back to `FALLBACK_MACOS_RELEASE` (`v1.9.2`).
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
