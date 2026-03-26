---
description: Five-layer Feature-First Clean Architecture with MVP+MVVM presentation layer. Defines the role, rules, and responsibilities of each layer.
globs: lib/**/*.dart, test/**/*.dart
alwaysApply: true
---

# Project Architecture — Five-Layer Feature-First Clean Architecture

## Layer Overview

```
┌───────────────────────────────────────────────────────────────────┐
│                        RIVERPOD PROVIDERS                         │
│            (Dependency Injection + State Management)              │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. IMMUTABLE WIDGETS — StatelessWidget, no Riverpod, no logic    │
│         ▲ called by                                               │
│  2. PRESENTERS        — ConsumerWidget, wires providers to views  │
│         ▲ ref.watch / ref.read                                    │
│  3. VIEWMODELS        — Notifier, emits immutable state           │
│         ▲ ref.read(useCaseProvider)                               │
│  4. DOMAIN            — UseCases + sealed Result types (pure Dart)│
│         ▲                                                         │
│  5. SERVICES          — Cross-feature infrastructure in lib/core/ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

The Domain layer (4) is **optional**. Simple features may skip it and have ViewModels call Services directly. Extract a UseCase when a ViewModel accumulates complex business logic, multiple error types, or 2+ async operations.

---

## Allowed & Forbidden Widget Base Classes

Every widget in the project **must** use one of the allowed base classes listed below. `StatefulWidget` and `ConsumerStatefulWidget` are **globally forbidden** — use hooks or pass lifecycle objects from the Presenter instead.

### Allowed Base Classes

| Base Class | Layer | Riverpod Access | Hooks |
|---|---|---|---|
| `StatelessWidget` | Immutable Widgets — no providers, no local state, no hooks | No | No |
| `ConsumerWidget` | Presenters that need `ref.watch`/`ref.read` but no lifecycle objects | Yes | No |
| `HookConsumerWidget` | Presenters that need `ref` AND disposable controllers (`TextEditingController`, `FocusNode`, `AnimationController`) | Yes | Yes |
| `HookWidget` | Shared widgets that need hooks but no `ref` (rare — never for feature Immutable Widgets) | No | Yes |

### Forbidden Base Classes — Do Not Use

| Forbidden Class | Use Instead |
|---|---|
| `StatefulWidget` | `HookWidget` (for hooks without `ref`) or `StatelessWidget` (pass lifecycle objects from Presenter) |
| `ConsumerStatefulWidget` | `HookConsumerWidget` (hooks replace `initState`/`dispose`) |
| `StatefulHookConsumerWidget` | `HookConsumerWidget` (should never need both hooks and `State` lifecycle) |

### Why No StatefulWidget?

- `setState` scatters state across the widget tree, making it invisible to Riverpod and hard to test.
- `initState`/`dispose` lifecycle is fragile — forgetting `dispose` causes leaks. Hooks handle this automatically.
- Every `StatefulWidget` can be expressed as `HookWidget` or `HookConsumerWidget` using `useTextEditingController()`, `useAnimationController()`, `useFocusNode()`, etc.

### Migration Cheat Sheet

| StatefulWidget pattern | Hook replacement |
|---|---|
| `late final _controller = TextEditingController()` + `dispose()` | `useTextEditingController()` |
| `late final _focusNode = FocusNode()` + `dispose()` | `useFocusNode()` |
| `late final _animController = AnimationController(vsync: this)` | `useAnimationController(duration: ...)` |
| `late final _scrollController = ScrollController()` + `dispose()` | `useScrollController()` |
| `initState()` for one-time setup | `useEffect(() { ... return dispose; }, [])` |
| `didUpdateWidget()` for prop changes | `useEffect(() { ... }, [dep])` or `useValueChanged()` |
| `setState(() { _flag = true })` for local UI toggle | `useState(false)` |

---

## 1. Immutable Widgets (View Layer)

Immutable Widgets are **pure `StatelessWidget`s** with no dependencies on Riverpod, Flutter Hooks, or any business logic. All data and callbacks arrive via constructor parameters. They are the sole place where UI is rendered.

| Rule | Rationale |
|------|-----------|
| **Must** extend `StatelessWidget` | No state, no lifecycle — fully portable and testable |
| **Must not** use Flutter Hooks (`use*`) | Hooks are Presenter responsibility |
| **Must not** import Riverpod | Zero coupling to app infrastructure |
| **Must not** contain business logic | Logic lives in ViewModels and Services |
| **Must not** instantiate Presenters directly in `build()` | Pass a `builder` parameter up the tree instead |
| **May** use `FutureBuilder`, `StreamBuilder`, `ValueListenableBuilder` | Reactive primitives passed in as constructor args |

### Builder Pattern for Nested Presenters

When an Immutable Widget needs to embed another Presenter (e.g. a user name that requires a provider), it **must not** instantiate the Presenter directly. Instead, define a `builder` parameter and let the parent Presenter fill it.

```dart
/// ✅ Immutable Widget delegates Presenter construction to the parent
class UserNameView extends StatelessWidget {
  final User user;
  final Widget Function(BuildContext context, User user) userNameBuilder;

