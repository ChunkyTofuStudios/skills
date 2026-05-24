---
name: ios-simulator
description: Run, debug, screenshot, and interact with a Flutter app on a running iOS Simulator via `xcrun simctl` and WebDriverAgent — boot/shut down a simulator, launch `flutter run` in the background, capture compact 360px-wide JPEG screenshots, dump the iOS accessibility tree to find addressable widgets, tap by label or coordinates, long-press, swipe, and pinch-zoom (multi-touch). Use this skill whenever the user wants to launch, test, QA, take screenshots of, reproduce a bug in, verify a layout on, or otherwise interact with a Flutter app on iOS — even when they don't say "simulator", "xcrun", or "screenshot" explicitly (e.g. "see what the home screen looks like", "try the new button", "check the layout on iPhone"). Auto-detects the project's bundle identifier, simulator UDID, and `fvm flutter` vs `flutter`; falls back to IOS_SIM_* env vars.
license: MIT
metadata:
  author: Yasin Günes (port of Chunky Tofu Studios android-emulator skill)
  source: local
---

# iOS Simulator (Flutter)

A bash helper that wraps `xcrun simctl` and a local **WebDriverAgent** (WDA) instance so an AI agent can **see** (screenshots, accessibility tree) and **act on** (tap, long-press, swipe, pinch) a Flutter app running on an iOS Simulator. `xcrun simctl` has no input API for taps/swipes/multi-touch — WDA bridges that gap via Apple's XCTest framework.

## When to use this

The user wants to launch, debug, smoke-test, QA, or screenshot a Flutter app on iOS. Reach for this skill before resorting to coordinate-guessing, manual screenshotting via DevTools, or asking the user to run `flutter run` themselves.

## Setup

