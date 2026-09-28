# Petrable Blueprint — SDLC, Architecture & Troubleshooting Playbook

> **Audience:** other AI models (and humans) picking up this project.
> **Purpose:** a single durable record of how a paid-model app builder was converted to run
> entirely on free models, shipped across iOS + macOS, tested end-to-end — including the
> failure modes, techniques and platform quirks encountered on the way.
> **Companion docs:** [`AGENTS.md`](../AGENTS.md) (setup runbook) ·
> [`FREE_PROVIDERS.md`](../FREE_PROVIDERS.md) (live provider status board) ·
> [`README.md`](../README.md) (product overview).

---

## 0. Document index — this file is the hub

| Doc | What it's for |
|---|---|
| **[`docs/BLUEPRINT.md`](BLUEPRINT.md) (you are here)** | SDLC record, HLD/LLD diagrams, platform inventory, troubleshooting playbook — read this first |
| [`AGENTS.md`](../AGENTS.md) | Step-by-step setup runbook for AI agents (clone → keys → build → test) |
| [`FREE_PROVIDERS.md`](../FREE_PROVIDERS.md) | Live free-model provider status board: env var names, verified models, signup URLs, "if it's not working" fixes |
| [`README.md`](../README.md) | Product overview + fastest human setup path |
| [`scripts/README.md`](../scripts/README.md) | Release automation scripts (archive, package, launchd) |

**Key locations (not docs, but findable):** test evidence → `ios/build/runN-*.xcresult` ·
brand tokens → `…/00_Keith_Outputs/Gradus Apply/2026-09-24 Today KAF palette/` ·
pre-change backups → `backups/` in this repo · Convex dashboard →
`dashboard.convex.dev/t/kfleishman/rilable-fy27/focused-panther-579`.

---

## 1. Project identity — current state at time of writing

| | |
|---|---|
| Product | **Petrable** (renamed from Keithable/Rilable — name matters to the owner; internal targets still `Forge`/`KeithableMac`) |
| What it is | Prompt → live web app + native iOS app builder (Lovable/Replit-mobile style) |
| Repo | **Canonical: `github.com/kafworlddigital/petrable`** (KAF World Digital account) — verified full mirror also on `kfleishman-spec`; original open-source base kept as read-only `upstream` (rbrown101010/rilable) |
| iOS app | SwiftUI, target `Forge`, scheme `Forge`, `.app` = `Forge.app`, display name **Petrable**, bundle `com.kafworlddigital.petrable`, deployment iOS 17+ |
| macOS app | target `KeithableMac`, product **`Petrable.app`**, bundle `com.keithfleishman.keithable.mac` |
| Signing | Team **V892V3PC6T** (Keith Fleishman); certs in login keychain; Xcode auto-signing |
| Backend | Convex (TypeScript), **dev deployment `focused-panther-579`** hardcoded in `ios/Sources/AppConfig.swift`; an unused prod deployment `focused-mule-635` exists |
| Model policy | **Free-only, forever.** No paid fallback, ever. 7-provider fallback chain (§4.1) |
| Quality bar | Full UI suite **6/6 passing** (incl. end-to-end build→live-preview demo test) |

---

## 2. SDLC record (discovery → release)

Standard delivery phases mapped to what actually happened. Use this to locate any
artifact quickly.

### 2.1 Discovery
- Requirement: remove all paid-model dependence (previous stack: OpenAI/Anthropic keys on
  Convex; OpenAI credits already exhausted — transcription returned `429 insufficient_quota`).
- Constraints recorded: free models only; keep iOS+macOS buildable; server-side keys only
  (never in the app); preserve Daytona web sandboxes + Mac-worker iOS builds; brand must
  match the KAF app family (Relo CRM, Sermo Voice, Gradus Apply).
- Naming decision: product = **Petrable** (after the dog, Petra); backend/folder names not
  important to the owner.

### 2.2 Design & architecture
- Free-model **tier router** (fast/balanced/smart) with an ordered provider chain; a
  provider without a key silently drops out; per-attempt error taxonomy drives fallthrough
  (§4.1). Design goal: *any single key keeps the product alive; N keys give resilience.*
- Key storage: Convex env vars only; local secrets read from macOS Keychain
  (`codex-*-api-key` services) and piped, never printed (§6.4).
- Brand system adopted from the owner's approved references (§5.4).

### 2.3 Implementation
- `backend/convex/freeAi.ts` — chain router (providers: Gemini, Groq, NVIDIA, GitHub
  Models, OpenRouter, Cerebras, Cloudflare).
