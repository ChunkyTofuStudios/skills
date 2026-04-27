---
name: symbolize-android-stacktrace
description: De-obfuscate (symbolize) an Android crash or ANR stacktrace exported from the Google Play Console for a Flutter app whose release build came from Codemagic CI/CD — fetches the matching `android_native_debug_symbols.zip` and `<AppName>_<N>_artifacts.zip` from Codemagic, then resolves every `pc 0x…` native frame and obfuscated Flutter frame to file:line via `llvm-addr2line`. Use whenever the user has a stacktrace (.txt/.log/pasted text) and wants to know which line of code crashed, even if they don't say "symbolize" — e.g. "what's causing this ANR?", "debug this Play Console crash", "translate this stack", "resolve these pc 0x… frames", "Codemagic build N crashed, here's the trace". Skips: iOS/dSYM symbolication, non-Codemagic builds (no symbol upload step), Crashlytics-only Dart exceptions with no native or Flutter frames.
license: MIT
metadata:
  author: Chunky Tofu Studios
  source: https://github.com/chunkytofustudios/flutter-skills
---

# Symbolize Android stacktrace (Flutter + Codemagic)

Turn an obfuscated Google Play Console crash/ANR stacktrace into a symbolized one (file + line for every native and Flutter frame), so you can reason about the bug.

## When to use this

All three must hold — if any is false, this skill is the wrong tool:

