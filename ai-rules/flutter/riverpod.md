---
description: Riverpod 3 usage patterns — provider types, ViewModel patterns, State classes, and ref rules.
globs: lib/**/*.dart, test/**/*.dart
alwaysApply: false
---

# Riverpod 3 — Usage Patterns

> We use **Riverpod 3**. Key breaking changes from v2:
> - `AutoDisposeNotifier`, `FamilyNotifier`, `AutoDisposeFamilyNotifier` are **removed**.
> - Use `Notifier` / `AsyncNotifier` / `StreamNotifier` as the **single base class**.
> - Auto-dispose is controlled by the **provider** (`.autoDispose`), not the notifier class.
> - `Ref` subclasses (`ProviderRef`, etc.) are **removed** — use `Ref` directly.

---

## Provider Types

| Provider Type | Use Case |
|---|---|
| `Provider` / `Provider.autoDispose` | Dependency injection (UseCases, Services) |
| `NotifierProvider` / `.autoDispose` | UI state with synchronous updates |
| `AsyncNotifierProvider` / `.autoDispose` | UI state with async initial load |
| `StreamNotifierProvider` / `.autoDispose` | Reactive data from streams |
| `FutureProvider` | Simple one-shot async fetch |

> **Legacy — avoid:** `StateProvider`, `StateNotifier`, `StateNotifierProvider`, `ChangeNotifier`, `ChangeNotifierProvider`. Import from `legacy.dart` if still used.

---

## Riverpod 3 Behaviors

| Behavior | Default | How to Override |
|---|---|---|
| **Auto retry** | Providers auto-retry on failure with exponential backoff | `retry: (count, error) => null` on provider or `ProviderScope` |
| **Pause when hidden** | Providers not visible to the user are paused | Wrap consumers in `TickerMode(enabled: true, ...)` |
| **Update filtering** | All providers use `==` to filter updates | Override `updateShouldNotify` on Notifier |
| **Error wrapping** | Failures rethrown as `ProviderException` | Catch `ProviderException` and inspect `.exception` |

---

## ViewModel Pattern

ViewModels are Riverpod Notifiers that emit immutable state. They are the `M` in the MVP+MVVM architecture (see `architecture.mdc`).

```dart
final loginViewModelProvider = NotifierProvider.autoDispose<LoginViewModel, LoginState>(
  LoginViewModel.new,
  dependencies: [clientProvider, loginUseCaseProvider],
);

// Riverpod 3: always extend `Notifier`, never `AutoDisposeNotifier` (removed).
// `.autoDispose` on the PROVIDER controls disposal.
final class LoginViewModel extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState.initial();

  Future<bool> submit({required String username, required String password}) async {
    state = const LoginState.loading();

    final result = await ref.read(loginUseCaseProvider).execute(
      username: username,
      password: password,
    );

    // Always check mounted after every await
    if (!ref.mounted) return false;

    state = switch (result) {
      LoginSuccess(:final message) => LoginState.success(message: message),
      LoginFailure(:final error) => LoginState.failure(error: error),
    };

    return result is LoginSuccess;
  }
}
```

### Family Provider Pattern (Riverpod 3)

```dart
// FamilyNotifier is removed. Use Notifier with a constructor argument.
final roomViewModelProvider = NotifierProvider.autoDispose
    .family<RoomViewModel, RoomState, String>(
      RoomViewModel.new,
      dependencies: [clientProvider],
    );

final class RoomViewModel extends Notifier<RoomState> {
  RoomViewModel(this.roomId);
  final String roomId;

  @override
  RoomState build() => const RoomState.loading();
}
```

---

## State Classes

### Sealed Classes — for state machines (discrete loading/success/error states)