- `backend/convex/models.ts` — menu keys → tiers (`free-smart|balanced|fast`, `fable-5`);
  unknown keys coerce to default (legacy `claude-*` aliases removed and callers made tolerant).
- `backend/convex/builder.ts` — web pipeline: generate → Daytona sandbox → upload → start
  server → preview URL (§4.2), plus Mac-worker mobile pipeline.
- `backend/convex/voice.ts` — Groq Whisper first (free), no OpenAI fallback anymore.
- iOS/macOS: product rename (display strings, plists, `project.yml`, pbxproj, scripts,
  docs), UI-string de-branding (no Claude references anywhere in app code/docs).
- Test evidence: `ios/build/run14-allsuite.xcresult` (6/6).

### 2.4 Systems integration testing (SIT)
SIT = the seams between systems; each seam was proven with a live probe, not a mock:
- App ⇄ Convex: UI suite drives the real app against the real deployment.
- Convex ⇄ free models: real chat-completions requests per provider (status-code matrix, §6.3).
- Convex ⇄ Daytona: sandbox create → proxy exec → upload → preview fetch, verified to
  `status: live` with a real `*.daytonaproxy01.*` URL.
- Voice ⇄ Groq: `whisper-large-v3` present in Groq's live model list; transcription path
  is Groq-first.
- Signing ⇄ devices: mac install verified (`codesign --verify` + launch), sim install verified.

### 2.5 Testing & Q&A
- Regression: 6 UI tests (`VoiceModelSpotTest`×2, `ForgeTourTest`×2, `MobileSpotTest`,
  `ForgeDemoTest`). The demo test waits up to 420 s for a **Live** project → asserts
  `previewButton` → opens webview. Budget math: prep ≈ 8 s + 420 s timeout ≈ 490 s when red.
- Flake protocol used: reproduce 3× → capture `simctl io … screenshot` + UI hierarchy →
  query `xcresulttool get test-results summary/tests` for exact failure text → fix root
  cause, never the assertion.
- Owner Q&A loop: screenshots from the owner were traced to *stale* sources (old deployment
  string, old app build) — always ask "when was this captured?" before debugging code.

### 2.6 Release (in progress)
- macOS: **shipped** — signed `Petrable.app` in `/Applications`, launches.
- iOS: build green; physical install **waits for a connected device** (dev-sign + auto
  app-id). TestFlight path needs the placeholder bundle id `com.kafworlddigital.petrable` re-registered
  under team `V892V3PC6T` (owner decision).
- Pending gates: owner commit/push approval; optional Cerebras/Cloudflare quota review;
  branding pass (§5.4) currently mid-flight.

---

## 3. HLD — platforms & topology

```
                         ┌──────────────────────────────────────────────┐
   HUMAN (Keith)         │  Owner devices & accounts                   │
   prompt / voice ───────┤  iPhone (iOS 26 sim + physical)  Mac (arm64) │
                         └───────────────┬──────────────────────────────┘
                                         │ SwiftUI app "Petrable"
                                         │ HTTPS (ConvexClient, AppConfig.convexDeploymentURL)
                                         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ CONVEX  — deployment: focused-panther-579 (dev; prod focused-mule-635 idle)│
│                                                                            │
│  projects.*     create / get / update / setModel(coerce→default)           │
│  messages.*     chat log, per-message model override                       │
│  builder.*      build, edit (web) · buildMobile, pollMobileBuild (iOS)      │
│  voice.transcribe   Groq whisper-large-v3 first                             │
│  models         MODEL_OPTIONS → FreeTier (fast|balanced|smart)             │
│  freeAi         ★ the router (LLD §4.1)                                    │
│  system.status  readiness card (Key/Convex/Daytona/worker…)                 │
└───────┬───────────────────────────────┬─────────────────────┬──────────────┘
        │ free chat-completions         │ REST (Bearer)       │ REST
        ▼                               ▼                     ▼
┌───────────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
│ FREE MODEL PROVIDERS  │   │ DAYTONA            │   │ Mac Worker           │
│ 1 Gemini   (AI Studio)│   │ mgmt: app.daytona  │   │ local Xcode poller   │
│ 2 Groq                │   │  /api/sandbox …    │   │ → unsigned IPA /     │
│ 3 NVIDIA NIM          │   │ toolbox PROXY:     │   │   device install     │
│ 4 GitHub Models       │   │  {proxy}/{sid}/    │   └──────────────────────┘
│ 5 OpenRouter :free    │   │  process/execute   │
│ 6 Cerebras (qwen3.8)  │   │  files/upload-v2   │   ┌──────────────────────┐
│ 7 Cloudflare WorkersAI│   └────────────────────┘   │ DEV LOOP (local)     │
└───────────────────────┘                            │ xcodegen (project.yml│
   keys = Convex env vars ONLY (never in apps)       │  → Forge.xcodeproj)  │
                                                     │ xcodebuild test/build│
                                                     │ xcresulttool forensics│
                                                     └──────────────────────┘
```

