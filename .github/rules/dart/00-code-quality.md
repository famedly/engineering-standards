# Dart & Flutter Code Quality Standards

## General Dart

- Follow the official [Dart style guide](https://dart.dev/effective-dart/style)
- Format code with `dart format` – the CI will reject unformatted code

## Dart Libraries

- Use Dart extensions to extend class functionality instead of wrapper classes
- Describe public classes, methods, and attributes using `///` dartdoc comments – see [Effective Dart: Documentation](https://dart.dev/effective-dart/documentation)
- Use `Object.hash(a, b)` instead of manual XOR (`a.hashCode ^ b.hashCode`) for hash code calculation

## Flutter Apps

- **Separation of concerns** – NEVER mix UI and business logic in the same class. Use controller and view classes.
- **Widget classes over functions** – NEVER write functions to create widgets. Always write widget classes.
- **Localization** – NEVER insert unlocalized strings
- **Caching futures** – when caching a `Future` result across rebuilds, always use **Riverpod** instead of raw `FutureBuilder`
- **InheritedWidget access** – if `InheritedWidget.of(context)` is called multiple times, call it once at the start of the `build` method and store it in a `final` variable. Use the lowercase name of the widget as the variable name:

```dart
final l10n = L10n.of(context);
```