  const UserNameView({
    super.key,
    required this.user,
    required this.userNameBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: userNameBuilder(context, user)),
    );
  }
}

/// ✅ Presenter fills the builder — Riverpod stays out of the View
class UserNamePresenter extends ConsumerWidget {
  const UserNamePresenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return UserNameView(
      user: user,
      userNameBuilder: (context, u) => UserNameDetailPresenter(user: u),
    );
  }
}
```

```dart
/// ✅ Full example — all data and callbacks from constructor
class PasswordLoginView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String? passwordErrorText;
  final VoidCallback onSubmit;

  const PasswordLoginView({
    super.key,
    required this.formKey,
    required this.isLoading,
    required this.usernameController,
    required this.passwordController,
    this.passwordErrorText,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: formKey,
        child: ListView(
          children: [
            TextFormField(controller: usernameController),
            FamedlyFilledButton(
              label: L10n.of(context)!.login,
              onPressed: isLoading ? null : onSubmit,
              isLoading: isLoading,
            ),
          ],
        ),
      ),
    );
  }
}
```

**File pattern:** `*_view.dart` in `presentation/widgets/`

---

## 2. Presenters

Presenters are **ConsumerWidgets** (or **HookConsumerWidgets** when hooks are needed) that wire Riverpod state to Immutable Widgets. They are the only layer that may access Riverpod providers.

| Rule | Rationale |
|------|-----------|
| **Must** be `ConsumerWidget` or `HookConsumerWidget` | Needs `ref` for provider access |
| **Must** return exactly one Immutable Widget at the end of `build()` | No own UI rendering |
| **Must not** have own state (`setState`) | All state lives in ViewModels |
| **Must not** render UI directly | Delegate to Immutable Widget |
| **May** use hooks for lifecycle objects (`TextEditingController`, `FocusNode`) | Hooks manage dispose automatically |
| **May** contain UI-flow coordination (dialogs, navigation, snackbars) | Side-effects live here, not in ViewModels |
| **May** fill `builder` parameters of Immutable Widgets with nested Presenters | See builder pattern in Section 1 |

```dart
final class RoomSettingsPresenter extends ConsumerWidget {
  final String? id;
  const RoomSettingsPresenter({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerArgs = (roomId: id!);
    final state = ref.watch(roomSettingsViewModelProvider(providerArgs));

    void onEditNameTap() => context.push('...');

    Future<void> onEncryptionTap() async {
      final confirmed = await famedlyShowOkCancelAlertDialog(...);
      if (confirmed != FamedlyOkCancelResult.ok) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => ref
            .read(roomSettingsViewModelProvider(providerArgs).notifier)
            .enableEncryption(),
      );
    }

    return RoomSettingsView(
      state: state,
      onEditNameTap: onEditNameTap,
      onEncryptionTap: onEncryptionTap,
    );
  }
}
```

**File pattern:** `*_presenter.dart` in `presentation/presenters/`

Presenters may conditionally render different Immutable Widgets (e.g. loading, error, content), but the Immutable Widget itself always stays a pure `StatelessWidget`.

---

## 3. ViewModels

ViewModels are **Riverpod Notifiers** that emit immutable state. They hold all UI state and expose methods that the Presenter calls in response to user actions.

| Rule | Rationale |
|------|-----------|
| **Must** extend `Notifier`, `AsyncNotifier`, or `StreamNotifier` | Riverpod 3 unified base classes |
| **Must** emit immutable state | Prevents race conditions |
| **Must** use `.autoDispose` (on the provider) by default | State resets when leaving the screen |
| **Must** declare `dependencies` explicitly | Transparent provider graph |
| **Must** check `ref.mounted` after every `await` | Prevents disposed-state errors |
| **Must not** import Flutter | Pure Dart — unit-testable without widget setup |
| **Must not** trigger UI side-effects (dialogs, navigation) | That is the Presenter's job |
| **May** call UseCases or Services directly | Domain layer is optional |

### State Modeling

**Sealed classes** for state machines (discrete states like loading/success/error):

```dart
sealed class LoginState {
  const LoginState();
  const factory LoginState.initial() = LoginInitial;
  const factory LoginState.loading() = LoginAuthenticating;
  const factory LoginState.success({required String userId}) = LoginSuccess;
  const factory LoginState.failure({required LoginErrorType errorType}) = LoginFailure;
}
```

**Final classes with `copyWith`** for view-state with many fields:

```dart
final class RoomDetailState {
  final bool showArchiveBanner;
  final Event? replyTo;
  final Event? editingEvent;
  const RoomDetailState({...});
  RoomDetailState copyWith({...}) => RoomDetailState(...);
}
```

**Guideline:** Simple counter-like state may use primitive types. As soon as loading/error/success semantics appear, use a sealed class.

**File patterns:** `*_view_model.dart` in `presentation/view_models/`, `*_state.dart` in `presentation/states/`

---

## 4. Domain Layer (UseCases + Results) — Optional

UseCases are **pure Dart classes** with an `execute()` method. They perform exactly one business operation and return a **sealed Result type**. No exceptions escape a UseCase.

| When to extract a UseCase | When to skip |
|---------------------------|-------------|
| Multiple error types to handle | Simple state toggle (mute/unmute) |
| Complex business logic (validation, mapping) | Single SDK call with simple try/catch |
| Logic reused by multiple Controllers | Trivial CRUD |
| 2+ async operations chained together | — |

```dart
final class LoginUseCase {
  final TiMessengerClient _client;
  LoginUseCase(this._client);

