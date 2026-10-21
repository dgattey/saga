import type { NextConfig } from "next";

// TODO(dylkit): drop this redirect once @dylkit/web serves `/appcast.xml` by proxying the latest GitHub release.
const APPCAST_URL = "https://github.com/dgattey/saga/releases/latest/download/appcast.xml";

const nextConfig: NextConfig = {
  transpilePackages: ["@dylkit/web"],
  async redirects() {
    return [{ source: "/appcast.xml", destination: APPCAST_URL, permanent: false }];
  },
};

export default nextConfig;