Trust boundaries: keys live only in Convex env; the app ships zero secrets; GitHub/Daytona/
model providers are all egressed from Convex functions (server-side), never from the phone.

---

## 4. LLD

### 4.1 Free-model router (`freeAi.ts`)

```
callFreeModel(system, user, tier)
  chain = freeChain(tier)                  # providers without keys are dropped
  if chain empty → throw "No free AI key is set…"
  for ep in chain:                         # ordered fallback
      attempt(ep):
        POST {ep.url}  Authorization: Bearer {ep.key}
        body = { messages, model: ep.model, max_tokens: 16000 }
        timeout = 300s (AbortSignal)       # timeout = immediate fail (no further retries)
        res.ok → return text               # empty text counts as failure
        400 + token-budget wording & round0 → retry once at max_tokens=8000
        401/403 → "key rejected"   → next provider
        404     → "model not available" → next provider   ← catalogue drift, see §6.3
        429     → "rate limited"   → next provider        ← expected on :free tiers
        other   → `${status}: body[0..200]` → next
  all failed → throw "Every free model provider failed — name: reason · …"
```

Chain order (keys all present):
- `fast`: Groq → Gemini → NVIDIA → GitHub → OpenRouter → Cerebras → Cloudflare
- `balanced`/`smart`: Gemini → Groq → NVIDIA → GitHub → OpenRouter → Cerebras → Cloudflare

Verified model pins (live-tested before deploy; env-override pattern `<PROVIDER>_<TIER>_MODEL`):

| Provider | env key | smart | balanced | fast |
|---|---|---|---|---|
| Gemini | `GEMINI_API_KEY` | gemini-3.8-flash | gemini-3.8-flash | gemini-3.8-flash |
| Groq | `GROQ_API_KEY` | openai/gpt-oss-120b | openai/gpt-oss-120b | openai/gpt-oss-20b |
| NVIDIA | `NVIDIA_API_KEY` | nvidia/nemotron-3-ultra-550b-a55b | nvidia/nemotron-3.5-lightning-30b-a3b | same |
| GitHub | `GITHUB_API_KEY` | deepseek/DeepSeek-V3 | openai/gpt-4o-mini | openai/gpt-4o-mini |
| OpenRouter | `OPENROUTER_API_KEY` | qwen/qwen3.8-27b:free | qwen/qwen3.8-27b:free | nvidia/nemotron-3.5-lightning:free |
| Cerebras | `CEREBRAS_API_KEY` | qwen-3.8-27b (env) | qwen-3.8-27b (env) | qwen-3.8-27b (env) |
| Cloudflare | `CLOUDFLARE_API_KEY` + `CLOUDFLARE_ACCOUNT_ID` | @cf/openai/gpt-oss-120b | @cf/deepseek-ai/deepseek-r1-distill-qwen-32b | @cf/meta/llama-3.1-8b-instruct-fp8 |

> Menu labels → keys: `free-smart`→"Gemini Pro", `free-balanced`→"Gemini Flash",
> `free-fast`→"Llama 3.3", `fable-5`→smart tier. Default = `free-balanced`.

### 4.2 Web build pipeline (`builder.build`, internal action)

```
projects.create(prompt) → insert(status=queued) → scheduler.runAfter(0, builder.build)

builder.build(projectId):
  getInternal → null ⇒ return (seen: log row looked "standalone" — queries log separately)
  DELETE old sandbox (best effort)
  status=generating "Free AI is designing your app"
  raw = callFreeModel(GENERATE_SYSTEM + aiSkill("web"), prompt, resolveModel(model))
  parse → {name, emoji, files[]} → projects.update(name) → files.saveAll
  status=sandbox   → POST {mgmt}/sandbox                    → sandboxId
  status=uploading → proxy exec mkdir + files/upload-v2 per file
  status=starting  → proxy exec: python3 -m http.server 3000 (×5 attempts until local200)
  GET {mgmt}/sandbox/{id}/ports/3000/preview-url → waitForPreview (GET until200,30s)
  status=live + previewUrl + version++
  any throw → status=error "Build failed", error=message (surfaced in app)
```

