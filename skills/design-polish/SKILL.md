---
name: design-polish
description: Polish Flutter app UI screens for visual hierarchy, readability, and section clarity. First reads a representative reference screen (the home page or a polished page the user points at) to lock in the app's existing design tone, then drives the running app on the Android emulator via the `android-emulator` skill — screenshots, taps, swipes — to observe each target screen, makes targeted widget and `ThemeData` changes, and spawns an independent evaluator sub-agent to score the result on design quality, originality, craft, and functionality. Use this skill whenever the user wants to improve, polish, refine, critique, audit, or tighten the visual design of a Flutter screen — even when they don't say "polish" explicitly (e.g. "make this look better", "fix the layout on settings", "tighten up the home screen", "this screen feels off").
license: MIT
metadata:
  author: Chunky Tofu Studios
  source: https://github.com/chunkytofustudios/skills
---

# Design polish (Flutter)

You polish screens in a Flutter mobile app — improving **visual hierarchy, readability, and section clarity** so a user instantly knows how to use the app. The work is opinionated, evidence-driven, and bounded: every round ends with an independent evaluator's verdict, not your own self-assessment.

## Setup

If the user didn't specify screens, ask:

- "Which screens should I polish? Provide route names (e.g. `/settings`, `/profile`) or component file paths under `lib/`."

The app must be running on an Android emulator. Use the [`android-emulator`](../android-emulator/SKILL.md) skill — every screenshot, tap, swipe, and accessibility-tree dump in this workflow goes through it:

```bash
scripts/emu.sh health        # confirm device, AVD, foreground app
scripts/emu.sh boot          # if not running
scripts/emu.sh run           # build & install in background
scripts/emu.sh wait-run      # block until attached
```

If the app needs login, get credentials from the user (or from `.env` / `lib/config/` if the project keeps them there) before navigating.

## Establish design tone

**Do this once before touching any screen.** Skipping it is the single biggest source of inconsistency — your changes will look right in isolation and wrong next to the rest of the app.

1. **Find a reference screen.** Try in this order:
   - The user named a polished screen ("settings looks great, polish the rest to match"). Use that.
   - The home page: `MaterialApp.home`, `initialRoute`, or the first tab of a `BottomNavigationBar` in `lib/main.dart` or the router config (GoRouter, AutoRoute, etc.).
   - Files named `home_page.dart`, `home_screen.dart`, `dashboard.dart`.
2. **Read its source.** Open the screen's widget file plus everything it imports from `lib/theme/`, `lib/widgets/`, and any custom `ThemeExtension`s. Note `ColorScheme`, `TextTheme`, spacing constants, radius values, and any shared layout primitives.
3. **Screenshot it on the emulator.** Navigate with `tap-label` if needed, then `scripts/emu.sh screenshot` and read the printed path. Scroll and capture each state.
4. **Write the design tone in 3–5 specific bullets.** What makes this app's screens feel like *this app* and not a generic Material default. Pick the axes that actually distinguish the reference screen — describe what's there, not what you wish were there:
   - Mood — e.g. calm/restrained, playful/energetic, bold/arcade, soft/cozy, retro, neon.
   - Fonts — which families and weights, where each is applied. Lock the list.
   - Color — the full `ColorScheme` story: restrained palette vs. expressive, flat vs. gradient, saturation level, semantic tokens, any `ThemeExtension`s.
   - Surfaces — card backgrounds, borders, corner radius, elevation/shadow, blur.
   - Hierarchy lever — how the app signals importance: weight, color, spacing, border, accent, illustration, or a mix.
   - Motion — none, subtle Material defaults, or expressive (custom curves, hero transitions, Lottie/Rive).

**If you cannot establish a tone with confidence** — no clear reference screen exists, candidate screens look unfinished, themes are inconsistent across the codebase — **stop and ask the developer**:

> "I couldn't establish a clear design tone from the codebase. Could you point me to a polished reference screen (file path or route name)? I need this so my changes stay consistent with your existing style."

Do not proceed without an established tone. The polish workflow only works if you know what you're polishing *toward*.

## Brand & design system

Use the design tone you established above as your north star. Pull concrete constraints from the codebase and respect them:

**Fonts.** Identify the families used in `theme.textTheme` (often via `google_fonts`, `flutter_fonts`, or asset-bundled `.ttf`s in `pubspec.yaml`). Don't add new fonts. Missing typographic tokens (e.g. an unused `labelSmall`) must be wired through `ThemeData` and applied consistently — no inline `TextStyle(...)` literals.