  Future<LoginResult> execute({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.login(username, password);
      return LoginResult.success(userId: response.userId);
    } on MatrixException catch (e) {
      return LoginResult.failure(errorType: _mapError(e));
    } catch (e, s) {
      ErrorReporter.reportError(e, s);
      return LoginResult.failure(errorType: LoginErrorType.unknown);
    }
  }
}

sealed class LoginResult {
  const factory LoginResult.success({required String userId}) = LoginSuccess;
  const factory LoginResult.failure({required LoginErrorType errorType}) = LoginFailure;
}
```

| Rule | Rationale |
|------|-----------|
| **Must** be pure Dart (no Flutter, no Riverpod imports) | Unit-testable without widget setup |
| **Must** return a sealed Result type | Compiler-enforced exhaustive handling |
| **Must not** throw exceptions | Errors are values, not control flow |
| **Injected** via Riverpod `Provider` | Consistent DI |

**File patterns:** `*_usecase.dart` in `domain/usecases/`, `*_result.dart` in `domain/models/`

---

## 5. Services (Core Infrastructure)

Services are **cross-feature infrastructure modules** under `lib/core/`. They provide functionality shared by multiple features.

### Service Types

| Type | May import Flutter? | May hold `Ref`? | May show UI (dialogs, navigation)? | Example |
|---|---|---|---|---|
| **Domain Service** | No (pure Dart) | No | No | `BootstrapService` |
| **Infrastructure Service** | Yes (platform APIs) | Via Provider only | No | `WakelockService`, `BackgroundPushService` |

**There is no "UI Service" type.** Services must **not** trigger dialogs, navigation, or snackbars. If a service currently shows UI (e.g. `showFutureLoadingDialog`), that UI logic belongs in the Presenter — the service should return a result that the Presenter acts on.

### Service Rules

| Rule | Rationale |
|------|-----------|
| **Must** be a `final class` | Closed for inheritance |
| **Must** receive dependencies via constructor | Explicit, testable DI |
| **Must not** trigger UI side-effects | Services have no `BuildContext` |
| **Must not** hold `Ref` directly | Use constructor injection from the Provider |
| **May** be a singleton only when required by platform constraints | e.g. `VoipService` (WebRTC lifecycle) |
| **Domain Services must** be pure Dart | No Flutter, no Riverpod imports |

```dart
/// ✅ Domain Service — pure Dart, dependencies via constructor
final class BootstrapService {
  final TiMessengerClient _client;
  BootstrapService(this._client);

