---
description: Guidelines for adding, consuming, and documenting feature flags.
globs: lib/core/config/feature_flag*.dart, lib/**/feature_flag*.dart
---

# Feature Flags Guidelines

This rule covers how to add new feature flags, consume them in widgets and controllers, and maintain the feature flag system.

## Overview

Feature flags control functionality across the app and can be:
- **Server-controlled**: Configured via well-known server configuration
- **Hardcoded defaults**: Fixed values in the enum (for development/internal flags)
- **Locally overridden**: Developer overrides for testing (persisted in SharedPreferences)

**Resolution order:** Local Override > Server Config > Enum Default

Platform restrictions are handled automatically via `FeaturePlatform` enum (`all` vs `mobileOnly`).

---

## 1. Adding a New Feature Flag

### Step-by-Step Checklist

1. **Add enum entry** in `lib/core/config/feature_flag.dart`:
   ```dart
   /// Brief description of what this flag controls.
   ///
   /// Detailed explanation of when/why this flag is used.
   /// 
   /// Controlled by server well-known configuration (`features.x.y.enabled`).
   /// Defaults to `true`/`false` if not configured.
   myNewFeatureEnabled(
     defaultValue: false,
     platform: FeaturePlatform.all, // or FeaturePlatform.mobileOnly
   ),
   ```

2. **Add server mapping** in `FeatureFlagController._mapServerFeatures()`:
   ```dart
   // myNewFeatureEnabled: features.myNewFeature.enabled (default: false)
   if (features.myNewFeature?.enabled != null) {
     serverValues[FeatureFlag.myNewFeatureEnabled] = features.myNewFeature!.enabled;
   }
   ```

3. **Add doc comment** at the enum value:
   - What the flag does
   - Who controls it (server/hardcoded)
   - Which feature is affected
   - Platform restrictions (if any)

### Naming Conventions

- Use **camelCase** for flag names
- Use descriptive names that indicate what they control
- Suffix conventions:
  - `*Enabled` - Feature is enabled/disabled
  - `*Forced` - Feature is forced (user cannot disable)
  - `*Suggested` - Feature is suggested to users
- Examples: `callsEnabled`, `appLockForced`, `appLockBiometricsSuggested`

### Required Documentation

**Every new flag MUST have a `///` doc comment** that includes:

- **What it does**: Brief description of the feature controlled
- **Who controls it**: Server well-known path OR "Hardcoded default value"
- **Default behavior**: What happens when not configured
- **Platform restrictions**: If `mobileOnly`, explain why

Example:
```dart
/// Whether calls (VoIP) are enabled for this organization.
///
/// Controlled by server well-known configuration (`features.calls.enabled`).
/// Defaults to `true` if not configured.
callsEnabled(
  defaultValue: true,
  platform: FeaturePlatform.all,
),
```

---

## 2. Adding a New Config Value

Non-boolean configuration values (URLs, IDs, objects) belong in `FeatureConfig`, not in the `FeatureFlag` enum.

### Steps

1. **Add field** to `FeatureConfig` class in `lib/core/config/feature_config.dart`:
   ```dart
   /// Description of what this config value represents.
   final String? myNewConfigValue;
   ```

2. **Add to constructor** and `copyWith()` method

3. **Add mapping** in `FeatureConfig.fromServerFeatures()`:
   ```dart
   myNewConfigValue: features.myNewFeature?.baseUrl,
   ```

4. **Update controller** if needed (usually automatic via `fromServerFeatures`)

### When to Use FeatureConfig vs FeatureFlag

| Type | Use |
|------|-----|
| `FeatureFlag` | Boolean toggles (enabled/disabled) |
| `FeatureConfig` | URLs, IDs, objects, strings, complex config |

Examples:
- ✅ `FeatureFlag.callsEnabled` - Boolean toggle
- ✅ `FeatureConfig.livekitJwtServiceUrl` - URL string
- ✅ `FeatureConfig.timVzd` - Complex object
- ❌ `FeatureFlag.livekitJwtServiceUrl` - Wrong! URLs belong in FeatureConfig

