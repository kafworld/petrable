"use node";

import { v } from "convex/values";
import { action } from "./_generated/server";

// Free-first transcription: Groq's Whisper endpoint is the default (free
// tier); OpenAI Whisper remains as an optional fallback if that key is also
// present. The key lives only on the deployment — never in the iOS app.

type SttProvider = { envKey: string; url: string; model: string };

function sttProviders(): SttProvider[] {
  const providers: SttProvider[] = [];
  if (process.env.GROQ_API_KEY) {
    providers.push({
      envKey: "GROQ_API_KEY",
      url: "https://api.groq.com/openai/v1/audio/transcriptions",
      model: process.env.GROQ_WHISPER_MODEL ?? "whisper-large-v3",
    });
  }
  if (process.env.OPENAI_API_KEY) {
    providers.push({
      envKey: "OPENAI_API_KEY",
      url: "https://api.openai.com/v1/audio/transcriptions",
      model: "whisper-1",
    });
  }
  return providers;
}

/// Transcribe a short voice recording (base64 m4a/AAC).
export const transcribe = action({
  args: { audioBase64: v.string() },
  returns: v.object({ text: v.string() }),
  handler: async (_ctx, { audioBase64 }) => {
    const providers = sttProviders();
    if (providers.length === 0) {
      throw new Error("No transcription key set — add GROQ_API_KEY on the Convex deployment");
    }
    const bytes = Buffer.from(audioBase64, "base64");
    if (bytes.length < 1_000) return { text: "" };
    if (bytes.length > 10_000_000) throw new Error("Recording too large");
    const audio = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);

    const failures: string[] = [];
    for (const provider of providers) {
      const key = process.env[provider.envKey];
      if (!key) continue;
      const form = new FormData();
      form.append("file", new Blob([audio], { type: "audio/m4a" }), "audio.m4a");
      form.append("model", provider.model);
      const res = await fetch(provider.url, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: form,
        signal: AbortSignal.timeout(60_000),
      });
      if (res.ok) {
        const data = (await res.json()) as { text?: string };
        return { text: (data.text ?? "").trim() };
      }
      const body = await res.text().catch(() => "");
      failures.push(`${provider.envKey} ${res.status}: ${body.slice(0, 200)}`);
    }
    throw new Error(`Transcription failed — ${failures.join(" · ")}`);
  },
});
