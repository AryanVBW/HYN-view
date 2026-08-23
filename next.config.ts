import type { NextConfig } from "next";
import { withWorkflow } from "workflow/next";

const nextConfig: NextConfig = {
  images: {
    unoptimized: true,
  },
};

export default withWorkflow(nextConfig);
