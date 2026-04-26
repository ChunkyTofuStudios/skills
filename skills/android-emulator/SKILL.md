---
name: android-emulator
description: Run, debug, screenshot, and interact with a Flutter app on a running Android emulator via adb and the qemu console — boot/shut down an AVD, launch `flutter run` in the background, capture compact 360px-wide JPEG screenshots, dump the Android accessibility tree to find addressable widgets, tap by label or coordinates, long-press, swipe, and pinch-zoom (multi-touch). Use this skill whenever the user wants to launch, test, QA, take screenshots of, reproduce a bug in, verify a layout on, or otherwise interact with a Flutter app on Android — even when they don't say "emulator", "adb", or "screenshot" explicitly (e.g. "see what the home screen looks like", "try the new button", "check the layout on Pixel"). Auto-detects the project's applicationId, AVD, and `fvm flutter` vs `flutter`; falls back to ANDROID_EMU_* env vars.
license: MIT
metadata:
  author: Chunky Tofu Studios
  source: https://github.com/chunkytofustudios/skills
---

# Android emulator (Flutter)

A bash helper that wraps `adb` and the qemu emulator console so an AI agent can **see** (screenshots, accessibility tree) and **act on** (tap, long-press, swipe, pinch) a Flutter app running on an Android emulator. Computer-use APIs cannot reach the emulator window (qemu has no macOS app bundle), and `adb shell input` is single-touch only — this script bridges both gaps.

## When to use this

The user wants to launch, debug, smoke-test, QA, or screenshot a Flutter app on Android. Reach for this skill before resorting to coordinate-guessing, manual screenshotting via DevTools, or asking the user to run `flutter run` themselves.

## Setup

