Keith action: None.

### Independent Review & Pixel Audit (`./docs/home.png`)

The brief's core assumption that this is simply a "dark theme needing colour blending" obscures the root cause: **this screen is suffering an identity crisis caused by importing Lovable's sunset bloom and misapplying light-canvas design tokens onto dark navy hero chrome.**

1. **Token Inversion**: `Theme.surface` (`#E5EFFD`) is a light blue-grey canvas token. Using it on the dark hero header creates a glaring pale hamburger button with an invisible white icon (`#FFFFFF` on `#E5EFFD` = 1.09:1 contrast — completely fails WCAG).
2. **Text Drowned in Mud**: "Connect all your tools", the prompt placeholder, the `+` menu, and the model selector are rendered in near-black ink (`#0B1535`) or unboosted muted tones on `#172640` dark panels. They are virtually unreadable.
3. **The Lovable Bruise**: Layering `bloomPink` (`#C4A6FF`) at 45% opacity over `#0B131F` navy produces a dirty, desaturated lilac/mauve haze across the lower 40% of the screen. It clashes violently with the electric lime `#C9FC4C` action button and makes the app look like an uncalibrated template.
4. **Visual Hierarchy Inversion**: The active "Web" toggle is a blinding, solid `#FFFFFF` block with black ink. It screams louder than the headline and competes directly with the lime Send button.
5. **Layout Vacuum**: A 1:3 `Spacer()` ratio shoves the interactive core into the upper half, stranding an empty 350pt lavender wasteland above the home indicator.

---

### Prioritised Implementation-Ready Fixes

Ranked by visual impact per unit of effort:

#### 1. Fix Critical Text & Icon Legibility on Hero/Panel Surfaces
* **Exact Roles & Hexes**:
  * **Top Bar Menu Button**: Icon `#FFFFFF`, background `Color.white.opacity(0.08)`, stroke `Color.white.opacity(0.12)`. Remove `#E5EFFD`.
  * **"Connect all your tools" Pill**: Label `#E7EEF7` (`Theme.onHero`), arrow `#8FA1C4` (`Theme.heroMuted`).
  * **Composer Placeholder**: `#8FA1C4` at 100% opacity (no washed-out alpha).
  * **Composer Chrome (`+` and Model dropdown)**: Text & icon `#E7EEF7`; dropdown chevron `#8FA1C4`.
  * **Voice Mic**: `#E7EEF7`.
  * **Send Button**: Keep `#C9FC4C` (brand lime), icon `#0B1535` (`Theme.textPrimary` ink).
* **Rationale**: Eliminates the broken white-on-white hamburger button and restores immediate 7:1+ contrast to previously invisible primary controls.

#### 2. Kill the Muddy Multi-Hue Bloom (Replace with Deep Navy Vignette or Focused Cobalt Ambient)
* **Strategy & Stops**:
  * Delete `bloomIndigo` (`#4653F4`), `bloomPink` (`#C4A6FF`), and `bloomOrange` from `LovableBloom`.
  * **Option A (Recommended — Subtle Focus)**: Single radial cobalt glow centered behind the composer card: `RadialGradient(colors: [Color(hex: "#3548EB").opacity(0.16), .clear], center: .center, startRadius: 10, endRadius: w * 0.75)` blurred at 70pt.
  * **Option B (Clean Native Vignette)**: LinearGradient from top `#0B131F` (navy hero) down to `#060A11` (deepest ink) at the bottom.
* **Rationale**: Purges the dirty purple haze, cleans the lower viewport, and anchors the cool Navy/Cobalt/Lime palette.

#### 3. De-escalate the Platform Toggle (Kill Stark Pure White Pill)
* **Exact Styling**:
  * **Track/Container**: `#172640` with `Color.white.opacity(0.08)` border.
  * **Active Segment ("Web")**: Background `Color.white.opacity(0.14)` (or solid elevated navy `#23385B`), text `#FFFFFF` (`.system(size: 15, weight: .semibold)`), icon `#FFFFFF`.
  * **Inactive Segment ("Mobile")**: Background `.clear`, text `#8FA1C4`, icon `#8FA1C4`.
* **Rationale**: Prevents a secondary segmented switch from out-shouting both the greeting and the primary lime action button.

#### 4. Tighten the "Connect All Your Tools" Badges (Icon Strategy)
* **Strategy**:
  * Remove the arbitrary multicolour icons (green triangle, magenta `#`, red envelope).
  * Standardise badges to 24×24pt circles: background `Color.white.opacity(0.08)`, border `Color.white.opacity(0.12)`.
  * Icons: Monochrome `#E7EEF7` using clean platform symbols: `sparkles` (AI models), `terminal` (Mac worker/builds), and `globe` (Daytona web).
* **Rationale**: Replaces carnival clip-art stickers with cohesive, precision developer-tool iconography.

#### 5. Refine Composer Card Geometry & Stroke Scale
* **Exact Specs**:
  * **Background**: Solid `#172640` or subtle vertical gradient (`#1B2C4B` to `#14223A`).
  * **Stroke**: 1px hairline `Color.white.opacity(0.08)`.
  * **Corner Radius**: Reduce from `30pt` to **`22pt` continuous** (`.continuous`).
* **Rationale**: Fixes the squishy "melted soap" appearance and aligns card curvature with standard iOS squircle proportions.

#### 6. Clean Up Footer Iconography & Copy
* **Exact Specs**:
  * Replace `triangle.fill` with `sparkles` at `size: 11, weight: .medium`.
  * Copy: "Runs on free AI models", font `.system(size: 13, weight: .medium)`, colour `#8FA1C4`.
  * Bottom spacing: 16pt above home indicator.
* **Rationale**: Replaces an ambiguous hazard/Vercel triangle with standard, reassuring AI indicator styling.

#### 7. Rebalance the Vertical Spacing Scale (8pt Grid)
* **Exact Scale**:
  * Replace the unbalanced `1 Spacer` (top) vs `3 Spacers` (bottom) with a structured rhythm:
    * `topBar` → `Spacer(minLength: 24)`
    * `connectPill` → `padding(.top, 16)`
    * `greeting` → `padding(.top, 20)`
    * `platformToggle` → `padding(.top, 16)`
    * `composerCard` → `padding(.top, 16)`
    * `Spacer(minLength: 48)`
    * Footer → `padding(.bottom, 12)`
* **Rationale**: Groups the interactive elements into an optical center cluster and stops the layout from floating awkwardly at the ceiling.

#### 8. Enforce a Strict 4-Tier Radius System
* **Exact Scale**:
  * **Tier 1 (Controls / Badges / Buttons)**: `Capsule()` (pills/toggles) and `Circle()` (send button, menu button, badge icons).
  * **Tier 2 (Alerts / Banners)**: `14pt` continuous (`readinessBanner`).
  * **Tier 3 (Primary Interactive Cards)**: `22pt` continuous (`composerCard`).
  * **Tier 4 (Modal Sheets / Drawers)**: `28pt` continuous (`ProjectsDrawer`).
* **Rationale**: Eliminates conflicting radii (18pt, 30pt, capsules, circles) across adjacent components.