**Colors.** Use existing `ColorScheme` tokens. You may add up to 2 new semantic tokens (e.g. `success`, `warning`) — wire them through a `ThemeExtension` (Flutter's mechanism for adding theme fields beyond `ColorScheme`'s built-ins) and apply them across every screen you touch. No one-off hex literals scattered through widgets.

**Components.** Reuse existing custom widgets in `lib/widgets/` or `lib/components/` where they exist. For Material-based apps, prefer SDK widgets (`FilledButton`, `Card`, `ListTile`, etc.) over rolling your own; for apps with a strong custom widget library (common in games and heavily-branded utility apps), match the existing pattern instead of introducing stock Material widgets that will look out of place. Small utility packages are fine; don't pull in a new component library mid-polish.

**Spacing & radius.** Identify the existing spacing scale (often a `Spacing` extension or `EdgeInsets` constants under `lib/theme/`) and the corner-radius value. Don't change either — variation here reads as inconsistency to the eye even when individual choices are defensible.

## Workflow (per screen)

### 1. Observe

Drive the screen via the `android-emulator` skill:

- `scripts/emu.sh ui-list` — discover what's addressable; default to this over screenshotting.
- `scripts/emu.sh tap-label "..."` — navigate to the target screen.
- `scripts/emu.sh screenshot` — capture the initial state. Read the printed path.
- Scroll (`swipe`), open tabs, expand panels, dismiss dialogs (`tap-label "Close"`) — interact like a real user. Screenshot each meaningful state.
- Read the screen's widget source and every shared widget it composes.

### 2. Diagnose

Write 3–7 **specific** problems. Each must name exact widgets and what's wrong:

- "`TabBarView` and the side `Drawer` both use `surfaceContainer` — no visual boundary between them."
- "All body text is `bodyMedium` with `FontWeight.w400` — nothing distinguishes primary data from labels."

Not acceptable: "needs more contrast", "feels cluttered."

### 3. Fix

Edit Dart source with **targeted widget changes**, not rewrites. Touch one concern at a time (hierarchy, then spacing, then color emphasis), not everything in one pass.

After each logical group of edits, re-attach and screenshot to verify:

```bash
scripts/emu.sh kill-run && scripts/emu.sh run && scripts/emu.sh wait-run
scripts/emu.sh screenshot
```

For tight iteration on visual-only changes, ask the user to keep `flutter run` going in their own terminal (IDE-driven hot-reload on save) — then you only screenshot. The kill-run/run cycle is the safe default but costs 30–60s per pass.

If a change looks wrong, revert and try differently. Do not pile fixes on top of a broken direction.

### 4. Evaluate (sub-agent)

Take "after" screenshots (interact with the page again). Then **spawn an evaluator sub-agent** with the Agent tool, using the latest Opus model, with this prompt (fill in `SCREEN_NAME`, `NAVIGATION_HINT`, and `LOGIN` — or "no login required"):

---

**Evaluator prompt:**

You are an independent design evaluator with NO relationship to the agent that made these changes. Be a skeptical, demanding critic. You are reviewing a screen in a Flutter mobile app.

The app is already running on an Android emulator. Use the `android-emulator` skill to interact:

- `scripts/emu.sh ui-list` to see what's addressable
- `scripts/emu.sh tap-label "..."` to navigate to SCREEN_NAME (NAVIGATION_HINT)
- `scripts/emu.sh screenshot` to capture each state — read the printed path
- Scroll, tap every tab, expand panels, open menus — interact like a real user. Capture screenshots of each meaningful state.

Login: LOGIN.

Score 1–10 on each criterion with 2–3 sentence justification:

**Design Quality (HIGH weight):** Coherent whole vs. collection of parts? Do colors, typography, layout, and spacing combine into a distinct mood and identity?