  Future<Bootstrap> startBootstrap({required BootstrapConfig config}) async { ... }
}

/// ✅ Infrastructure Service — may use platform APIs, no UI
final class WakelockService {
  Future<void> enable() async { ... }
  Future<void> disable() async { ... }
}
```

### Service Provider Co-location

A service's Riverpod provider is defined **in the same file** as the service class, or in a `*_service_provider.dart` file directly next to it.

```dart
/// Provider defined in the same file as the service
final bootstrapServiceProvider = Provider<BootstrapService>(
  (ref) => BootstrapService(ref.watch(clientProvider)),
  dependencies: [clientProvider],
);
```

**File pattern:** `*_service.dart` in `lib/core/<module>/`

### Module Organization

```
lib/core/
├── auth/           # OIDC, session, login/logout
├── client/         # Matrix client provider
├── encryption/     # Key backup, bootstrap
├── push/           # Push notifications
├── router/         # GoRouter config
├── room/           # Room state (cross-feature mediator)
├── state/          # Global app state (cross-feature mediator)
├── voip/           # VoIP/calls
└── ...
```

Each core module may have its own `domain/`, `extensions/`, and sub-modules as needed.

### Cross-Feature Mediators

When state is shared by 2+ features, it lives in a dedicated core module — **features must never import each other**.

| Module | Purpose |
|--------|---------|
| `core/room/` | Room state used by chat, settings, room list |
| `core/state/` | Global app state (unread badge, nav) |
| `core/hba/` | eHBA card state used by eHBA and insuree features |

**Decision rule:**
- Used by 2+ features → `core/<domain>/`
- Used by 1 feature only → inside that feature
- Global app state → `core/state/`

---

## 6. Providers (Riverpod Wiring)

Providers are the glue that connects all layers. They define how classes are instantiated and how state flows through the app. Because they are so pervasive, consistent conventions are critical.

### Provider File Naming

| Pattern | When to Use | Example |
|---|---|---|
| `*_provider.dart` (singular) | Single provider or small group of related providers for one concept | `client_provider.dart`, `router_provider.dart` |
| `*_providers.dart` (plural) | Collection of related providers for a module | `room_granular_providers.dart`, `startup_lifecycle_providers.dart` |
| `*_usecases_providers.dart` | Bundled UseCase providers for a feature's domain layer | `auth_usecases_providers.dart` |

### Provider File Placement

Providers live **next to what they provide**. Never create a separate `providers/` directory.

| What the provider creates | Provider file location |
|---|---|
| UseCase | `domain/usecases/*_usecases_providers.dart` (bundled per feature) |
| ViewModel | Inline in `*_view_model.dart` (co-located with the Notifier) |
| Service | Inline in `*_service.dart` or in `*_service_provider.dart` next to it |
| Cross-feature state | `core/<module>/*_provider.dart` |
| Granular selectors | `core/<module>/*_providers.dart` |

```
# ✅ Correct: providers next to what they provide
lib/core/room/
├── room_actions_service.dart         # Contains roomActionsServiceProvider
├── room_granular_providers.dart      # Contains select()-based providers
├── room_snapshot_controller.dart     # Contains roomSnapshotProvider
└── ...

lib/features/auth/domain/usecases/
├── login_usecase.dart
├── check_auth_status_usecase.dart
└── auth_usecases_providers.dart      # Bundles all UseCase providers

# ❌ Wrong: separate providers/ directory
lib/core/room/providers/             # Don't do this
```

### Inline vs. Separate File

- **Inline** (provider in the same file as the class): Default for simple providers with 1-2 dependencies.
- **Separate file**: When the provider has complex setup logic, or when bundling multiple providers (e.g. `*_usecases_providers.dart`).

### Granular Providers (Performance Pattern)

For frequently-updated state (e.g. room data), create granular providers using `select()` to minimize widget rebuilds:

```dart
/// Only rebuilds when displayName changes — not when unread count changes.
final roomNameProvider = Provider.autoDispose.family<String, String>((ref, roomId) {
  return ref.watch(
    roomSnapshotProvider(roomId).select((async) => async.value?.displayName ?? roomId),
  );
}, dependencies: [roomSnapshotProvider]);
```

Use granular providers when:
- The source provider updates frequently (e.g. on every sync)
- Multiple widgets watch the same source but need different fields
- Performance profiling shows unnecessary rebuilds

### Provider Rules

| Rule | Rationale |
|------|-----------|
| **Must** declare `dependencies` explicitly | Transparent provider graph |
| **Must** use `.autoDispose` by default | Prevents memory leaks |
| **Must** co-locate with the class they provide | Discoverable, not scattered |
| **Must not** contain business logic | Logic belongs in Controllers, UseCases, or Services |

---

## Directory Structure

```
lib/
├── main.dart
├── app/                              # App shell (no business logic)
│   ├── layouts/
│   ├── navigation/
│   ├── splash/
│   ├── app_lock/
│   └── famedly_app.dart
├── core/                             # Cross-feature infrastructure
│   ├── auth/
│   ├── client/
│   ├── router/
│   └── ...
├── features/                         # Business domains
│   ├── authentication/
│   │   ├── domain/
│   │   │   ├── usecases/             # LoginUseCase, etc.
│   │   │   └── models/               # LoginResult, etc.
│   │   ├── presentation/
│   │   │   ├── view_models/          # LoginViewModel
│   │   │   ├── states/               # LoginState (sealed)
│   │   │   ├── presenters/           # PasswordLoginPresenter
│   │   │   └── widgets/              # PasswordLoginView (Immutable Widget)
│   │   └── index.dart
│   ├── chat/
│   │   ├── timeline/
│   │   ├── composer/
│   │   └── index.dart
│   └── ...
└── shared/                           # Reusable UI components
    └── widgets/
```

**Feature-first, not page-first.** Each feature owns its routes, its domain, and its presentation. Sub-features (e.g. `chat/timeline/`, `chat/composer/`) nest naturally.

### Rules for `shared/`

`shared/` contains **reusable UI components** that are used across multiple features (buttons, dialogs, avatars, HTML rendering, etc.).

| Rule | Rationale |
|------|-----------|
| **Must** be `StatelessWidget` or `HookWidget` | No Riverpod dependency — usable everywhere |
| **Must not** import Riverpod | Shared widgets must not depend on app-specific providers |
| **Must not** contain business logic | Pure UI building blocks |
| **May** use `Theme.of(context)`, `L10n.of(context)` | Standard Flutter context lookups |
| **May** accept callbacks and data via constructor | Same principle as Views |

### Rules for `app/`

`app/` is the **app shell** — top-level scaffolding, layouts, splash screen, and app-lock overlay. It is not a feature and contains no business logic.

| Rule | Rationale |
|------|-----------|
| **Must** use `ConsumerWidget` or `HookConsumerWidget` for provider-aware widgets | Standard Presenter rules apply |
| **Must not** contain business logic | Logic belongs in `core/` or `features/` |
| **May** contain layout shells, navigation chrome, splash, app-lock | Structural UI only |

### Rules for `core/`

Core modules follow the same layer conventions as features. If a core module has its own widgets or ViewModels, they follow the same Presenter/View/ViewModel rules.

| Rule | Rationale |
|------|-----------|
| Core ViewModels **must** be Riverpod Notifiers | Same as feature ViewModels |
| Core widgets **must** be `StatelessWidget` or `HookWidget` | No Riverpod in reusable widgets |
| Services follow the Service rules from Section 5 | Consistency |

---

## Naming Vocabulary

| Name | File Pattern | Layer | Description |
|------|-------------|-------|-------------|
| **View** | `*_view.dart` | Immutable Widget | `StatelessWidget`, no Riverpod, no hooks. Feature-specific UI that receives a state object. |
| **Presenter** | `*_presenter.dart` | Presenter | `ConsumerWidget`/`HookConsumerWidget`, wires providers to Immutable Widgets |
| **ViewModel** | `*_view_model.dart` | ViewModel | Riverpod Notifier, emits immutable state |
| **State** | `*_state.dart` | — | Immutable data class for UI state |
| **UseCase** | `*_usecase.dart` | — | Pure Dart business operation |
| **Result** | `*_result.dart` | — | Sealed return type of a UseCase |
| **Service** | `*_service.dart` | Service | Cross-feature infrastructure (see Section 5) |
| **Widget** | `*_widget.dart` | — | Generic reusable UI component (receives primitive data, not a state object) |
| **Provider** | `*_provider.dart` / `*_providers.dart` | — | Riverpod provider definitions (see Section 6) |
| **Handler** | `*_handler.dart` | — | Event or error handler |
| **Extension** | `*_extension.dart` | — | Dart extension methods |
| **Utils** | `*_utils.dart` | — | Pure top-level functions (no classes) |
| **Routes** | `*_routes.dart` | — | GoRouter route definitions for a feature |

### `*_view.dart` vs. `*_widget.dart`

Both are `StatelessWidget` and contain no business logic. The difference:

| | `*_view.dart` (View) | `*_widget.dart` (Widget) |
|---|---|---|
| **Purpose** | Feature-specific screen content | Generic, reusable UI building block |
| **Receives** | A typed state object + callbacks | Primitive data (strings, bools, callbacks) |
| **Reused across features?** | No — tied to one Presenter | Yes — used by multiple features |
| **Location** | `features/<name>/presentation/widgets/` | `shared/widgets/` or `features/<name>/presentation/widgets/` |
| **Example** | `LoginView(state: loginState, onSubmit: ...)` | `CopyButton(text: '...', onCopied: ...)` |

**Rule of thumb:** If it receives a feature-specific state class → `*_view.dart`. If it is a standalone UI primitive → `*_widget.dart`.

### File Naming Matrix — Suffix to Directory

Every file must use the correct suffix for its directory. Files with the wrong suffix must be renamed.

| Directory | Required Suffix(es) | Exceptions |
|---|---|---|
| `presentation/widgets/` | `*_view.dart`, `*_widget.dart` | `index.dart` |
| `presentation/presenters/` | `*_presenter.dart` | `index.dart` |
| `presentation/view_models/` | `*_view_model.dart` | `index.dart` |
| `presentation/states/` | `*_state.dart` | `index.dart` |
| `domain/usecases/` | `*_usecase.dart`, `*_usecases_providers.dart` | `index.dart` |
| `domain/models/` | `*_result.dart`, other domain types | `index.dart` |
| `shared/widgets/` | No strict suffix — but prefer `*_widget.dart` for clarity | Subdirectories are allowed |

**What goes where in `presentation/presenters/`:**

`presenters/` only contains Presenters (`*_presenter.dart`). Do **not** place Immutable Widgets, shared widgets, or helper files in `presenters/`. If a Presenter needs a dedicated View, put the View in `presentation/widgets/`. If a Presenter needs sub-Presenters (e.g. tabbed navigation), use subdirectories:

```
# ✅ Correct
presentation/presenters/
├── settings_presenter.dart
└── security/
    └── privacy_presenter.dart

# ❌ Wrong — Views and widgets mixed into presenters/
presentation/presenters/
├── settings_presenter.dart
├── settings_view.dart              # Belongs in widgets/
└── widgets/                        # No widgets/ inside presenters/
    └── settings_tile.dart
```

### Forbidden Terms

Do **not** use these as class names or suffixes: `Manager`, `Helper`, `Notifier` (as class name — OK as Riverpod base class), `Entity`, `Model` (as suffix), `Repository`, `Interactor`, `Bloc`, `Cubit`, `Controller`, `Screen`, `Store`, `Facade`.

---

## Anti-Patterns

### Widget Base Classes

```dart
// ❌ StatefulWidget — globally forbidden
class MyWidget extends StatefulWidget { ... }
class _MyWidgetState extends State<MyWidget> {
  late final _controller = TextEditingController();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}

// ✅ Use HookConsumerWidget in the Presenter instead
class MyPresenter extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    // pass controller down to the Immutable Widget
    return MyView(controller: controller);
  }
}

// ❌ ConsumerStatefulWidget — globally forbidden
class MyPresenter extends ConsumerStatefulWidget { ... }

// ✅ Use HookConsumerWidget
class MyPresenter extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final state = ref.watch(myViewModelProvider);
    return MyView(state: state, controller: controller);
  }
}

// ❌ Hooks in an Immutable Widget
class MyView extends HookWidget {
  Widget build(BuildContext context) {
    final isExpanded = useState(false); // Not allowed in Immutable Widgets!
  }
}

// ✅ Pass local UI state as a constructor parameter, or move to Presenter
class MyView extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  const MyView({super.key, required this.isExpanded, required this.onToggle});
}

// ❌ setState anywhere in the codebase
setState(() { _isExpanded = !_isExpanded; });

// ✅ Use useState hook in the Presenter for local UI toggles
final isExpanded = useState(false);
isExpanded.value = !isExpanded.value;
```

### Layer Violations

```dart
// ❌ Immutable Widget imports Riverpod
class MyView extends ConsumerWidget { ... }
// ✅ Immutable Widget is pure StatelessWidget
class MyView extends StatelessWidget { ... }

// ❌ Immutable Widget uses hooks
class MyView extends HookWidget {
  Widget build(BuildContext context) {
    final controller = useTextEditingController(); // Not allowed in Immutable Widgets!
  }
}
// ✅ Hooks belong in the Presenter — pass the controller as a constructor parameter
class MyView extends StatelessWidget {
  final TextEditingController controller;
  const MyView({super.key, required this.controller});
}

// ❌ Immutable Widget instantiates a Presenter directly
class MyView extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(children: [
      Text('Hello'),
      UserNamePresenter(), // Breaks the layer boundary!
    ]);
  }
}
// ✅ Define a builder parameter — let the parent Presenter fill it
class MyView extends StatelessWidget {
  final Widget Function(BuildContext) userNameBuilder;
  const MyView({super.key, required this.userNameBuilder});
  Widget build(BuildContext context) {
    return Column(children: [Text('Hello'), userNameBuilder(context)]);
  }
}

// ❌ Presenter renders its own UI instead of delegating to an Immutable Widget
class MyPresenter extends ConsumerWidget {
  Widget build(context, ref) {
    return Scaffold(body: Column(children: [/* complex UI tree */]));
  }
}
// ✅ Presenter delegates to Immutable Widget
class MyPresenter extends ConsumerWidget {
  Widget build(context, ref) {
    final state = ref.watch(myViewModelProvider);
    return MyView(state: state, onTap: () => ...);
  }
}

