import type { NextConfig } from "next";

// Saga's Sparkle feed (SUFeedURL). Releases are published to GitHub Releases and never committed, so the
// site points at the latest release's appcast. Temporary, so Sparkle and caches never pin the target.
const APPCAST_URL = "https://github.com/dgattey/saga/releases/latest/download/appcast.xml";

/** Icon URLs dyl-kit and dylangattey.com fetch cross-origin from every <app>.gattey.com site. */
const SHARED_ICON_PATHS = ["/icon.png", "/app-icon.png", "/apple-touch-icon.png"] as const;

const SHARED_ICON_HEADERS = [
  { key: "Cache-Control", value: "public, max-age=3600, stale-while-revalidate=86400" },
  { key: "Access-Control-Allow-Origin", value: "*" },
];

const nextConfig: NextConfig = {
  async redirects() {
    return [{ source: "/appcast.xml", destination: APPCAST_URL, permanent: false }];
  },
  async headers() {
    return SHARED_ICON_PATHS.map((source) => ({ source, headers: SHARED_ICON_HEADERS }));
  },
};

export default nextConfig;