**Originality (HIGH weight):** Deliberate custom choices vs. Material defaults and AI patterns? AI-slop signs (sparkle/✨ icons, "AI-powered"/"magic" badges, meaningless decorative charts, decorative elements that don't fit the rest of the visual language) = automatic failure.

**Craft (MEDIUM weight):** Typography hierarchy, spacing consistency, color harmony, contrast, alignment. Competence check — failing = broken fundamentals.

**Functionality (MEDIUM weight):** Can users find actions, complete tasks, understand the interface without guessing? Tap targets ≥ 48dp? Text readable at device DPI?

Calibration: 9–10 = Apple Design Award caliber, or top-charting App Store app in the same category (game vs. utility), almost never given. 7–8 = solid pro work, no notes. 5–6 = generic, default Material components, no identity. 3–4 = obvious problems. 1–2 = broken.

For any score >7, name one thing a skeptical senior designer would still criticize. If you can't, lower the score.

Write a 3–5 bullet critique of remaining problems (specific widgets, not vague). Then a verdict: PASS (all 7+), ITERATE (any high-weight <7), FAIL (any <5).

Format:
```
DESIGN_QUALITY: X/10 — ...
ORIGINALITY: X/10 — ...
CRAFT: X/10 — ...
FUNCTIONALITY: X/10 — ...

CRITIQUE:
- ...

VERDICT: PASS/ITERATE/FAIL
```

---

### 5. React to verdict

- **PASS:** Move to the next screen.
- **ITERATE:** Address the evaluator's specific critique — don't re-diagnose from scratch. Return to step 2.
- **FAIL:** Consider reverting to "before" and trying a completely different approach.
- Max 3 evaluation rounds per screen. At the cap, keep the best-scoring version.

## Hierarchy toolkit

Apply what the layout needs — not everything on every screen. Tokens below are Material 3; translate to your app's equivalents if it uses Cupertino, a custom theme class, or a heavily-themed game widget library:

- **Borders/dividers** between sections (`Divider`, `OutlinedBorder`, 1px `colorScheme.outlineVariant`).
- **Background contrast** between regions (`surface` vs `surfaceContainer` vs `surfaceContainerHighest`).
- **Typographic weight/size** to signal importance (`titleLarge` > `titleMedium` > `bodyMedium` > `labelSmall`).
- **Spacing** — related items tight (`Gap(4)`/`Gap(8)`), unrelated items far apart (`Gap(24)`/`Gap(32)`).
- **Color as signifier** — `primary` for the single primary action; `onSurfaceVariant` to de-emphasize.
- **Left-border accents** on key cards (2–3px `Border(left: BorderSide(color: primary))` inside a `Container` decoration).
- **Tab indicators** — `TabBar` active state must be unambiguous; inactive should recede with `unselectedLabelColor`.

## Anti-patterns

### Tone-relative — departing from the established tone (Originality score ≤ 4)

The fastest way to make a screen feel AI-generated is to add visual elements that don't belong in *this* app. Gradients, animations, hero illustrations, decorative blur, `StadiumBorder` pills, custom scrollbars, particle effects, parallax, lottie — every one of these is a legitimate choice in the right context and slop in the wrong one. The reference is the design tone you established up top, not a fixed aesthetic prescription.

The principle: **don't introduce a visual element that isn't already part of the established tone.** Match what's there. If the rest of the app is flat, don't add a gradient. If the rest of the app is calm, don't add a particle burst. If the rest of the app uses outlined cards, don't introduce a glassmorphic blur layer.

If you think the tone itself is the problem, that's not a polish task — flag it to the user. Polishing toward a tone the app doesn't have is how screens end up feeling like a different app.

### Universal red flags (any one = Originality score 2)

These are slop in any context — game, utility, productivity, or otherwise:

1. Sparkle/✨ icons, "AI-powered"/"magic"/"smart" badges, or other in-product AI branding used as decoration
2. Meaningless decorative charts, sparklines, gauges, or graphs that don't represent real data
3. Internal contradictions — decorative shadows on an otherwise-flat design, a flat panel slapped onto an elevated layout, a single screen with rounded everything in an app that's all rectangles
4. `Shimmer`/skeleton loaders without a real async wait behind them
5. "Welcome back!" greeters, hero banners, or onboarding-style headers slipped onto a screen the user opens every day
6. Functionality changes — route restructuring, feature removal, or widget API changes (out of scope for polish; flag, don't quietly do)

### Smell tests

- "Would a designer at an Apple Design Award–winning app in this category call this decorative noise?"
- "Would someone scrolling past this say it looks AI-generated?"

If yes to either, undo it.

## Process rules

- One screen at a time. Full cycle (observe → diagnose → fix → evaluate) before moving on.
- New `ColorScheme` or `TextTheme` tokens must be applied across every screen you touch in this session — no localized inconsistencies.
- Shared widgets and `ThemeExtension`s: fix once, then verify the ripple by re-screenshotting every screen that consumes them.
- Run `dart format .` and `flutter analyze` (or `fvm flutter analyze`) after each screen's changes. Fix lints before evaluating — they often surface real issues.
- Run `flutter test` before declaring a screen done, in case widget tests reference text or structure you changed.
