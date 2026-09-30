"use node";

import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import type { ActionCtx } from "./_generated/server";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import JSZip from "jszip";
import { resolveModel, preferredProvider } from "./models";
import { callFreeModel } from "./freeAi";
import {
  renderPbxproj,
  XCSCHEME,
  ASSETS_ROOT_JSON,
  ASSETS_APPICON_JSON,
  ASSETS_ACCENT_JSON,
} from "./iosTemplate";

// ---------------------------------------------------------------------------
// Daytona REST helpers (web projects)
// ---------------------------------------------------------------------------

const APP_DIR = "/home/daytona/app";
const PORT = 3000;
const HOME_DIR = "/home/daytona";

function daytonaBase(): string {
  return process.env.DAYTONA_API_URL ?? "https://app.daytona.io/api";
}

function daytonaHeaders(): Record<string, string> {
  const key = process.env.DAYTONA_API_KEY;
  if (!key) throw new Error("DAYTONA_API_KEY is not set on the Convex deployment");
  return { Authorization: `Bearer ${key}` };
}

async function daytona(
  path: string,
  init: RequestInit = {},
  timeoutMs = 60_000
): Promise<Response> {
  return await fetch(`${daytonaBase()}${path}`, {
    ...init,
    headers: { ...daytonaHeaders(), ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(timeoutMs),
  });
}

async function daytonaJson<T>(
  path: string,
  init: RequestInit = {},
  timeoutMs = 60_000
): Promise<T> {
  const res = await daytona(path, init, timeoutMs);
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(
      `Daytona ${init.method ?? "GET"} ${path} failed (${res.status}): ${body.slice(0, 300)}`
    );
  }
  return (await res.json()) as T;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type SandboxInfo = { id: string; state: string };

async function getSandbox(id: string): Promise<SandboxInfo> {
  return await daytonaJson<SandboxInfo>(`/sandbox/${id}`);
}

async function waitForSandboxState(
  id: string,
  want: string,
  timeoutMs: number
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const sb = await getSandbox(id);
    if (sb.state === want) return;
    if (["error", "build_failed", "destroyed"].includes(sb.state)) {
      throw new Error(`Sandbox entered state "${sb.state}"`);
    }
    await sleep(1500);
  }
  throw new Error(`Timed out waiting for sandbox to reach "${want}"`);
}

async function createSandbox(): Promise<string> {
  // Daytona occasionally returns a transient 403 "Region ... is not available"
  // when capacity is tight — retry with backoff before giving up.
  let lastError: unknown;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const sandbox = await daytonaJson<SandboxInfo>(
        "/sandbox",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            public: true,
            autoStopInterval: 60,
            labels: { app: "forge" },
          }),
        },
        120_000
      );
      if (sandbox.state !== "started") {
        await waitForSandboxState(sandbox.id, "started", 180_000);
      }
      return sandbox.id;
    } catch (err) {
      lastError = err;
      const message = errorMessage(err);
      const transient = /Region .* is not available|temporarily unavailable|\b(429|502|503)\b/i.test(message);
      if (!transient || attempt === 2) throw err;
      await sleep(8_000 * (attempt + 1));
    }
  }
  throw lastError;
}

async function startSandbox(id: string): Promise<void> {
  const res = await daytona(`/sandbox/${id}/start`, { method: "POST" }, 120_000);
  if (!res.ok && res.status !== 409) {
    throw new Error(`Failed to start sandbox (${res.status})`);
  }
  await waitForSandboxState(id, "started", 180_000);
}

// Daytona moved command execution behind a per-sandbox toolbox proxy
// (the old inline /toolbox/{id}/toolbox/process/execute route now 404s).
// Resolve the proxy URL once per sandbox and reuse it for every call.
const toolboxUrlCache = new Map<string, string>();

async function toolboxBase(sandboxId: string): Promise<string> {
  const hit = toolboxUrlCache.get(sandboxId);
  if (hit) return hit;
  const data = await daytonaJson<{ url: string }>(
    `/sandbox/${sandboxId}/toolbox-proxy-url`,
    {},
    30_000
  );
  toolboxUrlCache.set(sandboxId, data.url);
  return data.url;
}

async function execInSandbox(
  id: string,
  command: string,
  timeoutSec = 60,
  cwd = HOME_DIR
): Promise<{ exitCode: number; result: string }> {
  const base = await toolboxBase(id);
  const res = await fetch(`${base}/${id}/process/execute`, {
    method: "POST",
    headers: { ...daytonaHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ command, cwd, timeout: timeoutSec }),
    signal: AbortSignal.timeout((timeoutSec + 30) * 1000),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Daytona process/execute failed (${res.status}): ${body.slice(0, 300)}`);
  }
  const data = (await res.json().catch(() => null)) as {
    exitCode?: number;
    result?: string;
  } | null;
  return { exitCode: data?.exitCode ?? 0, result: data?.result ?? "" };
}

async function uploadFile(
  sandboxId: string,
  remotePath: string,
  content: string
): Promise<void> {
  const base = await toolboxBase(sandboxId);
  const form = new FormData();
  form.append(
    "file",
    new Blob([content], { type: "application/octet-stream" }),
    remotePath.split("/").pop() ?? "file"
  );
  const res = await fetch(
    `${base}/${sandboxId}/files/upload-v2?path=${encodeURIComponent(remotePath)}`,
    { method: "POST", headers: daytonaHeaders(), body: form },
  );
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Upload of ${remotePath} failed (${res.status}): ${body.slice(0, 200)}`);
  }
}