1. The app is a **Flutter** app targeting **Android**.
2. The trace was exported from the **Google Play Console** (Crash dashboard or ANR dashboard) — typically a `.txt`/`.log` with `pc 0x…` frames, optionally a `# Application:` / `# Version:` header.
3. The release build was produced by **Codemagic CI/CD**, with the workflow uploading both `android_native_debug_symbols.zip` *and* `<AppName>_<N>_artifacts.zip` (Flutter's split-debug-info `.symbols` files) as build artefacts. Without those, there is nothing to match the obfuscated PCs against.

If you're unsure whether the build was from Codemagic, check `codemagic.yaml` at the repo root or ask the user.

## Setup (caller's machine)

| Requirement | How to satisfy |
|---|---|
| `CODEMAGIC_API_TOKEN` env var | Generate at [Codemagic → User settings → Integrations → Personal API token](https://docs.codemagic.io/rest-api/codemagic-rest-api/). Export it before invoking the skill. |
| Android NDK with `llvm-addr2line` | Default lookup: `~/Library/Android/sdk/ndk/27.3.13750724`. Override with `ANDROID_NDK_HOME=/path/to/ndk`. Any recent NDK ships `llvm-addr2line` and `llvm-readelf`. |
| `unzip`, `python3` (3.10+), `bash` | Standard. The Python script uses stdlib only. |

If `CODEMAGIC_API_TOKEN` isn't set, **stop and ask the user** rather than guessing — every Codemagic call will 401.

There is **no other setup**. In particular, `gh` is **not** required — see [step 3](#3-fetch-symbols-from-codemagic).

## Bundled scripts

- **`scripts/codemagic_fetch_artifacts.py`** — three-mode discovery + download tool. JSON to stdout, progress to stderr.
- **`scripts/symbolize_flutter_anr.sh`** — order-insensitive trace + symbol bundler. Detects which input is which.

Both ship with `--help`. Read it before improvising flags.

## Workflow

### 1. Save the trace to a file

If the user pasted text rather than attaching a file, write it to `/tmp/play-stacktrace.log`. The bash script needs a real path (it `grep`s the file twice — for ABI detection and frame extraction).

### 2. Identify app + version from the trace

The trace usually contains the package name embedded in `/data/app/.../<applicationId>-…/split_config.<abi>.apk`:

```
/data/app/~~xxxx==/com.example.foo-yyyy==/split_config.arm64_v8a.apk
                   ^^^^^^^^^^^^^^^
```

For the version, prefer (in order):
1. A `# Version:` header line in the trace (Crashlytics-style export).
2. The version the user stated when sharing the trace.
3. The version shown next to the crash in Play Console — ask the user if missing.

Don't guess. Symbol files only resolve if their Build IDs match the crashing build exactly.

### 3. Fetch symbols from Codemagic

Three-step discovery (skip steps you don't need):

```bash
# (a) List visible apps. Read the JSON to pick the right `appName`,
#     then use that exact string for --app in step (b).
python3 scripts/codemagic_fetch_artifacts.py

# (b) List finished Android builds for the app, to confirm the version exists.
python3 scripts/codemagic_fetch_artifacts.py --app "Pixel Buddy"

# (c) Download both symbol zips for that version. Most-recent build wins on ties.
python3 scripts/codemagic_fetch_artifacts.py --app "Pixel Buddy" --build 1.2.3
```

`--app` accepts the Codemagic display name (case-insensitive exact match against `appName`) — that's the canonical selector and works on any machine. If you'd rather pass the Android `applicationId` (e.g. `com.chunkytofustudios.pixel_buddy`), install and authenticate the `gh` CLI (`gh auth login`); the script then resolves `applicationId` from the repo's `android/app/build.gradle{,.kts}`. **Don't install `gh` for this skill alone** — start by listing apps and matching by name.

The download is cached under `~/.cache/codemagic-fetch-artifacts/codemagic/<appId>/<buildId>/` — repeat invocations on the same build are instant.

Step (c)'s stdout is JSON — parse `.cacheDir` and `.files[].path` to feed the next step. Example:

```json
{
  "cacheDir": "/Users/you/.cache/codemagic-fetch-artifacts/codemagic/<appId>/<buildId>",
  "files": [
    { "name": "android_native_debug_symbols.zip", "path": "…/android_native_debug_symbols.zip", "size": 123456789, "cached": true },
    { "name": "PixelBuddy_42_artifacts.zip",       "path": "…/PixelBuddy_42_artifacts.zip",       "size": 12345678,  "cached": false }
  ]
}
```

If the app or version isn't found, the script exits non-zero with the available list — surface that to the user instead of looping.

### 4. Symbolize

```bash
bash scripts/symbolize_flutter_anr.sh \
  /tmp/play-stacktrace.log \
  ~/.cache/codemagic-fetch-artifacts/codemagic/<appId>/<buildId>/android_native_debug_symbols.zip \
  ~/.cache/codemagic-fetch-artifacts/codemagic/<appId>/<buildId>/<AppName>_<N>_artifacts.zip
```

Argument order doesn't matter — the script sniffs each input and classifies it as the trace, the native zip, or the Flutter symbols zip. Defaults the output to `<trace>.symbolized.txt` next to the input. Override with `-o`. Use `--json` for a machine-readable summary on stdout.

### 5. Read the symbolized output and debug

The output interleaves the original lines with resolved frames:

```
  #07  pc 0x00000000004bfb78  /data/app/.../split_config.arm64_v8a.apk (flutter::SurfaceDestroyed(_JNIEnv*, _jobject*, long)+…) (BuildId: d73e2148…)
    -> /Users/.../libflutter.so
flutter::SurfaceDestroyed(_JNIEnv*, _jobject*, long)
shell/platform/android/platform_view_android_jni_impl.cc:1234
```

Frames the script couldn't resolve get `[UNRESOLVED]`. The summary at the end reports `Frames` and `Unresolved` counts.

## Gotchas

- **Build IDs are the contract.** A symbol file matches a frame only if its `BuildId:` (from `llvm-readelf --notes`) equals the `BuildId:` in the trace line. Wrong version → no matches → every frame `[UNRESOLVED]`. The script's first warning when most frames fail is "wrong build artifacts (common)".
- **The version string must match the Codemagic build's `version` field exactly.** Codemagic stores e.g. `"2.3.1"`; a `v` prefix is tolerated, but appending the build number (`2.3.1+42`) is not. If unsure, run `codemagic_fetch_artifacts.py --app …` (no `--build`) to see the available versions.
- **ABI is detected from the trace by greps** for `arm64`, `armeabi`, `x86_64`, `x86`. The 99% case is `arm64-v8a`. If the trace genuinely lacks an ABI hint, the script defaults to `arm64-v8a`.
- **The Flutter symbols zip is named `<AppName>_<N>_artifacts.zip`** where `<N>` is the Codemagic build sequence (not the version). The fetch script picks it up via the regex `.+_\d+_artifacts\.zip`. If the Codemagic workflow renamed the artifact, update `FLUTTER_ARTIFACTS_RE` in `scripts/codemagic_fetch_artifacts.py`.
- **System library frames stay unresolved on purpose.** Frames in `libc.so`, `libart.so`, `com.google.android.gms`, `com.google.android.webview`, `system_server`, etc. aren't from your build — those PCs match Android system binaries no Codemagic artifact ships. Don't chase them; focus on frames pointing into `split_config.<abi>.apk` for *your* package.
- **Non-Codemagic builds will fail at step 3.** If the Codemagic workflow didn't run for the version that crashed (e.g. it was a local `flutter build appbundle` upload), the API simply has nothing — bail and tell the user.
- **The `--json` flag on `symbolize_flutter_anr.sh`** prints `{"frames", "unresolved", "abi", "output"}` to stdout with all status logs on stderr — use this when chaining the symbolizer into another script.

## Quick reference

```bash
# End-to-end, when you already know the display name + version:
export CODEMAGIC_API_TOKEN=...
python3 scripts/codemagic_fetch_artifacts.py --app "Pixel Buddy" --build 1.2.3 \
  | tee /tmp/cm.json
CACHE=$(jq -r .cacheDir /tmp/cm.json)
bash scripts/symbolize_flutter_anr.sh \
  /tmp/play-stacktrace.log \
  "$CACHE/android_native_debug_symbols.zip" \
  "$CACHE"/*_artifacts.zip
# → /tmp/play-stacktrace.symbolized.txt
```
