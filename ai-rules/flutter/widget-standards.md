---
description: Shared UI widget standards — which widgets to use, what to avoid
globs: lib/**/*.dart
alwaysApply: false
---

# Shared Widget Standards

Use the widgets in `lib/shared/widgets/` for consistent UI. **Do NOT** create feature-local copies.

## Buttons

Use `lib/shared/widgets/buttons/famedly_buttons.dart`:

| Need | Widget |
|------|--------|
| Primary action (filled) | `FamedlyFilledButton` |
| Secondary action (outlined) | `FamedlyOutlinedButton` |
| Destructive action | `FamedlyErrorButton` or `FamedlyOutlinedButton(isDestructive: true)` |
| Text-only / cancel | `FamedlyTextButton` |
| Custom colored | `FamedlyFatColoredButton` |
| Small / dense | `FamedlyCompactButton` |
| Vertical icon + label | `ProfileScaffoldButton` |

**Avoid:** Creating new `ElevatedButton`, `OutlinedButton`, `TextButton` with custom styles. Extend the Famedly button system instead.

## Settings / List Items

- Use `SettingsTile` for icon + title + optional trailing menu items.
- Pass `foregroundColor` to tint icon and text together.
- Feature-specific tiles with complex layouts (avatars, badges, popups) may use `ListTile` directly.

## Banners

- Use `DefaultBanner` for icon + title + trailing layout.
- Feature banners with avatars or complex subtitles may use custom implementations.

## Avatars

- Always use or wrap the shared `Avatar` widget from `lib/shared/widgets/avatar.dart`.
- Do **not** create thin wrapper classes that only pass size parameters — inline the `Avatar` call.

## QR Scanner (Verification)

- Use `QrScannerBody` from `lib/shared/widgets/encryption/qr_scanner_body.dart` with callbacks.
- Do **not** create feature-local QR scanner duplicates.

## Dialogs

- Use `showFutureLoadingDialog`, `famedlyShowOkAlertDialog`, `famedlyShowOkCancelAlertDialog` from `lib/shared/utils/famedly_dialogs.dart`.
- Use `showBottomSheetMenu` for action menus.

## Anti-Patterns

```dart
// ❌ Feature-local button with custom ElevatedButton styling
class MyCustomButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: primary, elevation: 0),
      // ...
    );
  }
}

// ✅ Use Famedly button system
FamedlyFilledButton(label: l10n.submit, onPressed: onSubmit)
```

```dart
// ❌ Thin avatar wrapper that only passes size
class _MyAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Avatar(url, size: 48);
}

// ✅ Inline the Avatar call
Avatar(url, size: 48)
```