async function uploadAppFiles(
  sandboxId: string,
  files: { path: string; content: string }[]
): Promise<void> {
  const dirs = new Set<string>();
  for (const f of files) {
    const idx = f.path.lastIndexOf("/");
    if (idx > 0) dirs.add(f.path.slice(0, idx));
  }
  let mkdir = `mkdir -p ${APP_DIR}`;
  for (const d of dirs) mkdir += ` ${APP_DIR}/${d}`;
  await execInSandbox(sandboxId, mkdir, 30);
  await Promise.all(
    files.map((f) => uploadFile(sandboxId, `${APP_DIR}/${f.path}`, f.content))
  );
}

async function startStaticServer(sandboxId: string): Promise<void> {
  const start =
    `if ! pgrep -f "http.server ${PORT}" >/dev/null; then ` +
    `nohup python3 -m http.server ${PORT} --bind 0.0.0.0 --directory ${APP_DIR} ` +
    `>/tmp/forge-server.log 2>&1 & fi; sleep 1; ` +
    `curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/`;
  for (let attempt = 0; attempt < 5; attempt++) {
    const out = await execInSandbox(sandboxId, start, 30);
    if (out.result.trim().endsWith("200")) return;
    await sleep(1500);
  }
  const log = await execInSandbox(
    sandboxId,
    "tail -5 /tmp/forge-server.log 2>/dev/null || true",
    15
  );
  throw new Error(`Web server failed to start: ${log.result.slice(0, 200)}`);
}

async function getPreviewUrl(sandboxId: string): Promise<string> {
  const data = await daytonaJson<{ url: string }>(
    `/sandbox/${sandboxId}/ports/${PORT}/preview-url`
  );
  return data.url;
}

async function waitForPreview(url: string, timeoutMs = 30_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(8_000) });
      if (res.ok) return;
    } catch {
      // proxy not ready yet
    }
    await sleep(2_000);
  }
}

// ---------------------------------------------------------------------------
// Chorus REST helpers (mobile projects) — https://ios.chorus.com/llms.txt
// ---------------------------------------------------------------------------

function chorusBase(): string {
  return process.env.CHORUS_API_URL ?? "https://ios.chorus.com";
}

function chorusKey(): string {
  const key = process.env.CHORUS_API_KEY;
  if (!key) throw new Error("CHORUS_API_KEY is not set on the Convex deployment");
  return key;
}

function chorusUserId(): string {
  const id = process.env.CHORUS_USER_ID;
  if (!id) throw new Error("CHORUS_USER_ID is not set on the Convex deployment");
  return id;
}

function chorusConfigured(): boolean {
  return Boolean(process.env.CHORUS_API_KEY && process.env.CHORUS_USER_ID);
}

async function chorus(
  path: string,
  init: RequestInit = {},
  timeoutMs = 60_000
): Promise<Response> {
  return await fetch(`${chorusBase()}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${chorusKey()}`, ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(timeoutMs),
  });
}

async function chorusJson<T>(
  path: string,
  init: RequestInit = {},
  timeoutMs = 60_000
): Promise<T> {
  const res = await chorus(path, init, timeoutMs);
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(
      `Chorus ${init.method ?? "GET"} ${path} failed (${res.status}): ${body.slice(0, 300)}`
    );
  }
  return (await res.json()) as T;
}

function bundleIdFor(name: string, projectId: string): string {
  const slug =
    name.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20) || "app";
  return `com.keithable.app.${slug}${projectId.slice(-6).toLowerCase()}`;
}

async function zipMobileProject(
  name: string,
  bundleId: string,
  files: { path: string; content: string }[]
): Promise<Blob> {
  const zip = new JSZip();
  zip.file("App/App.xcodeproj/project.pbxproj", renderPbxproj(name, bundleId));
  zip.file("App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", XCSCHEME);
  zip.file("App/App/Assets.xcassets/Contents.json", ASSETS_ROOT_JSON);
  zip.file("App/App/Assets.xcassets/AppIcon.appiconset/Contents.json", ASSETS_APPICON_JSON);
  zip.file("App/App/Assets.xcassets/AccentColor.colorset/Contents.json", ASSETS_ACCENT_JSON);
  for (const f of files) {
    zip.file(`App/App/${f.path}`, f.content);
  }
  const bytes = await zip.generateAsync({ type: "arraybuffer" });
  return new Blob([bytes], { type: "application/zip" });
}

type SimPreview = { simBuildId: string; previewUrl: string };

async function mintSimPreview(projectId: string, buildJobId: string): Promise<SimPreview> {
  return await chorusJson<SimPreview>(
    "/api/sim-preview",
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-project-id": `forge-${projectId}` },
      body: JSON.stringify({ buildJobId }),
    },
    90_000
  );
}

/// Kick off a Chorus cloud build for the project's current files and schedule
/// polling until it completes.
async function startMobileBuild(
  ctx: ActionCtx,
  projectId: Id<"projects">,
  name: string,
  summary: string,
  files: { path: string; content: string }[],
  isEdit: boolean,
  repairCount = 0
): Promise<void> {
  if (!chorusConfigured()) {
    await queueMacMobileBuild(ctx, projectId);
    return;
  }
  await setStatus(ctx, projectId, "building", "Compiling your iOS app in the cloud (2–5 min)");
  await log(ctx, projectId, "📦 Uploading source to Chorus…");
  const bundleId = bundleIdFor(name, projectId);
  const zipBlob = await zipMobileProject(name, bundleId, files);
  const form = new FormData();
  form.append("file", zipBlob, "source.zip");
  const job = await chorusJson<{ buildJobId: string }>(
    "/api/build",
    {
      method: "POST",
      headers: { "x-project-id": `forge-${projectId}` },
      body: form,
    },
    180_000
  );
  await ctx.runMutation(internal.projects.update, {
    id: projectId,
    buildJobId: job.buildJobId,
  });
  await log(ctx, projectId, "🏗️ Cloud build started (Xcode on macOS)…");
  await ctx.scheduler.runAfter(15_000, internal.builder.pollMobileBuild, {
    projectId,
    buildJobId: job.buildJobId,
    attempts: 0,
    isEdit,
    summary,
    repairCount,
  });
}

