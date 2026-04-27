# `@Preview` and `@MultiPreview` reference

Quick reference for the annotation API. Source of truth: [api.flutter.dev/flutter/widget_previews](https://api.flutter.dev/flutter/widget_previews/widget_previews-library.html).

## Import

```dart
import 'package:flutter/widget_previews.dart';
```

`widget_previews` is part of the Flutter SDK from 3.35 onward — no `pubspec.yaml` change needed.

## `@Preview` constructor

```dart
const Preview({
  String group = 'Default',
  String? name,
  Size? size,
  double? textScaleFactor,
  WidgetWrapper? wrapper,
  PreviewTheme? theme,
  Brightness? brightness,
  PreviewLocalizations? localizations,
});
```

| Param | Purpose |
|---|---|
| `name` | Display label rendered above the preview tile. Use a clear, unique name per variant (e.g. `'MyButton — disabled'`). |
| `group` | Bucket for related previews. Defaults to `'Default'`. Tiles in the same group are grouped visually in the previewer UI. |
| `size` | Forces a specific viewport size for the previewed widget. Without it, unconstrained widgets get auto-sized to ~half the canvas. |
| `textScaleFactor` | Multiplies font sizes — use `1.5` or `2.0` to dogfood accessibility settings. |
| `wrapper` | `Widget Function(Widget child)` that wraps the previewed widget in any global ancestors it needs (BLoC providers, `MaterialApp`, `Scaffold`, etc.). Must be a top-level public function. |
| `theme` | `PreviewThemeData Function()` returning Material/Cupertino theme data. Lighter alternative to `wrapper` when all you need is theming. |
| `brightness` | `Brightness.light` or `Brightness.dark`. Sets the initial brightness toggle state. |
| `localizations` | `PreviewLocalizations Function()` providing localization delegates. |

**Constraints (enforced at compile time):**

1. All values passed to `@Preview(...)` must be **const-evaluable**.
2. `wrapper`, `theme`, and `localizations` must be **public top-level (or static) function tearoffs** — no closures, no private (`_`-prefixed) functions.
3. The annotation target must be one of:
   - a top-level function returning `Widget` or `WidgetBuilder`,
   - a public widget constructor or factory with **no required arguments**,
   - a public static method on a class.

## Valid annotation targets

```dart
// Top-level function returning Widget.
@Preview(name: 'Top-level preview')
Widget preview() => const Text('Foo');

// Top-level function returning WidgetBuilder (gets BuildContext).
@Preview(name: 'Builder preview')
WidgetBuilder builderPreview() {
  return (BuildContext context) {
    return Text('Theme is ${Theme.of(context).brightness}');
  };
}

// Public constructor with no required args.
class MyWidget extends StatelessWidget {
  @Preview(name: 'Constructor preview')
  const MyWidget.preview({super.key});

  // Factory works too.
  @Preview(name: 'Factory preview')
  factory MyWidget.factoryPreview() => const MyWidget.preview();

  // Public static method.
  @Preview(name: 'Static method preview')
  static Widget previewStatic() => const Text('Static');
}
```

## Multiple `@Preview` on the same target

Stack annotations to render the same widget under multiple configurations:

```dart
@Preview(group: 'Brightness', name: 'Light', brightness: Brightness.light)
@Preview(group: 'Brightness', name: 'Dark',  brightness: Brightness.dark)
Widget buttonPreview() => const ButtonShowcase();
```

## `@MultiPreview` for reusable matrices

A `MultiPreview` subclass bundles a list of `Preview`s into one annotation. Useful when many widgets in your codebase want the same set of variants.

```dart
final class BrightnessPreview extends MultiPreview {
  const BrightnessPreview();

  @override
  final List<Preview> previews = const <Preview>[
    Preview(name: 'Light', brightness: Brightness.light),
    Preview(name: 'Dark',  brightness: Brightness.dark),
  ];
}

@BrightnessPreview()
Widget buttonPreview() => const ButtonShowcase();
```

**Subclass requirements:**

1. `final class` modifier (no further subclassing).
2. `const` constructor.
3. Override `previews` as a `final List<Preview>`, initialized to a `const` literal.
4. All values inside the list must be const-evaluable; callbacks must be public top-level (or static).

## Custom `Preview` subclasses

Extend `Preview` directly when you want a reusable annotation that bakes in defaults (theme, wrapper, size). Override `transform()` to mutate every emitted preview:

```dart
final class TransformativePreview extends Preview {
  const TransformativePreview({
    super.name,
    super.group,
    super.size,
    super.textScaleFactor,
    super.wrapper,
    super.brightness,
    super.localizations,
  });

  static PreviewThemeData _themeBuilder() {
    return PreviewThemeData(
      materialLight: ThemeData.light(),
      materialDark: ThemeData.dark(),
    );
  }

  @override
  Preview transform() {
    final original = super.transform();
    final builder = original.toBuilder()
      ..name = 'Transformed — ${original.name}'
      ..theme = _themeBuilder;
    return builder.toPreview();
  }
}
```

## When to use which

| Goal | Use |
|---|---|
| One-off preview of a widget | `@Preview(name: …, wrapper: previewWrapper)` |
| Same matrix (light/dark/tablet) across many widgets | `MultiPreview` subclass |
| Inject a default `wrapper:` or `theme:` for the whole codebase | Custom `Preview` subclass with `transform()` |
| Per-widget override of just one parameter | Stack multiple `@Preview` annotations |
