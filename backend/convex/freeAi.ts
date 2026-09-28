// Free-only generation router — no paid model providers, ever.
//
// Every provider below speaks the OpenAI chat-completions shape, so one
// request format serves all of them. Requests walk an ordered chain
// (Gemini → Groq → OpenRouter → NVIDIA → GitHub Models → Cerebras →
// Cloudflare, with "fast" starting on Groq); a provider with no API key is
// skipped, and a usable failure falls through to the next free endpoint.
// All keys live as Convex env vars — none ship in apps.

export type FreeTier = "fast" | "balanced" | "smart";

type FreeProvider =
  | "gemini"
  | "groq"
  | "openrouter"
  | "nvidia"
  | "github"
  | "cerebras"
  | "cloudflare";

type FreeEndpoint = {
  name: string;
  url: string;
  key: string;
  model: string;
};

const PROVIDER_URLS: Record<FreeProvider, string | ((acct: string) => string)> = {
  gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
  groq: "https://api.groq.com/openai/v1/chat/completions",
  openrouter: "https://openrouter.ai/api/v1/chat/completions",
  nvidia: "https://integrate.api.nvidia.com/v1/chat/completions",
  github: "https://models.github.ai/inference/chat/completions",
  cerebras: "https://api.cerebras.ai/v1/chat/completions",
  cloudflare: (acct) =>
    `https://api.cloudflare.com/client/v4/accounts/${acct}/ai/v1/chat/completions`,
};

const ATTEMPT_TIMEOUT_MS = 300_000;

function readEnv(name: string): string | undefined {
  const raw = process.env[name];
  return raw && raw.trim() ? raw.trim() : undefined;
}

function defaultModel(provider: FreeProvider, tier: FreeTier): string {
  // Every ID below was verified live against the provider (28 Sep 2026).
  if (provider === "gemini") return "gemini-3.8-flash";
  if (provider === "groq") return tier === "fast" ? "openai/gpt-oss-20b" : "openai/gpt-oss-120b";
  if (provider === "openrouter")
    return tier === "fast" ? "nvidia/nemotron-3.5-lightning:free" : "qwen/qwen3.8-27b:free";
  if (provider === "nvidia")
    return tier === "smart" ? "nvidia/nemotron-3-ultra-550b-a55b" : "nvidia/nemotron-3.5-lightning-30b-a3b";
  if (provider === "github") return tier === "smart" ? "deepseek/DeepSeek-V3" : "openai/gpt-4o-mini";
  if (provider === "cerebras") return tier === "fast" ? "llama-3.1-8b" : "llama-3.3-70b";
  return tier === "fast" ? "@cf/meta/llama-3.1-8b-instruct" : "@cf/meta/llama-3.3-70b-instruct";
}

function endpoint(provider: FreeProvider, tier: FreeTier): FreeEndpoint | null {
  const keyEnv = `${provider.toUpperCase()}_API_KEY`;
  const modelEnv = `${provider.toUpperCase()}_${tier.toUpperCase()}_MODEL`;
  const key = readEnv(keyEnv);
  if (!key) return null;
  const spec = PROVIDER_URLS[provider];
  let url: string;
  if (typeof spec === "function") {
    const acct = readEnv("CLOUDFLARE_ACCOUNT_ID");
    if (!acct) return null;
    url = spec(acct);
  } else {
    url = spec;
  }
  return {
    name: provider,
    url,
    key,
    model: readEnv(modelEnv) ?? defaultModel(provider, tier),
  };
}

/// Ordered fallback chain for a tier. Providers without keys drop out.
/// `prefer` (from the selected model key) is tried first, then the default
/// order — a preference, never a pin, so the chain still covers failures.
export function freeChain(tier: FreeTier, prefer?: string): FreeEndpoint[] {
  const order: FreeProvider[] =
    tier === "fast"
      ? ["groq", "gemini", "nvidia", "github", "openrouter", "cerebras", "cloudflare"]
      : ["gemini", "groq", "nvidia", "github", "openrouter", "cerebras", "cloudflare"];
  const first =
    prefer && prefer in PROVIDER_URLS ? [prefer as FreeProvider] : [];
  const ranked = [...first, ...order.filter((p) => !first.includes(p))];
  return ranked.map((p) => endpoint(p, tier)).filter((e): e is FreeEndpoint => e !== null);
}

/// Best-effort mapping of whatever model id a generated app asked the
/// `/ai/*` proxy for onto a free tier (the id itself is rewritten anyway).
export function tierForModelHint(model: string | undefined): FreeTier {
  if (!model) return "balanced";
  const m = model.toLowerCase();
  if (/pro|opus|sonnet|smart|o[0-9]|gpt-5/.test(m)) return "smart";
  if (/haiku|mini|flash|instant|8b|fast/.test(m)) return "fast";
  return "balanced";
}