async function queueMacMobileBuild(
  ctx: ActionCtx,
  projectId: Id<"projects">
): Promise<void> {
  await ctx.runMutation(internal.projects.update, {
    id: projectId,
    status: "mac_queued",
    statusDetail: "Waiting for your Mac to compile the iPhone app",
    clearError: true,
  });
  await log(
    ctx,
    projectId,
    "💻 Mobile build queued for your Mac. Keep Keithable open here; the Mac worker will compile it with Xcode and report back.",
    "agent"
  );
}

/// Pull deduplicated `file.swift:line: error: …` lines out of the Azure build
/// logs, stripped of timestamps and runner paths.
async function extractBuildErrors(buildJobId: string): Promise<string[]> {
  try {
    const data = await chorusJson<{ logs: { text: string }[] }>(
      `/api/build-jobs/${buildJobId}/logs`,
      {},
      60_000
    );
    const all = data.logs.map((l) => l.text).join("\n");
    const seen = new Set<string>();
    const errors: string[] = [];
    for (const line of all.split("\n")) {
      if (!line.includes("error: ")) continue;
      const cleaned = line
        .replace(/^\S+Z\s+/, "")
        .replace(/^.*\/App\/App\//, "")
        .trim();
      if (!seen.has(cleaned)) {
        seen.add(cleaned);
        errors.push(cleaned);
      }
    }
    return errors;
  } catch {
    return [];
  }
}

async function postLoginLink(
  ctx: ActionCtx,
  projectId: Id<"projects">
): Promise<void> {
  try {
    const link = await chorusJson<{ url: string }>(
      "/api/auth/login-link",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId: chorusUserId() }),
      },
      60_000
    );
    await log(
      ctx,
      projectId,
      `🔐 I need access to your Apple Developer account to sign apps.\n\n[Connect your Apple account](${link.url}) — the link expires in 10 minutes. Once you've signed in, ask me for the download link again.`,
      "agent"
    );
  } catch (err) {
    await log(
      ctx,
      projectId,
      `❌ Couldn't prepare an Apple sign-in link: ${errorMessage(err)}`,
      "agent"
    );
  }
}

// ---------------------------------------------------------------------------
// Free AI code generation (Gemini → Groq → OpenRouter fallback chain)
// ---------------------------------------------------------------------------

const OUTPUT_FORMAT = `OUTPUT FORMAT — follow EXACTLY, with no markdown fences and no commentary before or after:
APP_NAME: <catchy app name, 18 characters max>
APP_EMOJI: <exactly one emoji>
SUMMARY: <one short sentence about what you built>
===FILE: index.html===
<complete file contents>
===END FILE===
===FILE: app.js===
<complete file contents>
===END FILE===`;

const DESIGN_RULES = `RULES:
- Static site only: HTML + CSS + JS. No build step, no npm, no server-side code. Files are served as-is by a static file server.
- index.html is REQUIRED. Put JS in app.js when it exceeds ~80 lines; add style.css for substantial custom CSS. 2-4 files total.
- Tailwind CSS is allowed via <script src="https://cdn.tailwindcss.com"></script>. CDN libraries (unpkg/jsdelivr) are allowed when genuinely useful: Chart.js, Three.js, Tone.js, canvas-confetti, marked, dayjs.
- Use localStorage when the app needs to remember things.
- DESIGN BAR IS HIGH. This must look like a polished product, not a demo: a deliberate color palette with one strong accent, generous spacing, smooth transitions and micro-animations, hover/active states, refined typography (Google Fonts allowed), tasteful gradients or glassmorphism. Default to a dark UI unless the request implies light.
- MOBILE-FIRST: it renders inside an iPhone WebView. Include <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">. Big touch targets, no hover-only interactions, respect safe areas.
- Everything must WORK. Every button does something real. No placeholders, no dead links, no TODOs, no console errors.
- Keep the whole app under ~700 lines total.`;

const GENERATE_SYSTEM = `You are Keithable, an elite web-app builder. You produce complete, beautiful, fully-working single-page web apps from a short request.

${OUTPUT_FORMAT}

${DESIGN_RULES}`;

const EDIT_SYSTEM = `You are Keithable, an elite web-app builder. You are updating an existing app. You receive the app's current files, recent conversation, and a change request. Re-output the ENTIRE app — every file in full, including unchanged files. Files you omit will be DELETED. Keep the existing APP_NAME and APP_EMOJI unless the user asks to change them; SUMMARY should describe what you changed.

${OUTPUT_FORMAT}

${DESIGN_RULES}`;

const MOBILE_OUTPUT_FORMAT = `OUTPUT FORMAT — follow EXACTLY, with no markdown fences and no commentary before or after:
APP_NAME: <catchy app name, 18 characters max>
APP_EMOJI: <exactly one emoji>
SUMMARY: <one short sentence about what you built>
===FILE: WeatherApp.swift===
<complete file contents>
===END FILE===
===FILE: ContentView.swift===
<complete file contents>
===END FILE===`;

