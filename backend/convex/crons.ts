import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Reclaim Daytona disk weekly: destroy sandboxes for builds that have been
// idle longer than the14-day window (active previews are never touched).
crons.interval("sweep idle sandboxes", { minutes: 7 * 24 * 60 }, internal.builder.sweepSandboxes, {});

export default crons;
