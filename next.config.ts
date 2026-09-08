import type { NextConfig } from "next";
import { withWorkflow } from "workflow/next";

const nextConfig: NextConfig = {
  images: {
    unoptimized: true,
  },
};

// Heroku runs one ordinary Node web process. Workflow requires a separately
// configured durable runtime, so it is an explicit deployment option.
export default process.env.HYN_ENABLE_WORKFLOW_WATCHDOG === "true"
  ? withWorkflow(nextConfig)
  : nextConfig;