**Daytona call contract (the hard-won part):**

```
mgmt base : https://app.daytona.io/api          (Bearer DAYTONA_API_KEY)
  POST /sandbox                      → create
  GET  /sandbox/{id}                 → state polling
  GET  /sandbox/{id}/toolbox-proxy-url → { url }      ← resolve ONCE per sandbox (cache)
  GET  /sandbox/{id}/ports/{port}/preview-url → { url, token }

toolbox proxy (per sandbox): {url}/{sandboxId}/…
  POST /process/execute   JSON {command, cwd, timeout} → { result, exitCode? }   Bearer
  POST /files/upload-v2?path=<abs>   multipart field "file"                      Bearer

⛔ DEAD ROUTES (404 "Cannot POST"): /toolbox/{id}/toolbox/process/execute,
   /toolbox/{id}/toolbox/files/upload   — the pre-proxy API. Do not resurrect.
```

### 4.3 Voice (`voice.transcribe`)
`base64 m4a → size gate (1KB..10MB) → [Groq whisper-large-v3] → (OpenAI removed: key unset)
 → {text}`. Failures fall through the provider list; final throw names the missing key.

### 4.4 Project state machine
`queued → generating → sandbox → uploading → starting → live | error` (+ mobile:
`queued → buildingMobile → … → readyToInstall | error`, polled by `worker:pendingMobileBuilds`).

---

## 5. Platform & integration inventory

### 5.1 Local toolchain & commands
```sh
# regenerate project from SOURCE OF TRUTH (do not hand-edit pbxproj long-term)
xcodegen generate                      # ios/project.yml → Forge.xcodeproj

# build / test (sim)
xcodebuild -project ios/Forge.xcodeproj -scheme Forge \
  -destination 'id=2F897A22-E49D-4C25-A0C4-F9E15B99E20A' \
  -derivedDataPath ios/build/build-<name> -resultBundlePath ios/build/runN.xcresult \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO [build|test]

# forensics
xcrun xcresulttool get test-results summary --path <run>.xcresult
xcrun simctl io <udid> screenshot out.png
# macOS product
xcodebuild -project ios/Forge.xcodeproj -scheme KeithableMac … build   # → Petrable.app

# backend
cd backend
npx tsc --noEmit -p convex/tsconfig.json     # typecheck
npx convex dev --once                        # NON-INTERACTIVE push to dev deployment
npx convex env set NAME 'value'              # no echo of value
printf '' | npx convex env list | cut -d= -f1  # names only — NEVER raw (leaks secrets)
npx convex run projects:create '{"prompt":"…","platform":"web"}'   # smoke build
npx convex logs --history N --jsonl          # schema: executionTimestamp(float s),
                                             # identifier, logLines[], error, caller
```

### 5.2 Secrets & auth map
| Thing | Where it lives |
|---|---|
| Model/Daytona keys | Convex env (dev deployment) |
| Groq/NVIDIA/OpenRouter originals | macOS Keychain services `codex-{groq,nvidia,openrouter}-api-key` — pipe with `security find-generic-password -s <svc> -w` inside `$(…)` so values never print |
| GitHub Models auth | the Mac's `gh` CLI token (`gh auth token`) — needs no special scope |
| Apple signing | keychain: Apple Distribution/Development *Keith Fleishman (V892V3PC6T)* |
| App→backend URL | `ios/Sources/AppConfig.swift` (hardcoded deployment URL) |

**Key hygiene rules learned the hard way:** secrets never appear in tool output; lists print
names only; if a secret does leak into logs → rotate that provider's key immediately
(we rotated GitHub PAT / Daytona / NVIDIA after an `env list` without a filter).

### 5.3 Brand system (KAF family)
Authoritative extracts (owner-approved, stored with evidence + sha256):
`…/07_OUTPUTS_AND_DELIVERABLES/00_Keith_Outputs/Gradus Apply/2026-09-24 Today KAF palette/`

- Website tokens: `--paper:#f3f5fc --ink:#0b0e18 --accent:#4154ef --lime:#baff38`
- Relo app implementation tokens: nav `#0B131F`, canvas `#E0EBF9`, surface `#E5EFFD`,
  inset `#D5E3F8`, line `#BED0EC`, toolbar `#3557F9`, action `#2E51F9`, priority `#2444D2`,
  lime `#C9FC4C`, ink `#0B1335`… (see `relo-palette-implementation.json` — includes
  contrast ratios already validated)