const MOBILE_RULES = `RULES:
- Pure SwiftUI targeting iOS 17. You may use iOS 17 APIs (@Observable, ContentUnavailableView, spring animations) but NOTHING newer than iOS 17.
- 2-5 .swift files with flat PascalCase names like TimerApp.swift, ContentView.swift, Models.swift. No folders, no asset-catalog images, no Info.plist or Xcode project changes.
- EXACTLY ONE file declares \`@main struct SomethingApp: App\`.
- If a file declares ObservableObject or uses @Published it MUST \`import Combine\` (strict member-import visibility). Prefer @Observable from the Observation framework instead.
- The project compiles with default MainActor isolation — write simple main-actor SwiftUI. Avoid Task.detached, custom actors, and Sendable tricks.
- No external packages. No special capabilities or entitlements (no camera, location, push, HealthKit). Avoid network calls; prefer realistic local/simulated data.
- Persist small user data with @AppStorage or UserDefaults.
- Visuals come from SF Symbols, SwiftUI shapes, and gradients only (no image assets).
- DESIGN BAR IS HIGH: this must feel like a polished App Store app — dark theme by default, tasteful gradients, smooth spring animations, generous spacing, rounded cards, haptics via UIImpactFeedbackGenerator (importing UIKit just for haptics is fine).
- Everything must WORK. Every button does something real. No placeholders, no TODOs.
- Keep the whole app under ~600 lines total.`;

const MOBILE_GENERATE_SYSTEM = `You are Keithable, an elite iOS engineer. You produce complete, beautiful, fully-working SwiftUI apps from a short request.

${MOBILE_OUTPUT_FORMAT}

${MOBILE_RULES}`;

const MOBILE_EDIT_SYSTEM = `You are Keithable, an elite iOS engineer. You are updating an existing SwiftUI app. You receive the app's current files, recent conversation, and a change request. Re-output the ENTIRE app — every file in full, including unchanged files. Files you omit will be DELETED. Keep the existing APP_NAME and APP_EMOJI unless the user asks to change them; SUMMARY should describe what you changed.

${MOBILE_OUTPUT_FORMAT}

${MOBILE_RULES}`;

const MOBILE_FIX_SYSTEM = `You are Keithable, an elite iOS engineer. The SwiftUI app below FAILED to compile. Fix every compiler error and re-output the ENTIRE app — every file in full, including unchanged files. Do not change the app's design or features beyond what the fixes require. Keep the existing APP_NAME and APP_EMOJI; SUMMARY should stay a description of the app (not the fix).

${MOBILE_OUTPUT_FORMAT}

${MOBILE_RULES}`;

function fixUserPrompt(
  files: { path: string; content: string }[],
  errors: string[]
): string {
  const fileBlock = files
    .map((f) => `===FILE: ${f.path}===\n${f.content}\n===END FILE===`)
    .join("\n");
  return `CURRENT FILES:\n${fileBlock}\n\nCOMPILER ERRORS:\n${errors.join("\n")}\n\nFix all compiler errors and output the complete corrected app.`;
}

/// Teach the generator that every app has free access to the AI proxy
/// (keyless free models, injected server-side by convex/http.ts).
function aiSkill(platform: "web" | "mobile"): string {
  const site = process.env.CONVEX_SITE_URL;
  if (!site) return "";
  const endpoint = `${site}/ai/chat/completions`;
  if (platform === "web") {
    return `

AI SKILL — every app you build has FREE access to a built-in AI endpoint (auth is injected server-side; never put an API key in your code and never ask the user for one). Use it whenever the request involves AI: chatbots, writing, summarizing, brainstorming, translation, Q&A, analysis, content generation.
- const res = await fetch("${endpoint}", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ model: "gemini-2.5-flash", messages: [{ role: "user", content: prompt }] }) });
- OpenAI-compatible response: (await res.json()).choices[0].message.content
- Models: any id works — the proxy routes to free models server-side (Gemini/Groq/OpenRouter). "gemini-2.5-flash" is the fast default.
- Non-streaming only. Always show a visible loading/thinking state while waiting and a friendly inline error if the call fails.`;
  }
  return `

AI SKILL — every app you build has FREE access to a built-in AI endpoint (auth is injected server-side; never embed an API key and never ask the user for one). Use it whenever the request involves AI: chatbots, writing, summarizing, brainstorming, translation, Q&A, analysis.
- POST ${endpoint} via URLSession with header Content-Type: application/json and JSON body {"model":"gemini-2.5-flash","messages":[{"role":"user","content":"..."}]}
- Decode the OpenAI-compatible response and read choices[0].message.content
- Models: any id works — the proxy routes to free models server-side (Gemini/Groq/OpenRouter)
- Calls to THIS endpoint are allowed and encouraged (the avoid-network-calls rule does not apply to it). Show a loading state while waiting; handle failures with a friendly message.`;
}

type GeneratedApp = {
  name: string;
  emoji: string;
  summary: string;
  files: { path: string; content: string }[];
};

function sanitizeSwiftName(path: string): string {
  const base = path.split("/").pop() ?? "File.swift";
  let stem = base.replace(/\.swift$/i, "").replace(/[^A-Za-z0-9_]/g, "");
  if (!stem) stem = "File";
  return `${stem}.swift`;
}