// ❌ ViewModel triggers navigation or dialogs
void submit() async {
  navigator.push(...); // Side-effect in ViewModel!
}
// ✅ ViewModel returns result, Presenter handles side-effects
// In ViewModel: return bool or state change
// In Presenter: if (success) context.push(...)

// ❌ Service shows dialogs
class RoomService {
  Future<Room?> createRoom(BuildContext context) async {
    return showFutureLoadingDialog(context: context, future: () => ...);
  }
}
// ✅ Service returns result, Presenter shows dialog
class RoomService {
  Future<CreateRoomResult> createRoom() async { ... }
}
// In Presenter: showFutureLoadingDialog(future: () => service.createRoom());

// ❌ Feature imports another feature
import '../settings/view_models/settings_view_model.dart';
// ✅ Shared state via core mediator or provider
final prefs = ref.watch(userPreferencesProvider);

// ❌ UseCase throws exception
Future<String> execute() => _client.doThing(); // Raw exception escapes!
// ✅ UseCase returns sealed Result
Future<MyResult> execute() async {
  try { ... return MyResult.success(...); }
  catch (e, s) { return MyResult.failure(...); }
}

// ❌ Shared widget imports Riverpod
class MySharedWidget extends ConsumerWidget { ... }
// ✅ Shared widget is StatelessWidget or HookWidget
class MySharedWidget extends StatelessWidget { ... }
```

### File Naming

```dart
// ❌ Wrong suffix for directory
presentation/widgets/discover_content.dart           // Should be *_view.dart or *_widget.dart
presentation/presenters/room_detail_view.dart        // Views don't belong in presenters/
presentation/presenters/widgets/member_item.dart     // No widgets/ inside presenters/
presentation/view_models/login_controller.dart       // Should be *_view_model.dart

// ✅ Correct
presentation/widgets/discover_content_view.dart
presentation/widgets/room_detail_view.dart
presentation/widgets/member_item_widget.dart
presentation/presenters/login_presenter.dart
presentation/view_models/login_view_model.dart
```

### Provider Placement

```dart
// ❌ Separate providers/ directory
lib/core/voip/providers/voip_service_provider.dart

// ✅ Provider next to what it provides
lib/core/voip/services/voip_service.dart          // Contains or is next to voipServiceProvider

// ❌ Generic provider file name
features/auth/domain/usecases/usecase_providers.dart

// ✅ Feature-prefixed provider file name
features/auth/domain/usecases/auth_usecases_providers.dart
```
