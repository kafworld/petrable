import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

const mobileJobShape = v.object({
  _id: v.id("projects"),
  _creationTime: v.number(),
  name: v.string(),
  emoji: v.string(),
  prompt: v.string(),
  status: v.string(),
  statusDetail: v.optional(v.string()),
  platform: v.optional(v.string()),
  model: v.optional(v.string()),
  bundleId: v.string(),
  version: v.number(),
  updatedAt: v.number(),
  files: v.array(v.object({ path: v.string(), content: v.string() })),
});

function bundleIdFor(name: string, projectId: string): string {
  const slug = name.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20) || "app";
  return `com.keithable.app.${slug}${projectId.slice(-6).toLowerCase()}`;
}

function requireWorkerToken(token: string | undefined): void {
  const expected = process.env.KEITHABLE_WORKER_TOKEN;
  if (expected && token !== expected) throw new Error("Invalid worker token");
}

export const pendingMobileBuilds = query({
  args: { token: v.optional(v.string()) },
  returns: v.array(mobileJobShape),
  handler: async (ctx, { token }) => {
    requireWorkerToken(token);
    const projects = await ctx.db.query("projects").order("desc").take(100);
    const pending = projects.filter(
      (project) =>
        project.platform === "mobile" &&
        (project.status === "mac_queued" || project.status === "mac_building")
    );
    const jobs = [];
    for (const project of pending.slice(0, 10)) {
      const files = await ctx.db
        .query("files")
        .withIndex("by_project", (q) => q.eq("projectId", project._id))
        .collect();
      jobs.push({
        _id: project._id,
        _creationTime: project._creationTime,
        name: project.name,
        emoji: project.emoji,
        prompt: project.prompt,
        status: project.status,
        statusDetail: project.statusDetail,
        platform: project.platform,
        model: project.model,
        bundleId: bundleIdFor(project.name, project._id),
        version: project.version,
        updatedAt: project.updatedAt,
        files: files
          .map((file) => ({ path: file.path, content: file.content }))
          .sort((a, b) => a.path.localeCompare(b.path)),
      });
    }
    return jobs;
  },
});

export const claimMobileBuild = mutation({
  args: { id: v.id("projects"), workerId: v.string(), token: v.optional(v.string()) },
  returns: v.boolean(),
  handler: async (ctx, { id, workerId, token }) => {
    requireWorkerToken(token);
    const project = await ctx.db.get(id);
    if (!project || project.platform !== "mobile" || project.status !== "mac_queued") {
      return false;
    }
    await ctx.db.patch(id, {
      status: "mac_building",
      statusDetail: "Your Mac is compiling the iPhone app",
      buildJobId: `mac:${workerId}:${Date.now()}`,
      updatedAt: Date.now(),
    });
    await ctx.db.insert("messages", {
      projectId: id,
      role: "log",
      content: "💻 Mac worker picked up the iPhone build.",
    });
    return true;
  },
});

export const completeMobileBuild = mutation({
  args: {
    id: v.id("projects"),
    ipaPath: v.string(),
    bundleId: v.string(),
    workerId: v.string(),
    signedIpaPath: v.optional(v.string()),
    installResult: v.optional(v.string()),
    token: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, { id, ipaPath, bundleId, workerId, signedIpaPath, installResult, token }) => {
    requireWorkerToken(token);
    const project = await ctx.db.get(id);
    if (!project || project.platform !== "mobile") return null;
    const installed = installResult === "installed";
    await ctx.db.patch(id, {
      status: "live",
      statusDetail: installed ? "Installed on your iPhone" : "IPA built on your Mac",
      appUrl: ipaPath,
      installUrl: signedIpaPath,
      version: project.version + 1,
      error: undefined,
      updatedAt: Date.now(),
    });
    const installLine = installed
      ? `Installed on your iPhone.`
      : `Built on your Mac. Codex will finish Signulous install when device signing is available.`;
    await ctx.db.insert("messages", {
      projectId: id,
      role: "agent",
      content:
        `✅ ${project.name} is Apple-ready on your Mac.\n\n` +
        `Bundle ID: ${bundleId}\n\n` +
        `${installLine}\n\n` +
        `IPA: ${ipaPath}`,
    });
    await ctx.db.insert("messages", {
      projectId: id,
      role: "log",
      content: `💻 Built by ${workerId}`,
    });
    return null;
  },
});

export const failMobileBuild = mutation({
  args: {
    id: v.id("projects"),
    error: v.string(),
    workerId: v.string(),
    token: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, { id, error, workerId, token }) => {
    requireWorkerToken(token);
    const project = await ctx.db.get(id);
    if (!project || project.platform !== "mobile") return null;
    await ctx.db.patch(id, {
      status: "error",
      statusDetail: "Mac build failed",
      error,
      updatedAt: Date.now(),
    });
    await ctx.db.insert("messages", {
      projectId: id,
      role: "agent",
      content: `❌ Mac build failed: ${error.slice(0, 800)}`,
    });
    await ctx.db.insert("messages", {
      projectId: id,
      role: "log",
      content: `💻 ${workerId} reported a failed iPhone build.`,
    });
    return null;
  },
});

export const requeueMobileBuild = mutation({
  args: { id: v.id("projects"), token: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, { id, token }) => {
    requireWorkerToken(token);
    const project = await ctx.db.get(id);
    if (!project || project.platform !== "mobile") return null;
    await ctx.db.patch(id, {
      status: "mac_queued",
      statusDetail: "Waiting for your Mac to compile the iPhone app",
      error: undefined,
      updatedAt: Date.now(),
    });
    await ctx.db.insert("messages", {
      projectId: id,
      role: "log",
      content: "💻 Mac worker build requeued after local worker repair.",
    });
    return null;
  },
});
