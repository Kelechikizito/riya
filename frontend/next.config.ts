import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The Foundry repo at the parent level has its own lockfile; pin the root so
  // Turbopack does not guess and warn on every build.
  turbopack: {
    root: path.resolve(process.cwd()),
  },
};

export default nextConfig;