function parseGeneration(text: string, platform: "web" | "mobile"): GeneratedApp {
  const name = /^APP_NAME:\s*(.+)$/m.exec(text)?.[1]?.trim() ?? "Untitled App";
  const emoji = /^APP_EMOJI:\s*(\S+)/m.exec(text)?.[1]?.trim() ?? "✨";
  const summary = /^SUMMARY:\s*(.+)$/m.exec(text)?.[1]?.trim() ?? "";
  let files: { path: string; content: string }[] = [];
  const re = /===FILE:\s*([^=\n]+?)\s*===\n([\s\S]*?)\n?===END FILE===/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(text)) !== null) {
    const path = match[1].trim().replace(/^\/+/, "");
    if (!path || path.includes("..")) continue;
    files.push({ path, content: match[2] });
  }
  if (platform === "mobile") {
    const seen = new Set<string>();
    files = files
      .filter((f) => f.path.toLowerCase().endsWith(".swift"))
      .map((f) => ({ path: sanitizeSwiftName(f.path), content: f.content }))
      .filter((f) => (seen.has(f.path) ? false : (seen.add(f.path), true)));
    if (files.length === 0) {
      throw new Error("The generated app has no Swift files — try again");
    }
    if (!files.some((f) => f.content.includes("@main"))) {
      throw new Error("The generated app is missing an @main entry point — try again");
    }
  } else if (!files.some((f) => f.path === "index.html")) {
    throw new Error("The generated app is missing index.html — try again");
  }
  return { name: name.slice(0, 30), emoji, summary, files };
}

function buildUserPrompt(prompt: string, platform: "web" | "mobile"): string {
  return platform === "mobile" ? `Build this iOS app: ${prompt}` : `Build this web app: ${prompt}`;
}

function editUserPrompt(
  files: { path: string; content: string }[],
  conversation: { role: string; content: string }[],
  request: string
): string {
  const fileBlock = files
    .map((f) => `===FILE: ${f.path}===\n${f.content}\n===END FILE===`)
    .join("\n");
  const convo = conversation
    .filter((m) => m.role === "user" || m.role === "agent")
    .slice(-10)
    .map((m) => `${m.role}: ${m.content}`)
    .join("\n");
  return `CURRENT FILES:\n${fileBlock}\n\nRECENT CONVERSATION:\n${convo}\n\nCHANGE REQUEST: ${request}`;
}

// ---------------------------------------------------------------------------
// Status plumbing
// ---------------------------------------------------------------------------

async function setStatus(
  ctx: ActionCtx,
  projectId: Id<"projects">,
  status: string,
  statusDetail: string
): Promise<void> {
  await ctx.runMutation(internal.projects.update, { id: projectId, status, statusDetail });
}

async function log(
  ctx: ActionCtx,
  projectId: Id<"projects">,
  content: string,
  role = "log"
): Promise<void> {
  await ctx.runMutation(internal.messages.log, { projectId, role, content });
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

// ---------------------------------------------------------------------------
// Web actions (Daytona)
// ---------------------------------------------------------------------------

export const build = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project) return null;
    try {
      if (project.sandboxId) {
        await daytona(`/sandbox/${project.sandboxId}`, { method: "DELETE" }).catch(() => {});
      }

      await setStatus(ctx, projectId, "generating", "Free AI is designing your app");
      await log(ctx, projectId, "🧠 Free AI is writing your app…");
      const raw = await callFreeModel(GENERATE_SYSTEM + aiSkill("web"), buildUserPrompt(project.prompt, "web"), resolveModel(project.model), preferredProvider(project.model));
      const app = parseGeneration(raw, "web");
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        name: app.name,
        emoji: app.emoji,
      });
      await ctx.runMutation(internal.files.saveAll, { projectId, files: app.files });
      await log(
        ctx,
        projectId,
        `📁 Generated ${app.files.length} file${app.files.length === 1 ? "" : "s"}: ${app.files
          .map((f) => f.path)
          .join(", ")}`
      );

      await setStatus(ctx, projectId, "sandbox", "Spinning up a cloud sandbox");
      await log(ctx, projectId, "📦 Creating a Daytona sandbox…");
      const sandboxId = await createSandbox();
      await ctx.runMutation(internal.projects.update, { id: projectId, sandboxId });

      await setStatus(ctx, projectId, "uploading", "Uploading your code");
      await log(ctx, projectId, "⬆️ Uploading files to the sandbox…");
      await uploadAppFiles(sandboxId, app.files);

      await setStatus(ctx, projectId, "starting", "Starting the web server");
      await log(ctx, projectId, "🚀 Starting the web server…");
      await startStaticServer(sandboxId);
      const previewUrl = await getPreviewUrl(sandboxId);
      await waitForPreview(previewUrl);

      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "live",
        statusDetail: "Live",
        previewUrl,
        version: project.version + 1,
        clearError: true,
      });
      await log(
        ctx,
        projectId,
        app.summary ? `✅ ${app.name} is live! ${app.summary}` : `✅ ${app.name} is live!`,
        "agent"
      );
    } catch (err) {
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "error",
        statusDetail: "Build failed",
        error: errorMessage(err),
      });
      await log(ctx, projectId, `❌ Build failed: ${errorMessage(err)}`, "agent");
    }
    return null;
  },
});

