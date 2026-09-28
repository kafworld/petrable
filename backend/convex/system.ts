import { query } from "./_generated/server";
import { v } from "convex/values";

export const status = query({
  args: {},
  returns: v.object({
    webBuildsReady: v.boolean(),
    mobileBuildsReady: v.boolean(),
    voiceReady: v.boolean(),
    aiGatewayReady: v.boolean(),
  }),
  handler: async () => ({
    webBuildsReady: Boolean(
      (process.env.GEMINI_API_KEY || process.env.GROQ_API_KEY || process.env.OPENROUTER_API_KEY) &&
        process.env.DAYTONA_API_KEY
    ),
    mobileBuildsReady: Boolean(
      process.env.KEITHABLE_MAC_WORKER_ENABLED === "1" ||
        (process.env.CHORUS_API_KEY && process.env.CHORUS_USER_ID)
    ),
    voiceReady: Boolean(process.env.GROQ_API_KEY || process.env.OPENAI_API_KEY),
    aiGatewayReady: Boolean(
      process.env.GEMINI_API_KEY || process.env.GROQ_API_KEY || process.env.OPENROUTER_API_KEY
    ),
  }),
});
