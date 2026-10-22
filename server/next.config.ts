import path from "node:path";
import type { NextConfig } from "next";

/** Icon URLs dyl-kit and dylangattey.com fetch cross-origin from every <app>.gattey.com site. */
const SHARED_ICON_PATHS = ["/icon.png", "/app-icon.png", "/apple-touch-icon.png"] as const;

const SHARED_ICON_HEADERS = [
  { key: "Cache-Control", value: "public, max-age=3600, stale-while-revalidate=86400" },
  { key: "Access-Control-Allow-Origin", value: "*" },
];

const nextConfig: NextConfig = {
  transpilePackages: ["@dylkit/web"],
  // @dylkit/web's loadSite() reads DylApp.toml (outside this project) and the screenshots' PNG headers at request
  // time, and Vercel leaves both out of function bundles unless they're traced.
  outputFileTracingRoot: path.join(import.meta.dirname, ".."),
  outputFileTracingIncludes: { "/**": ["../DylApp.toml", "./public/*.png"] },
  async headers() {
    return SHARED_ICON_PATHS.map((source) => ({ source, headers: SHARED_ICON_HEADERS }));
  },
};

export default nextConfig;