---

## 3. Consuming Feature Flags

### In Widgets/Controllers

**Always use `ref.watch(isFeatureEnabledProvider(FeatureFlag.x))`:**

```dart
// ✅ CORRECT: Watch flag in widget
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsEnabled = ref.watch(
      isFeatureEnabledProvider(FeatureFlag.callsEnabled),
    );
    
    if (!callsEnabled) {
      return const SizedBox.shrink();
    }
    
    return CallButton();
  }
}
```

### For Config Values

**Use `ref.watch(featureConfigProvider)`:**

```dart
// ✅ CORRECT: Watch config value
final config = ref.watch(featureConfigProvider);
final supportUrl = config.supportUrl;

if (supportUrl != null) {
  return HelpButton(url: supportUrl);
}
```

### Selective Rebuilds

Use `.select()` to minimize rebuilds:

```dart
// ✅ GOOD: Only rebuilds when callsEnabled changes
final callsEnabled = ref.watch(
  isFeatureEnabledProvider(FeatureFlag.callsEnabled).select((v) => v),
);

// ✅ GOOD: Only rebuilds when supportUrl changes
final supportUrl = ref.watch(
  featureConfigProvider.select((config) => config.supportUrl),
);
```

### In Services (without WidgetRef)

If you have a `ProviderContainer` (e.g., in a service):

```dart
// ✅ CORRECT: Read from container
final state = container.read(featureFlagControllerProvider);
final callsEnabled = state.isEnabled(FeatureFlag.callsEnabled);
```

### Platform Checks

**DO NOT** add `if (kIsWeb)` guards in consumers. Platform restrictions are handled automatically via `FeaturePlatform`:

```dart
// ❌ WRONG: Manual platform check
if (kIsWeb) {
  return const SizedBox.shrink();
}
final flag = ref.watch(isFeatureEnabledProvider(FeatureFlag.mobileOnlyFlag));

// ✅ CORRECT: Platform handled automatically
final flag = ref.watch(isFeatureEnabledProvider(FeatureFlag.mobileOnlyFlag));
// Returns false automatically on web if platform is mobileOnly
```

---

## 4. Anti-Patterns

### ❌ Forbidden: Static Access

```dart
// ❌ FORBIDDEN: Old static access (removed)
ChatConfigs.features?.callsEnabled
ChatConfigs.callsEnabled
```

**Reason:** Static access bypasses Riverpod reactivity and local overrides.

### ❌ Forbidden: Hardcoded Booleans

```dart
// ❌ BAD: Hardcoded boolean for feature control
if (true) { // Should be a feature flag!
  showNewFeature();
}

// ✅ GOOD: Use feature flag
final newFeatureEnabled = ref.watch(
  isFeatureEnabledProvider(FeatureFlag.newFeatureEnabled),
);
if (newFeatureEnabled) {
  showNewFeature();
}
```

### ❌ Forbidden: Platform Checks in Consumers

```dart
// ❌ BAD: Manual platform check
if (kIsWeb) {
  return const SizedBox.shrink();
}
final flag = ref.watch(isFeatureEnabledProvider(FeatureFlag.mobileOnlyFlag));

// ✅ GOOD: Platform handled in enum
final flag = ref.watch(isFeatureEnabledProvider(FeatureFlag.mobileOnlyFlag));
// Automatically returns false on web
```

### ❌ Forbidden: Flags Without Documentation

```dart
// ❌ BAD: No doc comment
myNewFlag(
  defaultValue: false,
  platform: FeaturePlatform.all,
),

// ✅ GOOD: Documented flag
/// Whether the new feature is enabled.
///
/// Controlled by server well-known configuration (`features.newFeature.enabled`).
/// Defaults to `false` if not configured.
myNewFlag(
  defaultValue: false,
  platform: FeaturePlatform.all,
),
```

### ❌ Forbidden: Reading in Build Without Watching

