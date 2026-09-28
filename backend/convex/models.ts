import type { FreeTier } from "./freeAi";

// Free model options the user can pick from. Keys are what the iOS app stores
// on a project (see the FreeModels mirror in ios/Sources); values are the
// routing tier used by freeAi.ts (provider chain with ordered fallback).
// The optional MODEL_PREFER map nudges the chain to start on the provider
// that actually serves that named model — a preference, never a hard pin;
// if that provider is missing or fails, the rest of the tier chain takes over.
export const MODEL_OPTIONS: Record<string, FreeTier> = {
  // Tier defaults (legacy keys, still accepted on old projects)
  "free-smart": "smart",
  "free-balanced": "balanced",
  "free-fast": "fast",
  // Displayed as "Fable 5" in the app; runs the smart tier under the hood.
  "fable-5": "smart",
  // Named models — each prefers the provider verified to serve it
  "gpt-oss-120": "smart",       // Groq  · openai/gpt-oss-120b
  "deepseek-v3": "smart",       // GitHub Models · deepseek/DeepSeek-V3
  "nemotron-3.5": "balanced",   // NVIDIA · nemotron-3.5-lightning-30b
  "qwen-3.8": "balanced",       // Cerebras · qwen-3.8-27b
  "llama-3.1-8b": "fast",       // Cloudflare · llama-3.1-8b-instruct-fp8
  "gpt-oss-20": "fast",         // Groq · openai/gpt-oss-20b
};

// Preferred first hop for named models (keys into freeAi's FreeProvider union).
export const MODEL_PREFER: Record<string, string> = {
  "gpt-oss-120": "groq",
  "deepseek-v3": "github",
  "nemotron-3.5": "nvidia",
  "qwen-3.8": "cerebras",
  "llama-3.1-8b": "cloudflare",
  "gpt-oss-20": "groq",
};

export const DEFAULT_MODEL_KEY = "free-balanced";

export function isAllowedModel(key: string): boolean {
  return key in MODEL_OPTIONS;
}

/// Map a stored model key to a free routing tier, falling back to the
/// default for unknown/missing values.
export function resolveModel(key: string | undefined | null): FreeTier {
  return MODEL_OPTIONS[key ?? DEFAULT_MODEL_KEY] ?? MODEL_OPTIONS[DEFAULT_MODEL_KEY];
}

/// Provider the chain should try first for this key (undefined = default order).
export function preferredProvider(key: string | undefined | null): string | undefined {
  if (!key) return undefined;
  return MODEL_PREFER[key];
}