The script assumes a working **Android SDK** install (with `adb` and `emulator` on `$PATH` or in `~/Library/Android/sdk/` / `~/Android/Sdk/`), at least one **AVD** created, and **Flutter** (or [`fvm`](https://fvm.app/)) installed. macOS-only utility: `sips` (used to resample screenshots — ships with macOS). On Linux, swap in `convert` from ImageMagick if porting.

The script is at `scripts/emu.sh` relative to this skill. Once the skill is wired into your project (see [README.md](../../README.md#installing-a-skill)), agents call it with that relative path.

## Quick start (cold boot to interactive)

```bash
scripts/emu.sh boot        # start an AVD (cold boot), idempotent
scripts/emu.sh run         # flutter build & install in background (~30–60s first time)
scripts/emu.sh wait-run    # blocks until attached or errors (180s timeout)
scripts/emu.sh health      # sanity check
scripts/emu.sh ui-list     # see what's on screen — start here, not screenshot
```

`run` auto-detects the project root (walks up to find `pubspec.yaml`) and uses `fvm flutter` if the project pins it. Always pair `run` with `wait-run` instead of `sleep` — the daemon's stdin is gone, so timing is the only signal that the build finished.

## Commands

### Emulator lifecycle

| Command | What it does |
|---|---|
| `boot` | Start the AVD in cold boot (`-no-snapshot-load`) and block until `sys.boot_completed`. Idempotent — if the device is already online, returns immediately. AVD defaults to the first one listed by `emulator -list-avds`; pin with `ANDROID_EMU_AVD`. |
| `exit` | Shut down the running emulator via the qemu console (`kill`). |
| `health` | One-shot status: connection, AVD name, resolution, foreground app, detected project root, detected package, flutter log size. **Run this first** to orient. Exits non-zero if the device isn't connected. |
| `devices` / `size` / `foreground` | Raw `adb devices` / `wm size` / focused activity. |
| `app-running` | Exit 0 if the target package is the focused app, 1 otherwise. Use in scripts. |

### App control

| Command | What it does |
|---|---|
| `launch` | `monkey`-launch the already-installed APK (no rebuild). |
| `stop` | `am force-stop` the app. |
| `run` | Start `flutter run -d <device>` in background. Log: `/tmp/android-emu-flutter.log`. Truncates the log each call. Uses `fvm flutter` when the project has a `.fvm/` directory and `fvm` is on `PATH`. |
| `wait-run` | Block until the log contains `Flutter run key commands.` (attached) or a build failure marker. 180s timeout (`ANDROID_EMU_WAIT_SECS` to override). Exit 0 on success, 1 on error/timeout. **Always pair `run` with `wait-run` instead of `sleep`.** |
| `kill-run` | Kill the flutter daemon and force-stop the app. The only way to stop a backgrounded `flutter run`, since stdin is gone. |
| `log [N]` | Tail last N lines of `/tmp/android-emu-flutter.log` (default 50). |

### Input — coordinate-based (all coords in screenshot pixels, 360-wide space)

| Command | What it does |
|---|---|
| `screenshot` | Capture screen → `/tmp/android-emu-shot-<id>.jpg` (360px wide JPEG q85). The exact path is printed on stdout — `Read` that path to see the current state. Per-invocation paths keep concurrent callers from clobbering each other. |
| `tap X Y` | Single tap. |
| `hold X Y [MS]` | Long-press (default 800ms). |
| `swipe X1 Y1 X2 Y2 [MS]` | Swipe (default 300ms). Shorter ms = fling. |
| `pinch out\|in [CX CY SG EG]` | Two-finger pinch. `out` zooms in. Defaults: center (180,367), start gap 67, end gap 333. Pinch goes through the qemu console — `adb input` cannot do multi-touch. |

### Input — label-based (preferred — no coordinate guessing)

These read Android's accessibility tree via `uiautomator dump` and act on the node whose `text`, `content-desc`, `resource-id`, or `hint` matches the given `LABEL`. Exact match wins over substring fallback. `hint` covers empty `TextField`s (Flutter's `InputDecoration.labelText` surfaces there).

| Command | What it does |
|---|---|
| `ui-list` | Human-readable list of on-screen labelled nodes: screenshot-space center, tap/hold/scroll flags, label. **Start here** to discover what's addressable. |
| `ui-find LABEL` | Print device-px bounds and screenshot-px center for the first match. Debugging aid. |
| `ui-dump` | Raw uiautomator XML. Useful when `ui-list` hides the node you want (e.g. an unlabelled parent). |
| `tap-label LABEL` | Tap the center of the first matching node. |
| `hold-label LABEL [MS]` | Long-press the center of the first matching node. |

**Coords are in screenshot space.** The `cx cy` columns in `ui-list` use the same 360-wide frame as the screenshot JPEG and `tap X Y`, so you can cross-reference the two without rescaling.

Example `ui-list` output:

```
 cx   cy  flags          label
 27   70  tap            'Settings'
137  141  tap            'Get started'
 47  254  tap            'New project'
 45  760  tap            'Home\nTab 1 of 4'
135  760  tap            'Search\nTab 2 of 4'
225  760  tap            'Library\nTab 3 of 4'
315  760  tap            'Profile\nTab 4 of 4'
```

Then `tap-label "Search"` — substring match is enough; you do **not** have to include the `\nTab 2 of 4` suffix.

## Choosing screenshot vs ui-list

Screenshots are ~30–60 KB each and add up fast in the conversation context, while `ui-list` output is ~2 KB. **Default to `ui-list`.** If the labels on screen changed, you're on a new screen — that's what most navigation steps need to confirm.

Reach for `screenshot` only when:

1. **Content is inherently visual** — a `CustomPainter`, image/camera preview, color swatches, thumbnails — anything rendered as pixels rather than widgets.
2. **Labels don't differentiate** — same screen, state change that isn't reflected in the accessibility tree (e.g. a slider dragged to a new value, a toggled chip that re-uses the same text).
3. **Debugging a `tap-label` failure** — when a label match fails or taps the wrong thing, a screenshot is faster than reading `ui-dump` to figure out what's on screen.

Heuristic: after a tap, check `ui-list` first. Screenshot only if it doesn't answer your question.

## Making widgets addressable (Flutter Semantics)

`uiautomator dump` reads Android's accessibility tree. In a Flutter app, that tree is empty unless the app's semantics tree is exposed. Two ways:

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

   Material widgets (`BottomNavigationBar`, `IconButton` with `tooltip:`, `TextButton`, `TextField`, etc.) emit Semantics automatically — no per-widget wrapping needed for the nav bar, app-bar buttons, form fields, etc.

2. **Enable an accessibility service on the AVD** — TalkBack or a similar service forces the platform to materialize the tree. Heavier-handed; option (1) is cleaner.

If `ui-list` prints `(no labelled nodes found — is Flutter semantics enabled?)`, neither is in effect.

For an icon-only custom widget that needs to be addressable:

```dart
Semantics(
  identifier: 'some_stable_id',   // optional, locale-invariant
  label: 'Human readable name',
  child: ...,
)
```

`identifier` is preferred for tests because it doesn't change with locale; `label` is what assistive tech (and `tap-label`) reads.

## Gotchas

- **`adb shell input swipe X Y X Y MS` is not a long-press.** It sends DOWN/UP so close together that Flutter's `LongPressGestureRecognizer` treats it as a cancelled tap and never fires `onLongPress`. Use `hold` (or `hold-label`) — they send a real `motionevent DOWN`, sleep, `motionevent UP` pair.
- **Pinch does not go through `adb`.** `adb shell input` is single-touch only. Multi-touch via `sendevent /dev/input/event1` requires either root (production AVDs deny `adb root`) or SELinux permissions the `shell` user lacks. The `pinch` command falls back to qemu's host-side console (`localhost:5554`, auth token at `~/.emulator_console_auth_token`), which writes events directly into the virtual input device.
- **Without semantics, the app is one opaque rectangle.** `ui-list` on a release build (or a debug build that didn't call `ensureSemantics()`) returns nothing useful. Fix it in the app, not by guessing coordinates — see the section above.
- **`ui-list` only shows nodes with a label.** Unlabelled parents/wrappers won't appear; use `ui-dump` to see the raw XML if a node you expect is missing.
- **Hot-restart vs full rebuild.** `run` always launches a fresh `flutter run`. If you want hot-reload after a code change, send `r\n` to the daemon's stdin — but the script backgrounds it (so stdin is gone) and assumes you'll `kill-run` and `run` again. For tighter inner loops, run `flutter run` in your own terminal and use only the input/screenshot commands here.
- **First-launch dialogs.** Many apps show splash, onboarding, or upsell screens on first launch. Use `ui-list` to see what's blocking, then `tap-label` to dismiss (e.g. `tap-label "Close"`, `tap-label "Skip"`). Don't rely on a fixed sleep — wait until `ui-list` shows the screen you expect.

## Typical workflows

### Cold start from nothing

```bash
scripts/emu.sh boot
scripts/emu.sh run
scripts/emu.sh wait-run
scripts/emu.sh health
scripts/emu.sh ui-list
```

### Debug something the user is seeing

1. `scripts/emu.sh ui-list` — what's on screen now?
2. Reproduce the user's path: `tap-label "…"` for each step.
3. After the suspect action, `ui-list` again. If it looks right, screenshot only if the bug is visual.
4. `scripts/emu.sh log 100` — tail the flutter log to catch exceptions/asserts.

### Stop a debug session cleanly

```bash
scripts/emu.sh kill-run
```

Don't try `TaskStop` from inside the agent — the background task may already be reaped, and either way the app keeps running on the device until force-stopped.

### Full teardown

```bash
scripts/emu.sh kill-run    # stop flutter + app
scripts/emu.sh exit        # shut down the emulator
```

## Why screenshots are 360px-wide JPEGs

Full-resolution PNGs (1080×2424 on a Pixel-class AVD) are 600 KB–1.5 MB and balloon the conversation context. PNG resize alone barely helps — the encoder isn't aggressive. JPEG q85 at 360px wide gets to ~25–60 KB while staying legible for UI labels and small text. The 360-wide image is the canonical input space for `tap`/`hold`/`swipe`/`pinch` — the script handles device-side scaling itself, so the resolution is invariant from the caller's point of view. Override the JPEG quality with `ANDROID_EMU_SHOT_QUALITY` if labels are illegible (try 92) or you need smaller files (try 70).

## Concurrent use

Two agents can share one emulator safely for read-only commands. `screenshot`, `ui-list`, `ui-dump`, `ui-find`, `tap-label`, and `hold-label` all write scratch files to per-invocation paths (suffixed with the script's PID, configurable via `ANDROID_EMU_TMP_ID`) both on the host and on `/sdcard/`, so simultaneous calls don't corrupt each other. That's why `screenshot` prints the path it wrote — don't hardcode `/tmp/android-emu-shot.jpg`; read the path the command echoed.

Shared state that isn't per-invocation: the emulator itself (input is a single stream — simultaneous taps will interleave unpredictably), the flutter daemon (`/tmp/android-emu-flutter.log`, one daemon per device), and the device-size cache (`/tmp/android-emu-device-size`). The practical pattern: one agent owns `run` / `wait-run` / `kill-run`, and both can freely take screenshots or list UI at the same time.

## Auto-detection

| What | How |
|---|---|
| Project root | Walks up from `$PWD` looking for `pubspec.yaml`. Override with `ANDROID_EMU_PROJECT_ROOT`. |
| `applicationId` | Parsed from `android/app/build.gradle` or `android/app/build.gradle.kts` (first `applicationId "…"` line). Override with `ANDROID_EMU_PKG`. |
| AVD | First entry of `emulator -list-avds` if `ANDROID_EMU_AVD` isn't set. With multiple AVDs, pin one explicitly. |
| `flutter` CLI | `fvm flutter` when the project has a `.fvm/` directory and `fvm` is on `PATH`; otherwise `flutter`. Override with `ANDROID_EMU_FLUTTER_CMD`. |

`scripts/emu.sh health` prints the resolved values — run it first if anything seems off.

## Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `ANDROID_EMU_DEVICE` | `emulator-5554` | adb device serial |
| `ANDROID_EMU_AVD` | first listed | AVD to boot |
| `ANDROID_EMU_PKG` | parsed from gradle | applicationId |
| `ANDROID_EMU_PROJECT_ROOT` | walked up from `$PWD` | Flutter project root |
| `ANDROID_EMU_FLUTTER_CMD` | `flutter` or `fvm flutter` | flutter command override |
| `ANDROID_EMU_CONSOLE_PORT` | `5554` | qemu console port |
| `ANDROID_EMU_SHOT_QUALITY` | `85` | JPEG quality (1–100) |
| `ANDROID_EMU_WAIT_SECS` | `180` | `wait-run` timeout |
| `ANDROID_EMU_BOOT_SECS` | `180` | `boot` timeout |
| `ANDROID_EMU_TMP_ID` | `$$` (script PID) | scratch-file suffix; pin across calls when multiple agents share one emulator |
