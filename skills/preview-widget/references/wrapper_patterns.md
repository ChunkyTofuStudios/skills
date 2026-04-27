# Wrapper patterns

The `wrapper:` parameter on `@Preview` is the load-bearing part of using widget previews in any non-trivial app. Below are recipes for the global ancestors a widget might need.

The wrapper signature is always:

```dart
Widget previewWrapper(Widget child)
```

It must be a **public top-level function** (no closures, no private prefix). Multiple wrappers can compose by wrapping each other.

## Skeleton

```dart
// lib/preview_wrapper.dart
import 'package:flutter/material.dart';

Widget previewWrapper(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    home: Scaffold(body: Center(child: child)),
  );
}
```

This bare wrapper is enough for stateless widgets that only read `Theme.of(context)`. Real apps need more.

## BLoC / `flutter_bloc`

If widgets read `BlocBuilder<FooCubit, FooState>` or `context.watch<FooCubit>`, the cubit must be in the tree.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/theme/cubit/theme_cubit.dart';
import 'src/ux/cubit/ux_cubit.dart';

Widget previewWrapper(Widget child) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<UxCubit>(create: (_) => UxCubit(deviceType: DeviceType.mobile)),
    ],
    child: BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, theme) => MaterialApp(
        theme: theme.getMaterialTheme(isTablet: false),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}
```

**Common mistake:** putting `theme:` on the `MaterialApp` but not the cubit in the tree. A widget that reads `BlocBuilder<ThemeCubit>` directly will throw `ProviderNotFoundException` regardless of what the `MaterialApp` says.

## Riverpod / `flutter_riverpod`

Wrap in a `ProviderScope` and `MaterialApp`. Override providers that need stub state:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/providers/theme_provider.dart';

Widget previewWrapper(Widget child) {
  return ProviderScope(
    overrides: [
      // Pin theme to a known value for previews.
      themeModeProvider.overrideWith((_) => ThemeMode.light),
    ],
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
```

For widgets that read `ref.watch(asyncFooProvider)`, override the provider with `AsyncValue.data(stubFoo)` so the preview renders the loaded state without hitting a real backend.

## `provider` package

Same idea, different syntax:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Widget previewWrapper(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
    ],
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
```

## GoRouter

Most widgets don't need a full router, but anything that calls `GoRouter.of(context)` or uses `context.push(...)` for navigation does. Use a tiny shell:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Widget previewWrapper(Widget child) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: child)),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    theme: ThemeData.light(useMaterial3: true),
  );
}
```

## Localizations / `AppLocalizations`

If the widget calls `AppLocalizations.of(context)!.someString`, register the delegates:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'gen/app_localizations.dart';

Widget previewWrapper(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData.light(useMaterial3: true),
    home: Scaffold(body: Center(child: child)),
  );
}
```

## `MediaQuery` overrides (tablet sizing, dark text scale, RTL)

Use `MediaQuery` *inside* the wrapper to dogfood specific device characteristics in addition to the `size:` parameter on `@Preview`:

```dart
Widget previewWrapper(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(1024, 1366),
        textScaler: TextScaler.linear(1.5),
        platformBrightness: Brightness.dark,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );
}
```

## Fonts (`google_fonts`, asset fonts)

Asset fonts declared in `pubspec.yaml` work without setup — Flutter loads them automatically. `google_fonts` fetches at runtime; in the previewer this means the first paint may show fallback fonts before the network fetch resolves. To pre-load:

```dart
import 'package:google_fonts/google_fonts.dart';

Widget previewWrapper(Widget child) {
  // Triggers an async preload; the `MaterialApp` below won't wait, but
  // hot-restart will pick up the cached font on the next paint.
  GoogleFonts.config.allowRuntimeFetching = true;
  GoogleFonts.poppins();
  return MaterialApp(/* ... */);
}
```

If fonts must be ready before the first frame, switch to bundled font assets in `pubspec.yaml`.

## Composing wrappers

When you have multiple optional concerns, compose by nesting:

```dart
Widget previewWrapper(Widget child) =>
    _withProviders(_withMediaQuery(_withMaterialApp(child)));
```

Keeping each helper a top-level public function is required — see the const-callable constraint in `references/preview_annotations.md`.

## Stubbing data sources

Real cubits often instantiate repositories that hit the network or disk. Two patterns:

1. **Constructor injection.** If `FooCubit(repo: FooRepo())`, wrap with `BlocProvider(create: (_) => FooCubit(repo: _StubFooRepo()))` where `_StubFooRepo` returns canned data.
2. **`emit` directly.** For state-only previews, emit a fake state right away:

   ```dart
   BlocProvider<FooCubit>(create: (_) => FooCubit()..emit(FooLoaded(stubData))),
   ```

The previewer is for *visual* iteration — anything that needs network round-trips or persisted state is a sign you're previewing the wrong layer (try a screen-level integration test instead).
