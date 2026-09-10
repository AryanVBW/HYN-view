import type { NextConfig } from "next";
import { withWorkflow } from "workflow/next";

const nextConfig: NextConfig = {
  // This portal is an independent checkout nested beside the Bash agent.
  // Parent lockfiles must not change its dependency resolution or file tracing.
  turbopack: { root: import.meta.dirname },
  outputFileTracingRoot: import.meta.dirname,
  images: {
    unoptimized: true,
  },
};

// Heroku runs one ordinary Node web process. Workflow requires a separately
// configured durable runtime, so it is an explicit deployment option.
export default process.env.HYN_ENABLE_WORKFLOW_WATCHDOG === "true"
  ? withWorkflow(nextConfig)
  : nextConfig;