```dart
// ❌ BAD: Won't rebuild when flag changes
Widget build(context, ref) {
  final flag = ref.read(isFeatureEnabledProvider(FeatureFlag.x)); // BUG!
}

// ✅ GOOD: Watch for reactivity
Widget build(context, ref) {
  final flag = ref.watch(isFeatureEnabledProvider(FeatureFlag.x));
}
```

---

## 5. Testing

### Unit Tests for FeatureFlagState

Test the 3-layer resolution logic:

```dart
test('isEnabled resolves Local Override > Server > Default', () {
  final state = FeatureFlagState(
    serverValues: {FeatureFlag.callsEnabled: false},
    localOverrides: {FeatureFlag.callsEnabled: true},
  );
  
  // Local override wins
  expect(state.isEnabled(FeatureFlag.callsEnabled), true);
});

test('isEnabled falls back to server value when no override', () {
  final state = FeatureFlagState(
    serverValues: {FeatureFlag.callsEnabled: false},
  );
  
  expect(state.isEnabled(FeatureFlag.callsEnabled), false);
});

test('isEnabled falls back to enum default when no server value', () {
  final state = const FeatureFlagState();
  
  expect(
    state.isEnabled(FeatureFlag.callsEnabled),
    FeatureFlag.callsEnabled.defaultValue,
  );
});
```

### Unit Tests for FeatureFlagController

Test server mapping, overrides, and persistence:

```dart
test('updateFromServer maps server features correctly', () {
  final controller = FeatureFlagController();
  final features = ServerFhirFeatures(
    calls: Calls(enabled: false),
  );
  
  controller.updateFromServer(features);
  
  expect(
    controller.state.isEnabled(FeatureFlag.callsEnabled),
    false,
  );
});

test('setOverride persists and takes precedence', () async {
  final controller = FeatureFlagController();
  await controller.setOverride(FeatureFlag.callsEnabled, false);
  
  expect(controller.state.hasOverride(FeatureFlag.callsEnabled), true);
  expect(controller.state.isEnabled(FeatureFlag.callsEnabled), false);
});
```

### Widget Tests

Use provider overrides instead of mocking:

```dart
testWidgets('Widget respects feature flag', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFeatureEnabledProvider(FeatureFlag.callsEnabled)
            .overrideWith((ref) => false),
      ],
      child: MyWidget(),
    ),
  );
  
  expect(find.byType(CallButton), findsNothing);
});
```

### Coverage Requirements

New flags must be covered in:
- `FeatureFlagState.isEnabled()` tests (default, server, override)
- `FeatureFlagController._mapServerFeatures()` tests
- Widget tests for consumers (if applicable)

---

## 6. Quick Reference

### Adding a Flag

```
1. Add to FeatureFlag enum with defaultValue + platform + /// doc
2. Map in FeatureFlagController._mapServerFeatures()
3. Add test case in feature_flag_state_test.dart
```

### Consuming a Flag

```dart
// In widgets/controllers
ref.watch(isFeatureEnabledProvider(FeatureFlag.myFlag))

// In services (with ProviderContainer)
container.read(featureFlagControllerProvider).isEnabled(FeatureFlag.myFlag)
```

### Consuming a Config Value

```dart
final config = ref.watch(featureConfigProvider);
final value = config.myConfigValue;
```

### Forbidden Patterns

```dart
ChatConfigs.features?.x        // ❌ Removed
ChatConfigs.callsEnabled       // ❌ Removed
if (kIsWeb) { /* flag logic */ } // ❌ Use FeaturePlatform instead
```

---

## Related Files

- `lib/core/config/feature_flag.dart` - Enum definitions
- `lib/core/config/feature_flag_state.dart` - State class with resolution logic
- `lib/core/config/feature_flag_controller.dart` - Riverpod controller
- `lib/core/config/feature_config.dart` - Non-boolean config values
- `lib/features/app_settings/presentation/pages/developer/widgets/feature_flag_overrides.dart` - Dev override UI
