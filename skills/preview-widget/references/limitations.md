# Limitations of the Flutter Widget Previewer

Source of truth: [docs.flutter.dev/tools/widget-previewer](https://docs.flutter.dev/tools/widget-previewer). The previewer is **experimental** as of Flutter 3.35; APIs and CLI flags may shift between releases.

## Hard restrictions

### No `dart:io`, `dart:ffi`, or native plugins

The previewer renders in Chrome, so anything that can't run in a browser fails:

- `File`, `Directory`, `Process`, `Platform.isAndroid`, etc.
- FFI (`dart:ffi`) calls.
- Method-channel-based plugins (camera, biometrics, contacts, file picker, in-app purchase, native widgets like Google Maps, etc.).

Any of those throws at the moment the preview tries to render.

**Workaround:** conditional imports.

```dart
// foo_io.dart, foo_web.dart, foo_stub.dart
export 'foo_stub.dart'
    if (dart.library.io) 'foo_io.dart'
    if (dart.library.html) 'foo_web.dart';
```

The widget previewer picks the `dart.library.html` variant — make that one return stub data.

### Asset paths must be package-prefixed

`Image.asset('assets/foo.png')` works in the real app but breaks in the previewer. Switch to:

```dart
Image.asset('packages/<your_package_name>/assets/foo.png')
```

The package-prefixed form works in both contexts (the in-app build resolves it to the same physical file).

### Annotation values must be const

All arguments to `@Preview(...)` and `@MultiPreview` subclass fields must be `const`-evaluable:

- ✅ `Size(360, 80)`, `Brightness.dark`, string literals, top-level function tearoffs
- ❌ Closures, lambdas, `const`-incompatible constructors, anything reading instance fields

### Callbacks must be public

`wrapper:`, `theme:`, and `localizations:` parameters require **public top-level (or static) function tearoffs**. A function whose name starts with `_` is private and rejected.

```dart
// ✅
Widget previewWrapper(Widget child) => Scaffold(body: child);

// ❌ — private name, won't be accepted as a const tearoff.
Widget _previewWrapper(Widget child) => Scaffold(body: child);
```

### No required arguments on annotated constructors

```dart
// ✅
@Preview(name: 'OK')
const MyWidget.preview({super.key});

// ❌ — `value` has no default and isn't optional.
@Preview(name: 'No good')
const MyWidget.preview({super.key, required this.value});
```

The previewer can't synthesize a value for `value`. Either give it a default or wrap in a top-level function:

```dart
@Preview(name: 'OK via wrapper')
Widget myWidgetPreview() => const MyWidget.preview(value: 42);
```

## Soft limitations (workarounds available)

### Unconstrained widgets get auto-sized

Without `size:`, the previewer constrains the widget to roughly half the canvas. For a button that's tiny visually, pass `size: Size(360, 80)`. For full-screen widgets, pass the device size you want (`Size(360, 800)` for phone, `Size(1024, 1366)` for tablet).

### First paint is slow

Flutter web bootstraps to JS/Skia on first preview load. 5–10s is typical, longer on slow disks. Subsequent paints are fast because the canvas is already warm. The default `--wait 10000` for `screenshot_preview.sh` covers most setups; bump to `--wait 20000` if first-shot screenshots are blank.

### Hot-restart is automatic but not instant

Edits to widget code trigger an automatic hot-restart, but it's not synchronous — give the previewer 1–2s to settle before screenshotting. Edits to the wrapper itself are slower (rebuilds the whole canvas); 3–5s is safer there.

### One project per server

The previewer's CLI server only knows about the project it was started in. For Pub workspaces, run from the workspace root. Multi-project IDE flows are tracked in [flutter/flutter#173550](https://github.com/flutter/flutter/issues/173550).

### Whole-page screenshots only

The previewer renders all annotated previews on one page. There's no per-preview URL or DOM selector that's officially supported. `screenshot_preview.sh` captures the whole page — if you only want one preview visible, comment out the others temporarily, or rely on `group:` to keep related variants adjacent.

### Experimental status

Flutter 3.35 marks widget-preview as experimental on stable. Expect occasional breakage on Flutter upgrades — particularly to:

- the `flutter widget-preview start` CLI flags,
- the URL format printed by the server,
- the page DOM (if you build per-preview screenshot tooling later).

If `start_preview.sh` stops capturing the URL after a Flutter upgrade, run `flutter widget-preview start` manually and inspect its output, then update the regex in the script.