function maxTokens(): number {
  const raw = Number(readEnv("FREE_MODEL_MAX_TOKENS"));
  return Number.isFinite(raw) && raw > 0 ? raw : 16_000;
}

function isTimeout(err: unknown): boolean {
  return err instanceof Error && (err.name === "TimeoutError" || err.name === "AbortError");
}

function fail(err: unknown): never {
  throw err instanceof Error ? err : new Error(String(err));
}

async function requestCompletion(ep: FreeEndpoint, payload: Record<string, unknown>): Promise<Response> {
  return fetch(ep.url, {
    method: "POST",
    headers: { Authorization: `Bearer ${ep.key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ...payload, model: ep.model }),
    signal: AbortSignal.timeout(ATTEMPT_TIMEOUT_MS),
  });
}

/// One provider attempt: tolerates a provider rejecting the token budget by
/// retrying once at a lower `max_tokens`, otherwise surfaces the failure so
/// the chain can fall through.
async function attempt(ep: FreeEndpoint, payload: Record<string, unknown>): Promise<string> {
  let body = { ...payload, max_tokens: maxTokens() };
  for (let round = 0; round < 2; round++) {
    const res = await requestCompletion(ep, body);
    if (res.ok) {
      const data = (await res.json().catch(() => null)) as {
        choices?: { message?: { content?: string } }[];
      } | null;
      const text = data?.choices?.[0]?.message?.content ?? "";
      if (!text.trim()) throw new Error("empty response");
      return text;
    }
    const text = await res.text().catch(() => "");
    const budgetRejected =
      res.status === 400 && round === 0 && Number(body.max_tokens) > 8_000 &&
      /max_tokens|max_completion_tokens|tokens|too long|length/i.test(text);
    if (budgetRejected) {
      body = { ...body, max_tokens: 8_000 };
      continue;
    }
    if (res.status === 401 || res.status === 403) throw new Error(`key rejected (${res.status})`);
    if (res.status === 404) throw new Error(`model not available (${res.status})`);
    if (res.status === 429) throw new Error("rate limited");
    throw new Error(`${res.status}: ${text.slice(0, 200)}`);
  }
  throw new Error("token budget rejected twice");
}

/// Generate text for an app build. Tries the free chain in order; a provider
/// timeout is surfaced immediately rather than burning the action budget on
/// further attempts.
export async function callFreeModel(
  system: string,
  user: string,
  tier: FreeTier,
  prefer?: string
): Promise<string> {
  const chain = freeChain(tier, prefer);
  if (chain.length === 0) {
    throw new Error(
      "No free AI key is set — set any of GEMINI/GROQ/NVIDIA/GITHUB/OPENROUTER/CEREBRAS/CLOUDFLARE keys on the Convex deployment"
    );
  }
  const payload = {
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  };
  const failures: string[] = [];
  for (const ep of chain) {
    try {
      return await attempt(ep, payload);
    } catch (err) {
      if (isTimeout(err)) {
        fail(new Error(`${ep.name} timed out after ${ATTEMPT_TIMEOUT_MS / 1000}s — try again`));
      }
      failures.push(`${ep.name}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  throw new Error(`Every free model provider failed — ${failures.join(" · ")}`);
}

/// OpenAI-compatible passthrough for the `/ai/*` proxy used by generated
/// apps: the requested model id is rewritten to the free chain's pick and
/// the answer comes back in the same OpenAI shape.
export async function freeChatCompletion(
  payload: Record<string, unknown>
): Promise<{ status: number; body: string }> {
  const tier = tierForModelHint(
    typeof payload.model === "string" ? (payload.model as string) : undefined
  );
  const chain = freeChain(tier);
  if (chain.length === 0) {
    return {
      status: 500,
      body: JSON.stringify({
        error: "No free AI key is set — set any of GEMINI/GROQ/NVIDIA/GITHUB/OPENROUTER/CEREBRAS/CLOUDFLARE keys",
      }),
    };
  }
  const base: Record<string, unknown> = { ...payload };
  if (base.max_tokens === undefined && base.max_completion_tokens === undefined) {
    base.max_tokens = maxTokens();
  }
  const failures: string[] = [];
  for (const ep of chain) {
    try {
      const res = await requestCompletion(ep, base);
      const text = await res.text();
      if (res.ok) return { status: res.status, body: text };
      failures.push(`${ep.name}: ${res.status} ${text.slice(0, 200)}`);
      if (res.status === 401 || res.status === 403) continue;
    } catch (err) {
      if (isTimeout(err)) {
        return { status: 504, body: JSON.stringify({ error: "Free AI provider timed out" }) };
      }
      failures.push(`${ep.name}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  return {
    status: 502,
    body: JSON.stringify({
      error: "All free AI providers failed",
      detail: failures.join(" · "),
    }),
  };
}
