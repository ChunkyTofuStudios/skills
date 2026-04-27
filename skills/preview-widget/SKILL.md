---
name: preview-widget
description: Preview a single Flutter widget in isolation using the built-in Flutter Widget Previewer (`flutter widget-preview`) — wires up a project-specific `previewWrapper` so the widget renders against the app's real theme and providers, launches the local preview server, and lets the agent take headless-Chrome screenshots of the live preview while a human follows along in their own browser. Use whenever the user wants to design, iterate on, dogfood, share, audit, or sanity-check a standalone Flutter widget — even when they don't say "previewer" (e.g. "let me see the new button", "show me dark mode for this card", "throw this widget on a preview", "iterate on the empty state", "preview just the badge", "what does this look like at tablet width"). For full-screen design polish on a running app, use `design-polish` + `android-emulator` instead. Skips: non-Flutter UIs, full-app QA flows, projects on Flutter < 3.35.
license: MIT
metadata:
  author: Chunky Tofu Studios
  source: https://github.com/chunkytofustudios/flutter-skills
---

# Preview a Flutter widget in isolation

Render a single widget in Flutter's Widget Previewer so you and the human can iterate on it — design tweaks, light/dark variants, tablet sizing — without booting the full app. The agent screenshots the live preview headlessly; the human optionally opens the same `localhost` URL in their own Chrome to follow along.

## When to use this

All three must hold — if any is false, this skill is the wrong tool:

1. The project is a **Flutter** project (`pubspec.yaml` at the cwd, `lib/` exists).
2. **Flutter ≥ 3.35** is on PATH (or via `fvm flutter`). The previewer is experimental on stable but stable enough to design against; older Flutters don't have it.
3. The user wants to iterate on a **single widget**, not a full screen or end-to-end flow. Full-screen visual work is what `design-polish` + `android-emulator` is for.

## Setup (caller's machine)

| Requirement | How to satisfy |
|---|---|
| Flutter ≥ 3.35 | Run `bash scripts/check_preview_support.sh` — fails loudly with an upgrade hint if too old. Override the Flutter binary with `FLUTTER_BIN=…` (default: `flutter`, falls back to `fvm flutter`). |
| Google Chrome / Chromium | Used headlessly by `screenshot_preview.sh` to capture previews. macOS picks up `/Applications/Google Chrome.app` automatically; on Linux any of `google-chrome`, `chromium`, `chromium-browser` on PATH works. Override with `CHROME_BIN=/path/to/chrome`. |
| `bash` 3.2+ (macOS default), `awk`, `grep`, `find` | Standard. No Python or Node needed. |

There's no per-machine auth, account, or token — everything runs on `localhost`.

## Bundled scripts

- **`scripts/check_preview_support.sh`** — verifies Flutter ≥ 3.35 and prints the resolved binary + version. Exit 0 = ready, exit 1 = version too old, exit 127 = no Flutter found.
- **`scripts/start_preview.sh`** — launches `flutter widget-preview start` in the background, parses the URL out of its log, and writes a small JSON state file. Idempotent: re-runs return the existing URL. `--stop` tears the server down. Default state dir: `./.preview-widget/` (override with `PREVIEW_WIDGET_STATE_DIR`).
- **`scripts/screenshot_preview.sh`** — headless-Chrome screenshot of the running previewer. Flags: `--out <path>`, `--size WxH` (default `1600x2400`), `--wait <ms>` (virtual-time budget, default `10000`), `--url <url>` (override the state file). Prints the absolute output path on stdout.
- **`scripts/list_previews.sh`** — greps `lib/` for `@Preview(...)`, `@<Custom>Preview(...)`, and `extends (Multi)?Preview` definitions so you don't re-add what's already there.

All four ship with `--help`. Read it before improvising flags.

## One-time setup per Flutter project

