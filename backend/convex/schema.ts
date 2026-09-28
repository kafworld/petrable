import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  projects: defineTable({
    name: v.string(),
    emoji: v.string(),
    prompt: v.string(),
    // web: queued | generating | sandbox | uploading | starting | live | updating | waking | error
    // mobile adds: building | signing | mac_queued | mac_building
    status: v.string(),
    statusDetail: v.optional(v.string()),
    // "web" (Daytona sandbox) or "mobile" (Chorus iOS build); absent = web
    platform: v.optional(v.string()),
    // Free model tier key used for generation (see convex/models.ts)
    model: v.optional(v.string()),
    sandboxId: v.optional(v.string()),
    previewUrl: v.optional(v.string()),
    // Mobile build pipeline state (Chorus or local Mac worker)
    buildJobId: v.optional(v.string()),
    appUrl: v.optional(v.string()),
    simBuildId: v.optional(v.string()),
    signBuildId: v.optional(v.string()),
    installUrl: v.optional(v.string()),
    version: v.number(),
    error: v.optional(v.string()),
    updatedAt: v.number(),
  }),

  messages: defineTable({
    projectId: v.id("projects"),
    // user | agent | log
    role: v.string(),
    content: v.string(),
  }).index("by_project", ["projectId"]),

  files: defineTable({
    projectId: v.id("projects"),
    path: v.string(),
    content: v.string(),
  }).index("by_project", ["projectId"]),
});
