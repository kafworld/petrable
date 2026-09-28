# Free AI providers — setup, status and troubleshooting

The backend (`backend/convex/freeAi.ts`) routes every generation through an
ordered chain of **free** providers. A provider with no key drops out of the
chain automatically; a provider that fails (rate limit, outage, bad model)
falls through to the next one. **Any single key makes the app work.**

Last verified live: **28 September 2026** (every "live" model below returned
HTTP 200 on a real chat request).

## Status board

| Provider | Env var (Convex) | Status | Models in use (verified) | Free allowance |
|---|---|---|---|---|
| Google Gemini | `GEMINI_API_KEY` | ✅ set | `gemini-3.8-flash` (all tiers) | AI Studio free tier. **Note:** tokens starting `AQ.` are OAuth-style and can expire — if requests start returning 401/403, get a fresh key at <https://aistudio.google.com/apikey> (durable keys start `AIza`). |
| Groq | `GROQ_API_KEY` | ✅ set | `openai/gpt-oss-120b` (smart/balanced), `openai/gpt-oss-20b` (fast) | Very generous daily free tier; fastest inference of the group. |
| NVIDIA NIM | `NVIDIA_API_KEY` | ✅ set | `nvidia/nemotron-3-ultra-550b-a55b` (smart), `nvidia/nemotron-3.5-lightning-30b-a3b` | Free credits at <https://build.nvidia.com>. |
| GitHub Models | `GITHUB_API_KEY` | ✅ set | `deepseek/DeepSeek-V3` (smart), `openai/gpt-4o-mini` | Free inference with a PAT that has the `models` scope. |
| OpenRouter | `OPENROUTER_API_KEY` | ✅ set | `qwen/qwen3.8-27b:free`, `nvidia/nemotron-3.5-lightning:free` | `:free` slugs rotate and rate-limit often (429) — that is normal; the chain moves on. Browse current free models: <https://openrouter.ai/models?max_price=0>. |
| Cerebras | `CEREBRAS_API_KEY` | ✅ set (PayGo £5) | `qwen-3.8-27b` (all tiers, env-pinned) | Draws tiny amounts from your £5 balance; verify Qwen availability at <https://inference.cerebras.ai>. |
| Cloudflare Workers AI | `CLOUDFLARE_API_KEY` + `CLOUDFLARE_ACCOUNT_ID` | ✅ set | `@cf/openai/gpt-oss-120b` (smart), `@cf/deepseek-ai/deepseek-r1-distill-qwen-32b` (balanced), `@cf/meta/llama-3.1-8b-instruct-fp8` (fast) — all live-verified | Daily neuron allowance at <https://dash.cloudflare.com>; kimi/glm models listed but403 on this plan. |
| Ollama (local) | — | 🖥 dev only | e.g. `gpt-oss:20b` installed locally | Zero limits, private. The **cloud** backend cannot reach `localhost`, so this only applies when running `npx convex dev` locally. |

Menu labels in the app map to tiers (`backend/convex/models.ts`):
**Gemini Pro → smart**, **Gemini Flash → balanced**, **Llama 3.3 → fast**,
**Fable 5 → smart**. Keys `free-smart` / `free-balanced` / `free-fast` are the
stable identifiers stored on projects.

## Adding a key

Keys go into the Convex deployment, never into the repo or the app:

```sh
cd backend
npx convex env set CEREBRAS_API_KEY '<the key>'
```

Confirm with `npx convex env list` (names only — never paste key values into
docs, chats, commits or screenshots).

To pin a different model for one provider/tier without touching code:
`npx convex env set GROQ_SMART_MODEL '<model-id>'` — pattern is
`<PROVIDER>_<TIER>_MODEL`.

## If it's not working

1. **"No free AI key is set"** — `npx convex env list`; set at least one key
   from the table above.
2. **"Every free model provider failed — …"** — the message lists each
   provider's reason. `429` means rate limit (normal — wait or rely on the
   chain), `401/403` means a key expired (refresh it), `404 model not
   available` means that provider rotated its catalogue (update the default
   model in `freeAi.ts` or set `<PROVIDER>_<TIER>_MODEL`).
3. **Generation is slow** — the chain only advances after a failure or
   timeout (300 s per attempt is the ceiling, not the norm). Check the
   Convex dashboard → Logs to see which provider served the request.
4. **User-facing status still says "Claude …"** — that text lives in the
   *deployed* old backend; it disappears the first time the free-only code
   is deployed (`npx convex deploy` from `backend/`).
