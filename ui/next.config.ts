import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  logging: {
    fetches: {
      fullUrl: true,
    },
  },
  serverRuntimeConfig: {
    trustProxy: true,
  },
  experimental: { swcPlugins: [] },
  compiler: { removeConsole: process.env.NODE_ENV === "production" },
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
};

export default nextConfig;