export const edit = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project) return null;
    try {
      const files = await ctx.runQuery(internal.files.getAll, { projectId });
      if (files.length === 0) throw new Error("No files yet — rebuild the app first");
      const conversation = await ctx.runQuery(internal.messages.recent, {
        projectId,
        limit: 30,
      });
      const request =
        [...conversation].reverse().find((m) => m.role === "user")?.content ?? project.prompt;

      await setStatus(ctx, projectId, "updating", "Free AI is applying your changes");
      await log(ctx, projectId, "🛠️ Free AI is updating your app…");
      const raw = await callFreeModel(
        EDIT_SYSTEM + aiSkill("web"),
        editUserPrompt(
          files.map((f) => ({ path: f.path, content: f.content })),
          conversation,
          request
        ),
        resolveModel(project.model), preferredProvider(project.model)
      );
      const app = parseGeneration(raw, "web");
      await ctx.runMutation(internal.files.saveAll, { projectId, files: app.files });
      if (app.name !== project.name || app.emoji !== project.emoji) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          name: app.name,
          emoji: app.emoji,
        });
      }

      let sandboxId = project.sandboxId;
      const existing = sandboxId ? await getSandbox(sandboxId).catch(() => null) : null;
      if (!existing || ["destroyed", "error", "build_failed"].includes(existing.state)) {
        await setStatus(ctx, projectId, "sandbox", "Spinning up a fresh sandbox");
        await log(ctx, projectId, "📦 Creating a Daytona sandbox…");
        sandboxId = await createSandbox();
        await ctx.runMutation(internal.projects.update, { id: projectId, sandboxId });
      } else if (existing.state !== "started") {
        await setStatus(ctx, projectId, "waking", "Waking the sandbox");
        await log(ctx, projectId, "☀️ Waking the sandbox…");
        await startSandbox(sandboxId!);
      }

      await setStatus(ctx, projectId, "uploading", "Uploading changes");
      await log(ctx, projectId, "⬆️ Uploading changes…");
      await uploadAppFiles(sandboxId!, app.files);
      await startStaticServer(sandboxId!);
      const previewUrl = await getPreviewUrl(sandboxId!);

      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "live",
        statusDetail: "Live",
        previewUrl,
        version: project.version + 1,
        clearError: true,
      });
      await log(ctx, projectId, app.summary ? `✅ Updated! ${app.summary}` : "✅ Updated!", "agent");
    } catch (err) {
      const fallbackLive = Boolean(project.previewUrl);
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: fallbackLive ? "live" : "error",
        statusDetail: fallbackLive ? "Live (last update failed)" : "Update failed",
        error: errorMessage(err),
      });
      await log(ctx, projectId, `❌ Update failed: ${errorMessage(err)}`, "agent");
    }
    return null;
  },
});

export const ensureRunning = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project || project.status !== "live") return null;

    // Mobile: re-mint the tokenized simulator preview if it stopped serving.
    if (project.platform === "mobile") {
      if (!project.buildJobId || !project.previewUrl) return null;
      try {
        const probe = await fetch(project.previewUrl, {
          signal: AbortSignal.timeout(8_000),
        });
        if (probe.ok) return null;
      } catch {
        // unreachable — fall through and re-mint
      }
      try {
        const preview = await mintSimPreview(projectId, project.buildJobId);
        if (preview.previewUrl && preview.previewUrl !== project.previewUrl) {
          await ctx.runMutation(internal.projects.update, {
            id: projectId,
            previewUrl: preview.previewUrl,
            simBuildId: preview.simBuildId,
            version: project.version + 1,
          });
        }
      } catch {
        // keep the existing preview URL
      }
      return null;
    }

    if (!project.sandboxId) return null;
    try {
      const sb = await getSandbox(project.sandboxId);
      if (sb.state === "started") {
        await startStaticServer(project.sandboxId);
        return null;
      }
      if (["stopped", "stopping", "archived"].includes(sb.state)) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "waking",
          statusDetail: "Waking your app",
        });
        if (sb.state === "stopping") {
          await waitForSandboxState(project.sandboxId, "stopped", 60_000);
        }
        await startSandbox(project.sandboxId);
        await startStaticServer(project.sandboxId);
        const previewUrl = await getPreviewUrl(project.sandboxId);
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "Live",
          previewUrl,
          version: project.version + 1,
        });
        await log(ctx, projectId, "☀️ Woke your app back up");
      }
    } catch {
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "live",
        statusDetail: "Preview may be sleeping — try again",
      });
    }
    return null;
  },
});

export const destroySandbox = internalAction({
  args: { sandboxId: v.string() },
  returns: v.null(),
  handler: async (_ctx, { sandboxId }) => {
    await daytona(`/sandbox/${sandboxId}`, { method: "DELETE" }, 60_000).catch(() => {});
    return null;
  },
});

/// Weekly disk sweep (2026-09-30): stopped sandboxes keep their disk, which
/// is how the free 30 GiB tier got exhausted. Destroy sandboxes that are
/// older than the idle window AND whose project hasn't been touched in that
/// window (or that no project references any more). Active builds and anything
/// newer than the window are never touched; `projects:remove` still destroys
/// its own sandbox immediately.
export const sweepSandboxes = internalAction({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const projects = await ctx.runQuery(internal.projects.allInternal, {});
    const bySandbox = new Map(
      projects.filter((p) => p.sandboxId).map((p) => [p.sandboxId as string, p])
    );
    const listing = await daytonaJson<{ items: { id: string; createdAt?: string }[] }>(
      "/sandbox"
    );
    const cutoff = Date.now() - 14 * 24 * 60 * 60 * 1000;
    for (const sb of listing.items ?? []) {
      const created = Date.parse(sb.createdAt ?? "");
      if (!Number.isFinite(created) || created >= cutoff) continue; // grace period
      const project = bySandbox.get(sb.id);
      if (project && project.updatedAt >= cutoff) continue; // still in active use
      await daytona(`/sandbox/${sb.id}`, { method: "DELETE" }, 60_000).catch(() => {});
    }
    return null;
  },
});

// ---------------------------------------------------------------------------
// Mobile actions (Chorus)
// ---------------------------------------------------------------------------