Before annotating any widget, the project needs a **preview wrapper** — a top-level `Widget previewWrapper(Widget child)` function that recreates the global ancestor chain a real widget assumes (theme cubit / `ProviderScope` / `MaterialApp` / localizations / `MediaQuery` overrides / etc.). The previewer's `theme:` parameter alone is **not** enough for any non-trivial app: widgets that read `BlocBuilder<ThemeCubit, …>` or `Theme.of(context)` directly will throw or render wrong without the cubit in their tree.

Steps:

1. Read the project's `lib/main.dart` and `lib/app.dart` (or equivalent root). Identify everything wrapping the `MaterialApp` — `MultiBlocProvider`, `ProviderScope`, `MultiRepositoryProvider`, custom `InheritedWidget`s, `MediaQuery` overrides, locale/router config.
2. Copy `assets/preview_wrapper.dart.template` to `lib/preview_wrapper.dart`.
3. Fill in the imports and provider list to mirror the real root tree, **stubbing** any provider that needs runtime state (e.g. `UxCubit` gets a default `DeviceType.mobile`; repository cubits get fake/empty states). The wrapper is a const-time tearoff, so all callbacks must be top-level public functions.
4. See [`references/wrapper_patterns.md`](references/wrapper_patterns.md) for recipes (BLoC, Riverpod, GoRouter, Localizations, `MediaQuery`, fonts).

If you're unsure which providers a widget actually needs, search the widget body for `Theme.of`, `BlocBuilder<`, `context.watch<`, `context.read<`, `ProviderScope.containerOf`, `MediaQuery.of`, `Localizations.of`, `GoRouter.of` — every one of those is a load-bearing ancestor.

## Per-widget workflow

### 1. Pick the annotation target

`@Preview` and `@MultiPreview` apply to:

- top-level functions returning `Widget` or `WidgetBuilder`
- public static methods on a class
- public widget constructors / factories with **no required arguments**

All values passed to the annotation must be **const**, and any callback (`wrapper:`, `theme:`, `localizations:`) must be a public top-level (or static) function — closures over private state are rejected by the previewer.

### 2. Annotate

Single preview, against the project's wrapper:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../preview_wrapper.dart';