- Native SwiftUI reference app: **Sermo** (`06_PROJECTS_AND_DEMOS/SermoPrivateJournal`,
  theme evidence under `Evidence/Theme-20260925`)
- Pending: apply this system to Petrable's `Theme.swift` (currently Lovable-dark bloom).

### 5.4 Storage & volumes (standing order)
- 5 TB bulk drive UUID `C09342A1-04CA-4236-AF34-C508C63875B1`, ≥500 GiB reserve,
  capacity-guard before bulk jobs (see `AI_TOOL_STORAGE_STANDING_ORDER.md`).
- microSD = working volume (this repo). Internal = apps/settings only.
- If a volume degrades: stop bulk jobs, keep read-only work (§6.7 case file).

---

## 6. Troubleshooting playbook (techniques + case files)

> Each case: **Symptom → Method → Root cause → Fix → Lesson.**

### 6.1 "Test failed but no info" → evidence ladder
Method: never guess from the assertion alone. Ladder, cheapest first:
1. `xcresulttool get test-results summary/tests` → exact failure text + failing step.
2. UI hierarchy at failure (`XCUIApplication.debugDescription` in-test, or CDP
   `Accessibility.getFullAXTree` for WebView) → what was actually on screen.
3. `simctl io screenshot` frames around the failure window.
4. Re-run 3× → distinguish flake (timing) from break (deterministic).
Case: `testModelMenuAndMic` failed once on a sleep-vs-appearance race; forensics showed the
sheet *did* appear — fixed with proper waits, then 3/3 green. Never weaken assertions.

### 6.2 "Backend says X but source says Y" → deployed-vs-local audit
Symptom: app displayed status text ("Claude is designing your app") absent from source.
Method: grep source (all files) → grep *data* (`convex run projects:list`) → if neither
holds the string, the renderer's **deployment or build is stale**; check which deployment
the app reads (`AppConfig.swift`) and which code the deployment has (`convex dev --once`
push, then re-probe). Lesson: three possible homes for a string — client build, deployed
backend, stored row. Eliminate all three before touching code.

### 6.3 "Works yesterday, 404 today" → provider catalogue drift
Symptom: live probes returned `404 model not available` for every previously pinned model
(Gemini2.5 retired, Groq llama retired, OpenRouter `:free` slugs removed).
Method: **never trust remembered model IDs.** For each provider, fetch its live catalogue
or parse the error's suggested replacement, then run a **status-code matrix** (one tiny
`max_tokens:8` request per candidate, print only HTTP codes) and pin survivors in code +
env. Re-run the matrix after every provider incident. Lesson: model IDs are config, not
constants; ship the fallback chain so drift degrades gracefully (429/404 → next provider).

### 6.4 Secrets discipline
- Never `env list` unfiltered (we leaked 6 keys once — rotated3).
- Set: `npx convex env set NAME "$(security find-generic-password -s svc -w)"` — value
  never enters output; `env set` confirms by name only.
- Classify unknown blobs without printing: pattern-match length/prefix in a subshell
  (`case "$V" in AIza*) …`) and only report the class.

### 6.5 "Third-party API404" → SDK-as-ground-truth (Daytona case)
Symptom: `POST /toolbox/{id}/toolbox/process/execute` → `404 Cannot POST` (the owner's
original screenshot; blocked every build regardless of model keys).
Method when docs are scattered:
1. Pull the vendor's **OpenAPI** (`…/openapi.json`, follow redirects) → discover
   `GET /sandbox/{id}/toolbox-proxy-url` (execution moved behind a per-sandbox proxy).
2. Pull the vendor's **llms.txt** for a human map of doc pages.
3. `npm pack @daytonaio/sdk` → grep the generated client for the *exact* path, basePath
   assembly (`{proxyUrl}/{sandboxId}`) and auth header (`Bearer` API key).
4. Implement the contract; smoke with a real sandbox until `status: live`.
Lesson: for API drift, the vendor's SDK tarball is more honest than any blog post.
Also: dead routes return Express-style `Cannot POST <path>` — that phrasing means
*route missing*, not auth (auth401s say "unauthorized: …" with the needed credential).

### 6.6 Convex-specific gotchas
- `convex deploy` targets **prod** and prompts (fails non-interactively); to push dev:
  `npx convex dev --once`.