export const buildMobile = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project) return null;
    try {
      await setStatus(ctx, projectId, "generating", "Free AI is designing your iOS app");
      await log(ctx, projectId, "🧠 Free AI is writing your iOS app in Swift…");
      const raw = await callFreeModel(
        MOBILE_GENERATE_SYSTEM + aiSkill("mobile"),
        buildUserPrompt(project.prompt, "mobile"),
        resolveModel(project.model), preferredProvider(project.model)
      );
      const app = parseGeneration(raw, "mobile");
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        name: app.name,
        emoji: app.emoji,
      });
      await ctx.runMutation(internal.files.saveAll, { projectId, files: app.files });
      await log(
        ctx,
        projectId,
        `📁 Generated ${app.files.length} Swift file${app.files.length === 1 ? "" : "s"}: ${app.files
          .map((f) => f.path)
          .join(", ")}`
      );
      await startMobileBuild(ctx, projectId, app.name, app.summary, app.files, false);
    } catch (err) {
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "error",
        statusDetail: "Build failed",
        error: errorMessage(err),
      });
      await log(ctx, projectId, `❌ Build failed: ${errorMessage(err)}`, "agent");
    }
    return null;
  },
});

export const editMobile = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project) return null;
    try {
      const files = await ctx.runQuery(internal.files.getAll, { projectId });
      if (files.length === 0) throw new Error("No files yet — rebuild the app first");
      const conversation = await ctx.runQuery(internal.messages.recent, {
        projectId,
        limit: 30,
      });
      const request =
        [...conversation].reverse().find((m) => m.role === "user")?.content ?? project.prompt;

      await setStatus(ctx, projectId, "updating", "Free AI is applying your changes");
      await log(ctx, projectId, "🛠️ Free AI is updating your iOS app…");
      const raw = await callFreeModel(
        MOBILE_EDIT_SYSTEM + aiSkill("mobile"),
        editUserPrompt(
          files.map((f) => ({ path: f.path, content: f.content })),
          conversation,
          request
        ),
        resolveModel(project.model), preferredProvider(project.model)
      );
      const app = parseGeneration(raw, "mobile");
      await ctx.runMutation(internal.files.saveAll, { projectId, files: app.files });
      if (app.name !== project.name || app.emoji !== project.emoji) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          name: app.name,
          emoji: app.emoji,
        });
      }
      await startMobileBuild(ctx, projectId, app.name, app.summary, app.files, true);
    } catch (err) {
      const fallbackLive = Boolean(project.previewUrl);
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: fallbackLive ? "live" : "error",
        statusDetail: fallbackLive ? "Live (last update failed)" : "Update failed",
        error: errorMessage(err),
      });
      await log(ctx, projectId, `❌ Update failed: ${errorMessage(err)}`, "agent");
    }
    return null;
  },
});

export const pollMobileBuild = internalAction({
  args: {
    projectId: v.id("projects"),
    buildJobId: v.string(),
    attempts: v.number(),
    isEdit: v.boolean(),
    summary: v.string(),
    repairCount: v.optional(v.number()),
  },
  returns: v.null(),
  handler: async (ctx, { projectId, buildJobId, attempts, isEdit, summary, repairCount }) => {
    const repairs = repairCount ?? 0;
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    // Bail on stale polls (project deleted or superseded by a newer build).
    if (!project || project.buildJobId !== buildJobId) return null;
    try {
      const job = await chorusJson<{ state: string; error: string | null; appUrl: string | null }>(
        `/api/build-jobs/${buildJobId}`
      );
      if (job.state === "built") {
        const preview = await mintSimPreview(projectId, buildJobId);
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "Live",
          previewUrl: preview.previewUrl,
          simBuildId: preview.simBuildId,
          appUrl: job.appUrl ?? undefined,
          version: project.version + 1,
          clearError: true,
        });
        const headline = isEdit
          ? summary
            ? `✅ Updated! ${summary}`
            : "✅ Updated!"
          : summary
            ? `✅ ${project.name} is live! ${summary}`
            : `✅ ${project.name} is live!`;
        await log(
          ctx,
          projectId,
          `${headline}\n\n📲 Want it on your iPhone? Ask me for the download link.`,
          "agent"
        );
        return null;
      }
      if (job.state === "failed") {
        const errors = await extractBuildErrors(buildJobId);
        // Self-heal: feed compiler errors back to the free model and rebuild.
        if (repairs < 2 && errors.length > 0) {
          await setStatus(
            ctx,
            projectId,
            "generating",
            "Build hit compile errors — Free AI is fixing them"
          );
          await log(
            ctx,
            projectId,
            `🔧 Compile ${errors.length === 1 ? "error" : "errors"} found — Free AI is fixing ${errors.length === 1 ? "it" : "them"}…`
          );
          const files = await ctx.runQuery(internal.files.getAll, { projectId });
          const raw = await callFreeModel(
            MOBILE_FIX_SYSTEM + aiSkill("mobile"),
            fixUserPrompt(
              files.map((f) => ({ path: f.path, content: f.content })),
              errors.slice(0, 8)
            ),
            resolveModel(project.model), preferredProvider(project.model)
          );
          const app = parseGeneration(raw, "mobile");
          await ctx.runMutation(internal.files.saveAll, { projectId, files: app.files });
          await startMobileBuild(
            ctx,
            projectId,
            project.name,
            summary || app.summary,
            app.files,
            isEdit,
            repairs + 1
          );
          return null;
        }
        const detail =
          errors.slice(0, 2).join(" · ").slice(0, 400) ||
          job.error?.slice(0, 300) ||
          "Cloud build failed — try rebuilding";
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "error",
          statusDetail: "Cloud build failed",
          error: detail,
        });
        await log(ctx, projectId, `❌ Cloud build failed: ${detail}`, "agent");
        return null;
      }
      // Still building.
      if (attempts >= 60) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "error",
          statusDetail: "Cloud build timed out",
          error: "The cloud build did not finish in 15 minutes — try rebuilding",
        });
        await log(ctx, projectId, "❌ The cloud build timed out — try rebuilding.", "agent");
        return null;
      }
      if (attempts === 20) {
        await setStatus(
          ctx,
          projectId,
          "building",
          "Still compiling — the cloud queue can add a few minutes"
        );
      }
      await ctx.scheduler.runAfter(15_000, internal.builder.pollMobileBuild, {
        projectId,
        buildJobId,
        attempts: attempts + 1,
        isEdit,
        summary,
        repairCount: repairs,
      });
    } catch (err) {
      if (attempts >= 60) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "error",
          statusDetail: "Cloud build failed",
          error: errorMessage(err),
        });
        await log(ctx, projectId, `❌ Cloud build failed: ${errorMessage(err)}`, "agent");
        return null;
      }
      await ctx.scheduler.runAfter(20_000, internal.builder.pollMobileBuild, {
        projectId,
        buildJobId,
        attempts: attempts + 2,
        isEdit,
        summary,
        repairCount: repairs,
      });
    }
    return null;
  },
});