@Preview(name: 'MyButton — default', wrapper: previewWrapper)
Widget myButtonPreview() => const MyButton();
```

Multi-preview matrix (light + dark + tablet) via the bundled `assets/multi_preview.dart.template` → `lib/preview_variants.dart`:

```dart
@StandardPreview()
Widget myButtonPreview() => const MyButton();
```

See [`references/preview_annotations.md`](references/preview_annotations.md) for the full `@Preview` parameter list and target-restriction rules.

### 3. Launch the preview server

```bash
bash scripts/start_preview.sh
# → Preview: http://localhost:51530
```

Idempotent — re-running while a server is up just re-prints the URL. The state file at `.preview-widget/server.json` carries `{ "url", "pid", "log" }`. Add `.preview-widget/` to `.gitignore`.

### 4. Screenshot the running preview

```bash
bash scripts/screenshot_preview.sh
# → /tmp/preview-widget/preview-001.png
```

Then `Read` the PNG to see the live preview. Default capture is 1600×2400 viewport (fits ~3 stacked preview tiles); pass `--size 1920x4000` for a taller capture or `--out /tmp/foo.png` to control the path. If the first paint looks blank, bump `--wait 20000` (20s) — that's the canvas/Skia bootstrap budget.

### 5. Iterate

```text
edit Dart → sleep 2 → screenshot → read → reason → repeat
```

The previewer hot-restarts automatically on file save, so no manual restart is needed. The 2-second sleep gives hot restart time to settle before the next screenshot.

### 6. Always print the URL at the end of your turn

Every assistant message that touched the previewer must end with the line:

```text
Preview: http://localhost:<port>
```

This lets the human drop in at any time, or come back later — the server keeps running until `start_preview.sh --stop`.

### 7. Clean up when done

```bash
bash scripts/start_preview.sh --stop
```

Kills the server and removes the state file. Optional — leaving it running between sessions is fine.

## Discovering existing previews

Before adding a new `@Preview`, see what's already in the project:

```bash
bash scripts/list_previews.sh
# lib/widgets/foo.dart:42  @Preview(name: 'Foo - light', wrapper: previewWrapper)
# lib/widgets/bar.dart:17  @StandardPreview()
# lib/preview_variants.dart:9  final class StandardPreview extends MultiPreview {
```

Pass an explicit root to scope: `bash scripts/list_previews.sh lib/src/widgets`.

## Gotchas

- **The wrapper is the load-bearing piece.** A naive `@Preview` without `wrapper: previewWrapper` will crash or render wrong in any app that reads providers/cubits inside widget bodies. If a widget does `BlocBuilder<ThemeCubit>` and the wrapper doesn't put a `ThemeCubit` above it, the preview throws `ProviderNotFoundException` — not a previewer bug.
- **`size:` constrains the widget, not the canvas.** An unconstrained widget without `size:` is auto-sized to roughly half the previewer canvas, which is rarely what you want for a single component. Pass `size: Size(360, 80)` for a button-sized component or `size: Size(1024, 1366)` for a tablet layout.
- **All annotation values must be const.** Including the `wrapper:`, `theme:`, and `localizations:` callbacks — they have to be public top-level (or static) function tearoffs, not lambdas. Anything captured from outside fails compile.
- **Asset paths must be `packages/<name>/...`** in previewed widgets. A widget that does `Image.asset('assets/foo.png')` works in the real app but breaks in the previewer; switch to `Image.asset('packages/<your_pkg>/assets/foo.png')` for both contexts.
- **No `dart:io`, `dart:ffi`, or native plugins.** The previewer runs in Chrome — anything that touches `File`, `Platform`, native channels, or platform plugins throws when the preview tries to render. Conditional imports (`if (dart.library.html)` etc.) sidestep this.
- **First paint is slow.** Flutter web bootstraps to JS/Skia on the first preview load — 5–10s is typical, longer on slow disks. The `--wait 10000` default is usually enough; bump it (e.g. `--wait 20000`) before assuming the screenshot is broken.
- **Whole-page screenshots only.** The previewer doesn't expose per-preview URLs, so `screenshot_preview.sh` captures the entire page (all preview tiles stacked). The agent reasons about which tile is which by the `name:` label rendered above it. If you only want one preview visible, temporarily comment out the others — or use a tall `--size` and rely on the `group:` parameter to keep related variants adjacent.
- **Hot-restart is automatic but not instant.** After editing a `.dart` file, give the previewer ~1–2s before screenshotting. Edits to the wrapper itself take longer; if a screenshot still shows the old state after `sleep 5`, restart the server (`--stop` then re-run).
- **One project per server.** As of Flutter 3.35 the previewer doesn't support multi-project workspaces in the IDE flow; the CLI server only knows about the current project. If the project uses Pub workspaces, run the server from the workspace root.
- **`flutter widget-preview` is experimental.** APIs and CLI flags may shift between Flutter versions. If a flag this skill uses stops working, check `flutter widget-preview --help` against what `start_preview.sh` passes.

## Quick reference

```bash
# 0. (one-time) Verify Flutter is recent enough.
bash skills/preview-widget/scripts/check_preview_support.sh

# 1. (one-time per project) Copy the wrapper template, fill in providers.
cp skills/preview-widget/assets/preview_wrapper.dart.template lib/preview_wrapper.dart
# …edit lib/preview_wrapper.dart, then add `.preview-widget/` to .gitignore

# 2. Annotate the widget (in its own file or alongside it).
#    @Preview(name: 'MyWidget', wrapper: previewWrapper)
#    Widget myWidgetPreview() => const MyWidget();

# 3. Start server, capture URL.
bash skills/preview-widget/scripts/start_preview.sh
# → http://localhost:51530

# 4. Iterate: edit → sleep 2 → screenshot → read → repeat.
bash skills/preview-widget/scripts/screenshot_preview.sh

# 5. Stop when done.
bash skills/preview-widget/scripts/start_preview.sh --stop
```

End every assistant turn that touched the previewer with `Preview: http://localhost:<port>` so the human can follow along.