- Function logs are JSONL with `executionTimestamp` (float seconds), `identifier`,
  `logLines[]`, `caller` ("Scheduler") — not `time`/`message`. Nested `ctx.runQuery`
  calls log as **their own rows**, so a standalone `getInternal` row doesn't imply a
  separate caller. `returnBytes: 4` = the action returned `null`.
- Mutations validate args strictly; a client sending a removed legacy model key threw
  `Unknown model` — fixed by coercing unknown → `DEFAULT_MODEL_KEY` (lenient at the edge,
  strict inside).
- Scheduler timing: `runAfter(0, …)` runs after the insert transaction commits; a
  "document missing" probe must look at *which* deployment/id the scheduler carried.

### 6.7 Volume degradation (macOS I/O case file)
Symptom: builds/vite starved; processes in `UN` (uninterruptible) state; `ls` of a volume
root hung >45 s while `stat` of deep paths succeeded.
Method: (a) latency matrix — read 5 known files on each volume (internal1ms / microSD 9ms
/ 5 TB **1–27 s** per small file) → isolate to one device; (b) probe root readdir vs
per-entry `stat` to find a pathological entry (a `.zip` whose stat stalled); (c) check
actors (`ps`): Spotlight indexing + Time Machine cycles as amplifiers; (d) bounded
`diskutil verifyVolume` (live fsck) — superblock/checkpoint/space-manager clean, interrupted
at timeout; (e) UUID vs standing order → correct drive, ≥reserve → *not* a policy hold.
Fix/posture: stop bulk jobs (build/deploy), continue read-only work, report to owner with
evidence (this was a physical-layer fault needing cable/port attention). Never fall back to
other volumes for bulk work.

### 6.8 UI automation pitfalls (iOS)
- Test host ids: use `-only-testing:ForgeUITests/Class/test`; result bundles must not pre-exist.
- App gating: tests pass `-hasEntered YES` launch arg to skip onboarding; intro/`#skip`
  changes timing of audio unlock (Howler `_playLock` queues `volume/rate/mute` every tick —
  a queued-action **cascade can blow the JS stack** if too many actions queue pre-unlock;
  symptom: `RangeError: Maximum call stack size exceeded` spam from howler).
  Fix pattern: register sounds **after** `audio.initiated`, mirroring ambient registration.
- Howler registration at boot vs after-init was isolated by a control run (barks disabled →
 0 spam; enabled → 148 exceptions) — always A/B a suspected regression with one flag.

---

## 7. Testing strategy (what "done" means)

1. **Unit-ish**: `tsc --noEmit` (backend), `node --check` (JS), xcodegen parse (`xcodebuild -list`).
2. **SIT**: live provider matrix (§6.3), Daytona smoke (`projects:create` → assert
   `status == live` + preview URL), voice path present in Groq's live catalogue.
3. **E2E**: `ForgeDemoTest` (prompt → free generate → sandbox → live → webview). Red ≈490 s; green ≈66–93 s.
4. **Full regression**: all6 tests, `TEST SUCCEEDED`, evidence in `ios/build/runN-*.xcresult`.
5. **Install proof**: mac `codesign --verify` + running process; iOS installed-container
   `CFBundleDisplayName` == Petrable.

---

## 8. Open items for the next session

- [ ] Physical iPhone install (needs device connected; dev-sign path ready).
- [ ] Owner approval → git commit + push (GitHub last push2026-06-11).
- [ ] Branding pass: retheme `Theme.swift` + views to KAF/Relo tokens (§5.3), rebuild both platforms.
- [ ] Optional: TestFlight release (bundle-id decision), Cerebras/Cloudflare spend review,
      mirror free setup onto idle prod deployment if anything still points at it.
- [ ] Gemini `AQ.` keys expire — replace from aistudio.google.com/apikey when401s appear.

## 9. Golden rules (pin these)

1. **Free-only.** No paid fallback. Any key → works; no key → provider drops out.
2. **Evidence before edits.** xcresult → hierarchy → screenshot → reproduce3×.
3. **Live probes over assumptions** for anything third-party (models, APIs, routes).
4. **Secrets never in output**; rotate on exposure.
5. **project.yml regenerates pbxproj** — edit the yml, or your fix vanishes on next script run.
6. **Push dev with `convex dev --once`**; prod is a separate, deliberate act.
7. **Names of things matter to the owner** (Petrable) — match his app family and vocabulary.