export const provideInstallLink = internalAction({
  args: { projectId: v.id("projects") },
  returns: v.null(),
  handler: async (ctx, { projectId }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project) return null;
    try {
      if (!project.appUrl) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "Live",
        });
        await log(
          ctx,
          projectId,
          "❌ I don't have a finished cloud build to sign yet — rebuild the app first, then ask again.",
          "agent"
        );
        return null;
      }
      if (/^\/|^file:/.test(project.appUrl)) {
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "IPA built on your Mac",
        });
        await log(
          ctx,
          projectId,
          `✅ ${project.name} is already built on your Mac.\n\nIPA: ${project.appUrl}\n\nCodex can sign and install this through Signulous from the Mac.`,
          "agent"
        );
        return null;
      }
      await setStatus(ctx, projectId, "signing", "Signing your app for your iPhone");
      await log(ctx, projectId, "🔏 Signing your app for device install…");
      const res = await chorus(
        "/api/sign",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            userId: chorusUserId(),
            appUrl: project.appUrl,
            projectId: `forge-${projectId}`,
          }),
        },
        90_000
      );
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "Live",
        });
        if (/authenticate|No saved Apple|User not found|session/i.test(body)) {
          await postLoginLink(ctx, projectId);
        } else {
          await log(ctx, projectId, `❌ Signing failed: ${body.slice(0, 250)}`, "agent");
        }
        return null;
      }
      const sign = (await res.json()) as { buildId: string; installUrl: string };
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        signBuildId: sign.buildId,
      });
      await ctx.scheduler.runAfter(10_000, internal.builder.pollSign, {
        projectId,
        signBuildId: sign.buildId,
        attempts: 0,
      });
    } catch (err) {
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "live",
        statusDetail: "Live",
      });
      await log(ctx, projectId, `❌ Signing failed: ${errorMessage(err)}`, "agent");
    }
    return null;
  },
});

export const pollSign = internalAction({
  args: {
    projectId: v.id("projects"),
    signBuildId: v.string(),
    attempts: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, { projectId, signBuildId, attempts }) => {
    const project = await ctx.runQuery(internal.projects.getInternal, { id: projectId });
    if (!project || project.signBuildId !== signBuildId) return null;
    const backToLive = async (detail = "Live") => {
      await ctx.runMutation(internal.projects.update, {
        id: projectId,
        status: "live",
        statusDetail: detail,
      });
    };
    try {
      const build = await chorusJson<{
        state: string;
        error: string | null;
        installUrl: string | null;
      }>(`/api/builds/${signBuildId}`);
      if (build.state === "signed") {
        const installUrl = build.installUrl ?? `${chorusBase()}/install/${signBuildId}`;
        await ctx.runMutation(internal.projects.update, {
          id: projectId,
          status: "live",
          statusDetail: "Live",
          installUrl,
          clearError: true,
        });
        await log(
          ctx,
          projectId,
          `📲 Your app is signed and ready!\n\n[Install ${project.name} on your iPhone](${installUrl})\n\nOpen the link in Safari on your phone and tap Install. If iOS asks, approve it in Settings → General → VPN & Device Management.`,
          "agent"
        );
        return null;
      }
      if (build.state === "failed") {
        await backToLive();
        const error = build.error ?? "Unknown signing error";
        if (/No registered iOS devices/i.test(error)) {
          await log(
            ctx,
            projectId,
            `📱 Your iPhone isn't registered for signing yet.\n\n[Register this iPhone](${chorusBase()}/register/${chorusUserId()}) — open that link on your phone, install the profile, then ask me for the download link again.`,
            "agent"
          );
        } else if (/authenticate|No saved Apple|session|auth/i.test(error)) {
          await postLoginLink(ctx, projectId);
        } else {
          await log(ctx, projectId, `❌ Signing failed: ${error.slice(0, 250)}`, "agent");
        }
        return null;
      }
      // pending | signing
      if (attempts >= 36) {
        await backToLive();
        await log(
          ctx,
          projectId,
          "❌ Signing timed out — ask me for the download link again in a minute.",
          "agent"
        );
        return null;
      }
      await ctx.scheduler.runAfter(10_000, internal.builder.pollSign, {
        projectId,
        signBuildId,
        attempts: attempts + 1,
      });
    } catch (err) {
      if (attempts >= 36) {
        await backToLive();
        await log(ctx, projectId, `❌ Signing failed: ${errorMessage(err)}`, "agent");
        return null;
      }
      await ctx.scheduler.runAfter(15_000, internal.builder.pollSign, {
        projectId,
        signBuildId,
        attempts: attempts + 2,
      });
    }
    return null;
  },
});