```dart
@immutable
sealed class LoginState {
  const LoginState();

  const factory LoginState.initial() = LoginInitial;
  const factory LoginState.loading() = LoginAuthenticating;
  const factory LoginState.success({required String userId}) = LoginSuccess;
  const factory LoginState.failure({required LoginErrorType errorType}) = LoginFailure;
}

final class LoginInitial extends LoginState { const LoginInitial(); }
final class LoginAuthenticating extends LoginState { const LoginAuthenticating(); }
final class LoginSuccess extends LoginState {
  final String userId;
  const LoginSuccess({required this.userId});
}
final class LoginFailure extends LoginState {
  final LoginErrorType errorType;
  const LoginFailure({required this.errorType});
}
```

### Final Classes with `copyWith` — for view-state with many fields

```dart
@immutable
final class ComposerState {
  final String text;
  final bool isTyping;
  final Event? replyTo;

  const ComposerState({this.text = '', this.isTyping = false, this.replyTo});

  ComposerState copyWith({String? text, bool? isTyping, Opt<Event?>? replyTo}) {
    return ComposerState(
      text: text ?? this.text,
      isTyping: isTyping ?? this.isTyping,
      replyTo: replyTo != null ? replyTo.value : this.replyTo,
    );
  }
}
```

**Guideline:** Use a sealed class as soon as loading/error/success semantics appear. For simple state with many fields and no discrete variants, use a final class with `copyWith`.

---

## ref Rules

```dart
// ref.watch — triggers rebuild when provider changes. Use in build().
final state = ref.watch(loginViewModelProvider);

// ref.read — does NOT trigger rebuild. Use in callbacks only.
onPressed: () => ref.read(loginViewModelProvider.notifier).submit(...)

// ref.listen — side-effect on change. Use for dialogs/navigation from Presenter.
ref.listen(loginViewModelProvider, (_, next) {
  if (next case LoginSuccess()) context.push('/home');
});

// .select() — only rebuild when a specific field changes
final isLoading = ref.watch(loginViewModelProvider.select((s) => s is LoginAuthenticating));
```

### Rules

- Always declare `dependencies` explicitly on every provider.
- Use `.autoDispose` by default — state resets when leaving the screen.
- Check `ref.mounted` after **every** `await` in a ViewModel.
- Wrap fire-and-forget async calls in `unawaited()` (import `dart:async`).
- Never call `ref.watch` inside a callback or after an `await`.

---

## Anti-Patterns

```dart
// ❌ Riverpod 2 base classes (removed in Riverpod 3)
class MyViewModel extends AutoDisposeNotifier<MyState> { }
class MyViewModel extends FamilyNotifier<MyState, String> { }
class MyViewModel extends AutoDisposeFamilyNotifier<MyState, String> { }

// ✅ Riverpod 3: unified Notifier base class
class MyViewModel extends Notifier<MyState> { }
final myProvider = NotifierProvider.autoDispose<MyViewModel, MyState>(...);
```

```dart
// ❌ ref.read in build() — won't rebuild when state changes
Widget build(context, ref) {
  final state = ref.read(myProvider); // BUG
}

// ✅ ref.watch in build()
Widget build(context, ref) {
  final state = ref.watch(myProvider);
}
```

```dart
// ❌ State modification after async without mounted check
Future<void> doAction() async {
  final result = await fetchData();
  state = result; // Widget may be disposed!
}

// ✅ Check mounted after every await
Future<void> doAction() async {
  final result = await fetchData();
  if (!ref.mounted) return;
  state = result;
}
```

```dart
// ❌ Discarded Future without unawaited()
@override
MyState build() {
  _loadData(); // Discarded Future lint!
  return const MyState.loading();
}

// ✅ Explicit unawaited() for fire-and-forget
@override
MyState build() {
  unawaited(_loadData());
  return const MyState.loading();
}
```

---

## Provider Placement

Provider files live **next to the class they provide**. Never create a separate `providers/` directory.

| What the provider creates | File location |
|---|---|
| UseCase | `domain/usecases/*_usecases_providers.dart` (bundled per feature) |
| ViewModel | Inline in `*_view_model.dart` |
| Service | Inline in `*_service.dart` or `*_service_provider.dart` next to it |
| Cross-feature state | `core/<module>/*_provider.dart` |

See `architecture.mdc` Section 6 for the full provider placement rules.
