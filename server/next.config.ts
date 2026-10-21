import type { NextConfig } from "next";

// Saga's Sparkle feed (SUFeedURL). Releases are published to GitHub Releases and never committed, so the
// site points at the latest release's appcast. Temporary, so Sparkle and caches never pin the target.
const APPCAST_URL = "https://github.com/dgattey/saga/releases/latest/download/appcast.xml";

const nextConfig: NextConfig = {
  async redirects() {
    return [{ source: "/appcast.xml", destination: APPCAST_URL, permanent: false }];
  },
};

export default nextConfig;