The script assumes a working **Xcode** install with the iOS Simulator runtime, at least one iOS Simulator created (Xcode → Settings → Platforms → iOS), and **Flutter** (or [`fvm`](https://fvm.app/)) installed. macOS-only: this skill cannot run on Linux/Windows (`xcrun simctl` is Apple-only and WDA needs Xcode to build).

For **tap/swipe/label-based** commands you also need WebDriverAgent. Run `scripts/sim.sh setup-wda` once — it clones [appium/WebDriverAgent](https://github.com/appium/WebDriverAgent), builds it with Xcode (~300 MB, 2–5 minutes the first time), and stores the build under `~/.local/share/ios-simulator-skill/WebDriverAgent/`. Lifecycle commands (`boot`, `screenshot`, `run`, `log`) work without WDA.

The script is at `scripts/sim.sh` relative to this skill.

## Quick start (cold boot to interactive)

```bash
scripts/sim.sh boot        # boot a Simulator (defaults to first available iPhone)
scripts/sim.sh run         # flutter build & install in background (~30–60s first time)
scripts/sim.sh wait-run    # blocks until attached or errors (180s timeout)
scripts/sim.sh health      # sanity check
scripts/sim.sh ui-list     # see what's on screen — start here, not screenshot (requires WDA)
```

`run` auto-detects the project root (walks up to find `pubspec.yaml`) and uses `fvm flutter` if the project pins it. Always pair `run` with `wait-run` instead of `sleep` — the daemon's stdin is gone, so timing is the only signal that the build finished.

## Commands

### Simulator lifecycle

| Command | What it does |
|---|---|
| `boot` | Boot the Simulator and open Simulator.app. Idempotent — if already booted, returns immediately. Defaults to the first available iPhone; pin with `IOS_SIM_UDID` (UUID) or `IOS_SIM_NAME` (e.g. "iPhone 15 Pro"). |
| `exit` | Shut down the Simulator (`xcrun simctl shutdown`). Does NOT quit Simulator.app — that's user-controlled. |
| `health` | One-shot status: connection, simulator name/UDID, runtime, resolution, foreground bundle, detected project root, detected bundle id, flutter log size. **Run this first** to orient. Exits non-zero if no simulator is booted. |
| `devices` | `xcrun simctl list devices available` filtered to iPhones. |
| `foreground` | Current foreground bundle id (via WDA). When WDA isn't running, falls back to listing all running third-party apps via `launchctl list` — less precise but answers "is my app alive?". |
| `app-running` | Exit 0 if the target bundle is the foreground app, 1 otherwise. Use in scripts. |

### App control

| Command | What it does |
|---|---|
| `launch` | `xcrun simctl launch` the already-installed app (no rebuild). |
| `stop` | `xcrun simctl terminate` the app. |
| `run` | Start `flutter run -d <udid>` in background. Log: `/tmp/ios-sim-flutter-<id>.log` (per-invocation, keyed on `IOS_SIM_TMP_ID`). Writes the daemon pid to `<log>.pid`. Uses `fvm flutter` when `.fvm/` or `.fvmrc` is present. |
| `wait-run` | Block until the log shows `Flutter run key commands.` or a build failure. **Auto-extends timeout to 900s on cold builds** (no DerivedData for this project) — overridable with `IOS_SIM_WAIT_SECS`. **Auto-surfaces actionable error lines** from the log on failure (filters out warnings and source-code "Error" mentions). Prints a build-progress hint every 30s so long waits aren't silent. **Always pair `run` with `wait-run` — not `sleep`.** |
| `kill-run` | Kill the flutter daemon (via `<log>.pid`, falls back to `pkill -f flutter_tools.snapshot`) and terminate the app. |
| `log [-f] [N]` | Tail last N lines (default 50) of the per-invocation log; with `-f`, follow live. Flutter's print output appears as plain lines; logging-package severity prefixes (`[F]/[I]/[W]/[S]`) are at line-start (unlike Android's logcat wrapping). Filter with `grep -E '\[(W\|S)\]'`. |

### Pre-flight (read-only diagnostics)

Run **`preflight`** before any first build of a project — it catches the common blockers (low disk, missing `flutterfire`, missing `cmake`, FVM not installed, Pods drift, no `pub get`) in ~50 ms instead of 5–15 min into a failed build. Both commands are pure read-only — no files touched, no caches cleared.

| Command | What it does |
|---|---|
| `preflight` | Validates disk free, FVM version installed, `flutterfire` CLI (if Firebase in pubspec.lock), `cmake` (if `flutter_soloud`), `Podfile.lock` vs `Pods/Manifest.lock` sync, `.dart_tool/`. Exits non-zero on blockers, prints a checklist. |
| `disk-check` | Free GB vs an estimated build need for this project. Estimate goes up for projects pulling Branch SDK, AppsFlyer, Amplitude, or `flutter_soloud`. |

### Input — coordinate-based (all coords in screenshot pixels, 360-wide space)

WDA required. Run `setup-wda` once if these commands report `WDA not running`.

| Command | What it does |
|---|---|
| `screenshot` | Capture screen → `/tmp/ios-sim-shot-<id>.jpg` (360px wide JPEG q85). The exact path is printed on stdout — `Read` that path to see the current state. Per-invocation paths keep concurrent callers from clobbering each other. Does NOT require WDA. |
| `tap X Y` | Single tap via WDA. |
| `hold X Y [MS]` | Long-press (default 800ms) via WDA's `touchAndHold`. |
| `swipe X1 Y1 X2 Y2 [MS]` | Swipe (default 300ms) via WDA's `dragfromtoforduration`. Shorter ms = fling. |
| `pinch out\|in [CX CY SCALE]` | Two-finger pinch. `out` zooms in (scale > 1), `in` zooms out (scale < 1). Defaults: center (180,367), scale 2.0 for out / 0.5 for in. Uses WDA's `pinch` action. |

### Input — label-based (preferred — no coordinate guessing)

WDA required. These read iOS's accessibility tree via WDA's `/source` endpoint and act on the element whose `name`, `label`, `value`, or `accessibilityIdentifier` matches the given `LABEL`. Exact match wins over substring fallback.

| Command | What it does |
|---|---|
| `ui-list` | Human-readable list of on-screen labelled elements: screenshot-space center, tap/hold/scroll flags, label. **Start here** to discover what's addressable. |
| `ui-find LABEL` | Print logical-point bounds and screenshot-px center for the first match. Debugging aid. |
| `ui-dump` | Raw WDA accessibility-tree XML. Useful when `ui-list` hides the element you want (e.g. an unlabelled parent). |
| `tap-label LABEL` | Tap the center of the first matching element. |
| `hold-label LABEL [MS]` | Long-press the center of the first matching element. |

**Coords are in screenshot space.** The `cx cy` columns in `ui-list` use the same 360-wide frame as the screenshot JPEG and `tap X Y`, so you can cross-reference the two without rescaling.

## Filtering logs by severity

Flutter on iOS doesn't wrap `print()` lines with logcat's `I/flutter ( PID): ` prefix like Android does — output goes straight to the daemon log:

```bash
scripts/sim.sh log 500 | grep -E '\[(W|S)\]'        # warnings + severe
scripts/sim.sh log -f  | grep --line-buffered -E '\[S\]'   # follow severe
```

## Choosing screenshot vs ui-list

Screenshots are ~30–60 KB each and add up fast in the conversation context, while `ui-list` output is ~2 KB. **Default to `ui-list`.** If the labels on screen changed, you're on a new screen — that's what most navigation steps need to confirm.

Reach for `screenshot` only when:

1. **Content is inherently visual** — a `CustomPainter`, image/camera preview, color swatches, thumbnails — anything rendered as pixels rather than widgets.
2. **Labels don't differentiate** — same screen, state change that isn't reflected in the accessibility tree (e.g. a slider dragged to a new value, a toggled chip that re-uses the same text).
3. **Debugging a `tap-label` failure** — when a label match fails or taps the wrong thing, a screenshot is faster than reading `ui-dump` to figure out what's on screen.

Heuristic: after a tap, check `ui-list` first. Screenshot only if it doesn't answer your question.

## Making widgets addressable (Flutter Semantics)

WDA reads iOS's accessibility tree. In a Flutter app, that tree is populated when the app's semantics tree is exposed. Two ways:

1. **Enable semantics in debug builds** — add this near the top of `main()`:

   ```dart
   import 'package:flutter/foundation.dart';
   import 'package:flutter/semantics.dart';

   void main() {
     if (kDebugMode) {
       SemanticsBinding.instance.ensureSemantics();
     }
     runApp(const MyApp());
   }
   ```

   Material widgets (`BottomNavigationBar`, `IconButton` with `tooltip:`, `TextButton`, `TextField`, etc.) emit Semantics automatically — no per-widget wrapping needed.

2. **Enable VoiceOver on the Simulator** — `xcrun simctl ui <udid> accessibility VoiceOver on`. Heavier-handed; option (1) is cleaner.

If `ui-list` prints `(no labelled elements found — is Flutter semantics enabled?)`, neither is in effect.

For an icon-only custom widget that needs to be addressable:

```dart
Semantics(
  identifier: 'some_stable_id',   // optional, locale-invariant — exposed as accessibilityIdentifier on iOS
  label: 'Human readable name',   // exposed as accessibilityLabel on iOS
  child: ...,
)
```

`identifier` is preferred for tests because it doesn't change with locale; `label` is what VoiceOver (and `tap-label`) reads.

## Gotchas

- **`xcrun simctl` cannot tap or swipe.** Apple deliberately limits Simulator automation. All input goes through WDA.
- **WDA must be running** before `tap`/`swipe`/`pinch`/`ui-*` commands. The script auto-spawns it if `setup-wda` has been done; otherwise commands fail with a clear error.
- **Without semantics, the app is one opaque view.** `ui-list` on a release build (or a debug build that didn't call `ensureSemantics()`) returns nothing useful. Fix it in the app, not by guessing coordinates — see the section above.
- **`ui-list` only shows nodes with a label.** Unlabelled parents/wrappers won't appear; use `ui-dump` to see the raw XML if an element you expect is missing.
- **Hot-restart vs full rebuild.** `run` always launches a fresh `flutter run`. If you want hot-reload after a code change, send `r\n` to the daemon's stdin — but the script backgrounds it (so stdin is gone) and assumes you'll `kill-run` and `run` again.
- **First-launch dialogs.** Many apps show splash, onboarding, or upsell screens on first launch. Use `ui-list` to see what's blocking, then `tap-label` to dismiss (e.g. `tap-label "Close"`, `tap-label "Skip"`). Don't rely on a fixed sleep — wait until `ui-list` shows the screen you expect.
- **Bundle id detection picks the first non-Test target.** If your project has multiple iOS targets (Runner, RunnerExtension, Notifications…), override with `IOS_SIM_BUNDLE_ID` if `health` resolves the wrong one.
- **iOS 17 vs 26 differences.** WDA's selectors are stable across these, but UI Test infrastructure changed in iOS 17. If WDA fails to start, check `~/.local/share/ios-simulator-skill/wda.log` and consider rebuilding (`setup-wda --force`).

## Typical workflows

### Cold start from nothing

```bash
scripts/sim.sh boot
scripts/sim.sh run
scripts/sim.sh wait-run
scripts/sim.sh health
scripts/sim.sh ui-list
```

### Debug something the user is seeing

1. `scripts/sim.sh ui-list` — what's on screen now?
2. Reproduce the user's path: `tap-label "…"` for each step.
3. After the suspect action, `ui-list` again. If it looks right, screenshot only if the bug is visual.
4. `scripts/sim.sh log 100` — tail the flutter log to catch exceptions/asserts.

### Stop a debug session cleanly

```bash
scripts/sim.sh kill-run
```

### Full teardown

```bash
scripts/sim.sh kill-run    # stop flutter + app
scripts/sim.sh exit        # shut down the simulator
```

## Why screenshots are 360px-wide JPEGs

Full-resolution PNGs (1290×2796 on an iPhone 15 Pro) are 600 KB–1.5 MB and balloon the conversation context. PNG resize alone barely helps. JPEG q85 at 360px wide gets to ~25–60 KB while staying legible for UI labels and small text. The 360-wide image is the canonical input space for `tap`/`hold`/`swipe`/`pinch` — the script handles iOS-side scaling itself, so the resolution is invariant from the caller's point of view. Override the JPEG quality with `IOS_SIM_SHOT_QUALITY` if labels are illegible (try 92) or you need smaller files (try 70).

## WebDriverAgent setup

```bash
scripts/sim.sh setup-wda          # one-time build (clones + xcodebuild)
scripts/sim.sh setup-wda --force  # rebuild after Xcode update if WDA stops starting
```

The first build takes 2–5 minutes and adds ~300 MB to disk. After setup, the script auto-launches WDA in the background when an input command needs it; the WDA test daemon stops when the simulator shuts down.

## Concurrent use

Per-invocation scratch paths (suffixed with `IOS_SIM_TMP_ID`, default `$$`) cover screenshots, UI dumps, and the flutter daemon log + pidfile, so two agents driving **different** simulators don't clobber each other. Pin `IOS_SIM_UDID` and `IOS_SIM_TMP_ID` across the full `run` → `wait-run` → `log` → `kill-run` chain. `screenshot` echoes its output path — read that, don't hardcode it.

One simulator still hosts only one flutter daemon, so two agents on the same simulator must coordinate (typically: one owns `run`/`kill-run`, both freely `log`/`screenshot`/`ui-list`).

## Auto-detection

| What | How |
|---|---|
| Project root | Walks up from `$PWD` looking for `pubspec.yaml`. Override with `IOS_SIM_PROJECT_ROOT`. |
| Bundle id | Parsed from `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER = …;` in the first non-Test target). Override with `IOS_SIM_BUNDLE_ID`. |
| Simulator | First booted iOS device, else first available iPhone from `xcrun simctl list`. Pin with `IOS_SIM_UDID` (UUID) or `IOS_SIM_NAME`. |
| `flutter` CLI | `fvm flutter` when the project has a `.fvm/` directory or a `.fvmrc` file and `fvm` is on `PATH`; otherwise `flutter`. Override with `IOS_SIM_FLUTTER_CMD`. |

`scripts/sim.sh health` prints the resolved values — run it first if anything seems off.

## Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `IOS_SIM_UDID` | auto-detect | Simulator UUID (exact match) |
| `IOS_SIM_NAME` | first iPhone | Simulator device name (e.g. "iPhone 15 Pro") |
| `IOS_SIM_BUNDLE_ID` | parsed from pbxproj | bundle id override |
| `IOS_SIM_PROJECT_ROOT` | walked up from `$PWD` | Flutter project root |
| `IOS_SIM_FLUTTER_CMD` | `flutter` or `fvm flutter` | flutter command override |
| `IOS_SIM_WDA_PORT` | `8100` | WDA REST port |
| `IOS_SIM_SHOT_QUALITY` | `85` | JPEG quality (1–100) |
| `IOS_SIM_WAIT_SECS` | `180` | `wait-run` timeout |
| `IOS_SIM_BOOT_SECS` | `180` | `boot` timeout |
| `IOS_SIM_TMP_ID` | `$$` (script PID) | scratch-file suffix; pin across calls when multiple agents share one simulator |
| `IOS_SIM_TMP_DIR` | `/tmp` | host-side scratch dir |
