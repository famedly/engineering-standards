---
description: Rules for writing and organizing Patrol end-to-end tests in patrol_test/.
globs: patrol_test/**/*.dart
---

# Patrol Test Standards

## Directory Structure — Feature-Based

Tests are organized by **feature**, not by infrastructure (single-user vs multi-user). The directory answers "where is the test code?", tags answer "what should run?".

```
patrol_test/
├── auth/           # Login, logout, bootstrap
├── chat/           # Messages, reactions, replies, markdown, export
├── polls/          # Poll creation, voting, results, lifecycle
├── groups/         # Group creation, members, discover, archive
├── settings/       # Status, theme, devices, language
├── presence/       # Online/busy/offline indicators
├── feature_flags/  # Tests requiring custom well-known config
└── utils/          # Infrastructure (helpers, extensions, config)
```

| Rule | Rationale |
|---|---|
| Place tests in the directory matching their feature | Discoverability by domain |
| Use `feature_flags/` for any test that **verifies behavior driven by a well-known value** — whether enabled or disabled | Groups positive/negative pairs together |
| Never create `single_user/` or `multi_user/` directories | Infrastructure is expressed via tags, not directories |

---

## Tag System — Five Dimensions

All filtering uses [Patrol tags](https://patrol.leancode.co/documentation/other/patrol-tags). Tags are defined in `TestTags` and organized in five orthogonal dimensions:

| Dimension | Tags | Assigned by | Count per test |
|---|---|---|---|
| **Infrastructure** | `single_user`, `multi_user`, `feature_flag` | Developer | Exactly 1 |
| **Feature** | `auth`, `chat`, `polls`, `groups`, `settings`, `presence`, `applock`, `media` | Developer | Exactly 1 |
| **Layout** | `one_column`, `two_column`, `three_column` | Auto-injected | 1–3 |
| **Platform** | `web`, `mobile` | Auto-injected | Exactly 1 |
| **Priority** | `smoke`, `slow` | Developer | 0–1 |

Each test also gets a unique **identifier tag** (e.g. `create_poll`) for targeted execution.

### Tag rules

| Rule | Example |
|---|---|
| Every test **must** have exactly 1 infrastructure tag | `TestTags.singleUser` |
| Every test **must** have exactly 1 feature tag | `TestTags.polls` |
| Every test **must** have exactly 1 identifier tag | `'create_poll'` |
| Priority tags are optional | `TestTags.smoke` for critical-path tests |
| **Never** manually add layout or platform tags | They are injected by `adaptivePatrolTest` |
| Use `TestTags` constants, not raw strings, for dimension tags | `TestTags.singleUser` not `'single_user'` |
| Identifier tags use raw strings | `'my_specific_test'` |

---

## Test Scaffold

### Minimal test

```dart
import '../utils/patrol_web_helpers.dart';

void main() {
  adaptivePatrolTest(
    'descriptive test name',
    ($) async {
      final user = await TestSetup.createAccount('UserName');

      await startWebApp($);
      await $.initialLogin(username: user.localpart, password: user.password);

      // ... test logic and assertions ...

      await $.returnToHome();
    },
    tags: [TestTags.singleUser, TestTags.chat, 'test_identifier'],
  );
}
```

### With feature flag — positive/negative pair

Feature-flag tests verify behavior that depends on a well-known value. Always write both the positive case (flag on) and the negative case (flag off) as a pair in the same file. Both must use an **explicit** `WellKnownBuilder` — never rely on the default well-known for feature-flag assertions.

```dart
// ✅ Positive case — flag enabled
adaptivePatrolTest(
  'forced applock shows pin setup after login',
  ($) async {
    final user = await TestSetup.createAccount('ApplockUser');

    final wellKnown = WellKnownBuilder()..applockForced = true;
    await startWebApp($, wellKnown: wellKnown);
    await $.login(username: user.localpart, password: user.password);
    // ... assert pin setup appears ...
  },
  tags: [TestTags.featureFlag, TestTags.applock, 'applock_forced'],
);

// ✅ Negative case — flag disabled (explicit, not default)
adaptivePatrolTest(
  'non-forced applock can be skipped',
  ($) async {
    final user = await TestSetup.createAccount('NoApplockUser');

    final wellKnown = WellKnownBuilder()..applockForced = false;
    await startWebApp($, wellKnown: wellKnown);
    await $.loginAndResetAccount(username: user.localpart, password: user.password);
    // ... assert pin setup does not appear ...
  },
  tags: [TestTags.featureFlag, TestTags.applock, 'applock_not_forced'],
);
```

### With multi-user interaction

```dart
adaptivePatrolTest(
  'partner votes on poll',
  ($) async {
    final user = await TestSetup.createAccount('VoteUser');
    final partner = await TestSetup.createBackgroundUser('VotePartner');

    await startWebApp($);
    await $.initialLogin(username: user.localpart, password: user.password);
    // partner is disposed automatically in cleanup
  },
  tags: [TestTags.multiUser, TestTags.polls, 'poll_multi_vote'],
);
```

---

## Platform Restriction

Tests run on **both web and mobile** by default. Only set `platforms` when a test cannot run on a specific platform:

```dart
// Only mobile (biometrics, push, native app-lock)
platforms: {TestPlatform.mobile}

// Only web (browser-specific UI)
platforms: {TestPlatform.web}
```

When `_activePlatform` is not in `platforms`, the test is not registered at all.

| Rule | Rationale |
|---|---|
| Default is both platforms — do not set `platforms` unless restricting | Less boilerplate, tests run everywhere by default |
| Use `{TestPlatform.mobile}` for native-only features (biometrics, push) | These APIs don't exist in browsers |
| Use `{TestPlatform.web}` for browser-only features (service workers) | These APIs don't exist on native |

---

## Layout Restriction

Tests run for **all three layouts** by default. Only set `layouts` when a test is irrelevant for certain screen sizes:

```dart
// Only wide screens
layouts: {TestLayout.twoColumn, TestLayout.threeColumn}

// Only one specific layout
layouts: {TestLayout.twoColumn}
```

---

## Feature Flag Tests

A test is a **feature-flag test** when it verifies behavior that depends on a well-known configuration value — regardless of whether the flag is enabled or disabled. The question is: "Does this test assert something about a well-known-controlled feature?"

### Decision rule

| Question | Answer | Result |
|---|---|---|
| Does the test assert UI/behavior that changes based on a well-known flag? | Yes | `feature_flags/` + `TestTags.featureFlag` |
| Does the test use the app normally without caring about flags? | Yes | Feature directory + `TestTags.singleUser` or `TestTags.multiUser` |

### Rules

| Rule | Rationale |
|---|---|
| Feature-flag tests live in `feature_flags/`, tagged `TestTags.featureFlag` | Clear separation from functional tests |
| Write positive and negative cases as a **pair in the same file** | Easy to see both sides of the flag |
| **Always** set the well-known value explicitly via `WellKnownBuilder` | Never rely on the default well-known for flag assertions |
| Name the file after the feature being tested | `calls_test.dart`, `applock_test.dart`, `attachment_restriction_test.dart` |
| The feature tag reflects the domain area | `TestTags.groups` for calls in groups, `TestTags.applock` for app-lock |

### Default well-known

The default well-known (`_defaultWellKnownString` in `mock_client.dart`) sets `callsEnabled = false` and `encounterRooms = true`. Tests that use `startWebApp($)` without a `WellKnownBuilder` get these defaults.

**Non-feature-flag tests must not depend on specific default values.** If a test asserts "button X is not visible" and that is only true because of a default well-known flag, the test is actually a feature-flag test and belongs in `feature_flags/` with an explicit `WellKnownBuilder`.

### Example: calls enabled/disabled

```dart
// feature_flags/calls_test.dart

// ✅ Negative case — calls disabled in direct chat
adaptivePatrolTest(
  'calls disabled hides call button in direct chat',
  ($) async {
    final wellKnown = WellKnownBuilder()..callsEnabled = false;
    await startWebApp($, wellKnown: wellKnown);
    // ... assert call button is not visible ...
  },
  tags: [TestTags.featureFlag, TestTags.chat, 'calls_disabled'],
);

// ✅ Positive case — calls enabled in direct chat
adaptivePatrolTest(
  'calls enabled shows call button in direct chat',
  ($) async {
    final wellKnown = WellKnownBuilder()..callsEnabled = true;
    await startWebApp($, wellKnown: wellKnown);
    // ... assert call button is visible ...
  },
  tags: [TestTags.featureFlag, TestTags.chat, 'calls_enabled'],
);

// ✅ LiveKit group calls — separate flag for group call buttons
adaptivePatrolTest(
  'livekit group calls enabled shows call button in group',
  ($) async {
    final wellKnown = WellKnownBuilder()
      ..callsEnabled = true
      ..livekitCallsBaseUrl = 'https://livekit.example.com';
    await startWebApp($, wellKnown: wellKnown);
    // ... assert group call button is visible ...
  },
  tags: [TestTags.featureFlag, TestTags.groups, 'livekit_calls_enabled'],
);
```

---

## Test Isolation Rules

| Rule | Rationale |
|---|---|
| Each test creates its own accounts via `TestSetup.createAccount` | No shared state between tests |
| Never reuse accounts across tests | Prevents flaky inter-test dependencies |
| Always call `await $.returnToHome()` at the end | Consistent teardown |
| `startWebApp` registers `TestSetup.cleanup` as tearDown automatically | Accounts are deactivated, clients disposed |
| `AppLocalStorage` is cleared before each test | No state bleed |

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Test file | `*_test.dart` | `poll_test.dart` |
| Test description | Lowercase, descriptive phrase | `'create and interact with poll in group'` |
| Identifier tag | `snake_case`, unique across suite | `'create_poll'` |
| Account display names | Short PascalCase prefix | `'PollUser'`, `'PollPartner'` |
| Group/room names | UPPER CASE for easy identification | `'POLL GROUP NAME'` |
| Helper functions | Private, prefixed with `_` | `_createPrivateGroup(...)` |

---

## Imports

Always import the barrel file — never import individual utils:

```dart
// ✅ Correct
import '../utils/patrol_web_helpers.dart';

// ❌ Wrong — import individual files
import '../utils/test_setup.dart';
import '../utils/test_config.dart';
import '../utils/extensions/patrol_app_extension.dart';
```

---

## Widget Finder Priority

All widget finders must follow this priority order. Lower-priority finders are only acceptable when higher-priority alternatives are not available.

| Priority | Finder | When to use | Example |
|---|---|---|---|
| 1 (preferred) | `$(K.loginButton)` | Always, when the widget has a Key | `await $(K.sendButton).tap()` |
| 2 (acceptable) | `$(find.textContaining(...))` | Dynamic text that cannot have a Key | `await $.richText(message).tap()` |
| 3 (avoid) | `$('Login')` | Only for text that is never translated and has no Key | Avoid — add a Key instead |
| 4 (forbidden) | `$(TextField).at(2)` | Never — class + index is too fragile | Add keys to form fields |

### Rules

| Rule | Rationale |
|---|---|
| **Must** use `K.xxx` constants from `lib/shared/keys.dart` for Key-based finders | Single source of truth, autocomplete, no typos |
| **Must not** use `const Key('...')` directly in tests | Use `K.xxx` instead |
| **Must not** find widgets by class + index (`$(TextField).at(n)`) | Breaks when UI order changes |
| **Should** add a Key to the app widget when a string finder is needed | Keys survive i18n changes |
| **May** use `$.richText(text)` / `$.textContaining(text)` for dynamic content | Dynamic text cannot have static keys |

---

## Wait Strategies

Tests must not use hardcoded delays. Use reactive waiting instead.

| Allowed | Forbidden |
|---|---|
| `await $(widget).waitUntilVisible()` | `await Future.delayed(Duration(seconds: 5))` |
| `await $(widget).waitUntilVisible(timeout: Duration(seconds: 15))` | Fixed delays without polling |
| `await $.waitUntilGone(finder)` | `await Future.delayed(...)` as sole wait |
| `await $.isPresent(finder, timeout: ...)` | |
| `await $.pumpAndSettle()` after user actions | |

### When to use which

| Scenario | Pattern |
|---|---|
| Wait for a widget to appear | `await $(widget).waitUntilVisible()` |
| Wait for a widget to disappear (e.g. after delete) | `await $.waitUntilGone($.richText(deletedText))` |
| Wait for async data (e.g. server response) | `await $(expectedWidget).waitUntilVisible(timeout: Duration(seconds: 15))` |
| Check if a widget exists without failing | `await $.isPresent(finder, timeout: Duration(seconds: 5))` |
| After tapping a button / entering text | `await $.pumpAndSettle()` |

---

## Central Keys File — `lib/shared/keys.dart`

All test-relevant widget keys are defined in `lib/shared/keys.dart` and exported via the barrel. Both app code and test code reference the same constants.

### Rules

| Rule | Rationale |
|---|---|
| **Must** define new test-relevant keys in `lib/shared/keys.dart` | Single source of truth |
| **Must** use `K.xxx` in tests, never `const Key('...')` | Autocomplete, typo-proof |
| **Should** use `K.xxx` in app widget code | Ensures app and test use identical keys |
| **Must** use camelCase for field names | Dart convention |
| **Must** use static factory methods for dynamic keys | `K.pollAnswer(i)`, `K.appLocale('de')` |

### Adding a new Key

1. Add a `static const` or `static` factory to `lib/shared/keys.dart`
2. In the app widget, set `key: K.myNewKey`
3. In the test, use `$(K.myNewKey)`

---

## Shared Test Helpers

Common test actions are provided as extensions on `PatrolIntegrationTester`. Import the barrel to access them.

### Available helpers

| Helper | Extension | Description |
|---|---|---|
| `$.createPrivateGroup(name, partnerName: ...)` | `PatrolGroupExtension` | Creates a private group and returns to home |
| `$.createPublicGroup(name, partnerName: ..., isEncrypted: ...)` | `PatrolGroupExtension` | Creates a public group and returns to home |
| `$.sendMessage(text)` | `PatrolChatExtension` | Sends a message and waits for it to appear |
| `$.richText(text)` | `PatrolChatExtension` | Finds RichText containing the given string |
| `$.textContaining(text)` | `PatrolChatExtension` | Finds text containing the given string |
| `$.returnToHome()` | `PatrolNavigationExtension` | Navigates back to the room list |
| `$.navigateToChat(displayName)` | `PatrolNavigationExtension` | Opens a chat by display name |
| `$.logout()` | `PatrolNavigationExtension` | Logs out the current user |
| `$.initialLogin(username: ..., password: ...)` | `PatrolAppExtension` | Logs in and waits for home screen |
| `$.loginAndResetAccount(username: ..., password: ...)` | `PatrolAppExtension` | Logs in and resets encryption |
| `$.setupBootstrap(password: ...)` | `PatrolAppExtension` | Completes chat backup setup |
| `$.isPresent(finder, timeout: ...)` | `PatrolFinderExtension` | Checks if a widget exists without failing |
| `$.waitUntilGone(finder, timeout: ...)` | `PatrolFinderExtension` | Waits until a widget disappears |
| `$.maybeUppercase(text)` | `PatrolFinderExtension` | Finds text case-insensitively |

### Rules

| Rule | Rationale |
|---|---|
| **Must** use shared helpers instead of duplicating code | DRY, single maintenance point |
| **Must not** define `_createPrivateGroup` locally | Use `$.createPrivateGroup(...)` instead |
| **May** define file-local helpers for feature-specific actions | e.g. `_openPollDialog`, `_archiveRoom` |

---

## Anti-Patterns

```dart
// ❌ Manually adding layout or platform tags
tags: [TestTags.singleUser, TestTags.chat, TestTags.oneColumn, 'my_test']
// ✅ Layout/platform tags are auto-injected
tags: [TestTags.singleUser, TestTags.chat, 'my_test']

// ❌ Missing infrastructure tag
tags: [TestTags.chat, 'my_test']
// ✅ Always include exactly 1 infrastructure tag
tags: [TestTags.singleUser, TestTags.chat, 'my_test']

// ❌ Missing feature tag
tags: [TestTags.singleUser, 'my_test']
// ✅ Always include exactly 1 feature tag
tags: [TestTags.singleUser, TestTags.chat, 'my_test']

// ❌ Using raw strings for dimension tags
tags: ['single_user', 'chat', 'my_test']
// ✅ Use TestTags constants for dimensions, raw string for identifier
tags: [TestTags.singleUser, TestTags.chat, 'my_test']

// ❌ Putting a multi-user test in a single_user/ directory
// ✅ Put it in the feature directory (e.g. polls/) and tag with TestTags.multiUser

// ❌ Setting platforms when the test works on both
platforms: {TestPlatform.web, TestPlatform.mobile}  // This is already the default
// ✅ Omit platforms entirely — both is the default

// ❌ Reusing accounts between tests
// ✅ Each test calls TestSetup.createAccount with a unique name

// ❌ Importing individual util files
import '../utils/test_setup.dart';
// ✅ Import the barrel file
import '../utils/patrol_web_helpers.dart';

// ❌ Relying on default well-known for feature-flag assertions
await startWebApp($);  // default has callsEnabled = false
expect($(callButton), findsNothing);  // implicitly depends on default!
// ✅ Set the flag explicitly — makes the test self-documenting
final wellKnown = WellKnownBuilder()..callsEnabled = false;
await startWebApp($, wellKnown: wellKnown);
expect($(callButton), findsNothing);

// ❌ Feature-flag test in a feature directory with singleUser tag
// groups/groups_rooms_test.dart
tags: [TestTags.singleUser, TestTags.groups, 'disabled_calls']
// ✅ Feature-flag test in feature_flags/ with featureFlag tag
// feature_flags/calls_test.dart
tags: [TestTags.featureFlag, TestTags.groups, 'calls_disabled']

// ❌ Only testing one side of a feature flag
// ✅ Write both enabled and disabled cases as a pair in the same file

// ❌ Using const Key('...') directly in tests
await $(const Key('SettingsButton')).tap();
// ✅ Use K.xxx from the central keys file
await $(K.settingsButton).tap();

// ❌ Hardcoded delay
await Future<void>.delayed(const Duration(seconds: 5));
await $.pumpAndSettle();
// ✅ Reactive waiting
await $(expectedWidget).waitUntilVisible(timeout: const Duration(seconds: 15));

// ❌ Waiting for disappearance with delay
await Future<void>.delayed(const Duration(seconds: 2));
expect($.richText(deleted), findsNothing);
// ✅ Poll until gone
await $.waitUntilGone($.richText(deleted));

// ❌ Finding widgets by class + index
await $(TextField).at(0).enterText('text');
// ✅ Use a Key
await $(K.usernameField).enterText('text');

// ❌ Duplicating _createPrivateGroup in each test file
Future<void> _createPrivateGroup(...) { ... }
// ✅ Use the shared extension
await $.createPrivateGroup('GROUP NAME', partnerName: 'Partner');
```

---

## Running Tests

Use tag expressions for all filtering:

```bash
# Quick CI: smoke tests, one-column
patrol test --tags '(smoke && one_column)'

# All poll tests
patrol test --tags polls

# Single-user tests, no three-column
patrol test --tags '(single_user && !three_column)'

# Single test by identifier
patrol test --tags create_poll

# Via run script
./scripts/run-patrol-test.sh -T '(polls && one_column)' -s
```
