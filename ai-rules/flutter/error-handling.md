---
description: Error handling strategy — Result types, layer-specific patterns, graceful degradation, and Sentry reporting rules.
globs: lib/**/*.dart, test/**/*.dart
alwaysApply: false
---

# Error Handling

Every error falls into one of four categories. Choose the handling strategy based on the category — do not use a one-size-fits-all approach.

---

## Error Categories

| Category | Description | Strategy | Example |
|---|---|---|---|
| **Expected, user-actionable** | User can fix or retry | Return typed Result → ViewModel maps to error State → UI shows message + retry | Message too large, permission denied |
| **Expected, non-actionable** | Transient or infrastructure, user cannot fix | Return typed Result or `Logs().v()` / `Logs().w()` | Typing indicator network error, draft save failure |
| **Unexpected** | Programming errors that should not happen | `ErrorReporter.reportError()` (Sentry) + typed Result | `StateError`, `TypeError`, unhandled SDK exception |
| **Graceful degradation** | High-frequency or non-critical, failure is invisible | Silent catch with **documented comment** explaining why | Amplitude polling at 100ms, permission pre-check |

---

## Layer-Specific Patterns

### UseCases — Return Sealed Result Types

Every UseCase that performs I/O **must** return a sealed Result type. No raw exceptions may escape a UseCase.

```dart
final class LoginUseCase {
  Future<LoginResult> execute({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.login(username, password);
      return LoginResult.success(userId: response.userId);
    } on MatrixException catch (e) {
      return LoginResult.failure(type: _mapMatrixError(e), originalError: e);
    } on SocketException {
      return LoginResult.failure(type: LoginErrorType.network);
    } catch (e, s) {
      // Only unexpected errors go to Sentry
      ErrorReporter.reportError(e, s, hint: 'LoginUseCase.execute');
      return LoginResult.failure(type: LoginErrorType.unknown, originalError: e);
    }
  }
}

sealed class LoginResult {
  const factory LoginResult.success({required String userId}) = LoginSuccess;
  const factory LoginResult.failure({
    required LoginErrorType type,
    Object? originalError,
  }) = LoginFailure;
}
```

### ViewModels — Map Results to State

ViewModels **must** await UseCase results and map them to state. Two valid patterns:

**Pattern A — `AsyncValue.guard`** (when ViewModel state is `AsyncValue`):

```dart
Future<void> login({required String username, required String password}) async {
  state = const AsyncValue.loading();

  state = await AsyncValue.guard(() async {
    final result = await ref.read(loginUseCaseProvider).execute(
      username: username,
      password: password,
    );
    return switch (result) {
      LoginSuccess(:final userId) => LoginState.success(userId: userId),
      LoginFailure(:final type) => throw LoginException(type: type),
    };
  });
}
```

**Pattern B — Sealed state classes** (when ViewModel state is a sealed/final class):

```dart
Future<bool> send({required String text}) async {
  state = state.copyWith(isSending: true, sendFailed: false);

  final result = await ref.read(sendUseCaseProvider).execute(text: text);
  if (!ref.mounted) return false;

  switch (result) {
    case SendSuccess():
      state = state.copyWith(isSending: false);
      return true;
    case SendError():
      state = state.copyWith(isSending: false, sendFailed: true);
      return false;
  }
}
```

**ViewModels must never:**
- Discard Futures from UseCase calls — use `await` or explicit `unawaited()` with a comment
- Report to Sentry directly — errors are reported at the UseCase level
- Silently swallow errors without at minimum `Logs().v()`

### Widgets / Presenters — Display State

```dart
return state.when(
  loading: () => const CircularProgressIndicator(),
  error: (error, _) => ErrorDisplay(
    message: _mapErrorToMessage(error, l10n),
    onRetry: () => ref.invalidate(loginViewModelProvider),
  ),
  data: (data) => LoginView(state: data),
);
```

Never show `error.toString()` directly to the user — always map to a localized message.

---

## Graceful Degradation

Silent failure is acceptable **only when all four conditions are met**:

1. The failure has **no user-visible impact** (e.g. a single missed amplitude sample)
2. The operation **retries automatically** (e.g. next timer tick)
3. Logging every failure would **flood the console** (e.g. 10 calls/second)
4. The catch block has a **documented comment** explaining why silence is acceptable

```dart
// ✅ Acceptable: documented graceful degradation
Future<double> getAmplitude() async {
  try {
    return await _recorder.getAmplitude();
  } catch (_) {
    // Graceful degradation: called every 100ms during recording.
    // A single missed sample is invisible to the user; the next tick retries.
    return _minAmplitude;
  }
}

// ❌ Forbidden: silent catch without explanation
Future<double> getAmplitude() async {
  try {
    return await _recorder.getAmplitude();
  } catch (_) {
    return _minAmplitude; // Why? Unknown. Do not do this.
  }
}
```

When in doubt, **prefer logging** (`Logs().v()` or `Logs().w()`) over silence.

---

## Sentry Reporting Rules

| Layer | When to Report |
|---|---|
| **UseCase** | Only unexpected / unknown errors |
| **ViewModel** | Never — errors propagate via state |
| **Presenter / Widget** | Never — errors display via state |

**Do NOT report** (expected infrastructure errors):
- `SocketException`
- `TimeoutException`
- `M_LIMIT_EXCEEDED`
- `M_FORBIDDEN`

**Always report** (unexpected programming errors):
- `StateError`
- `TypeError`
- `NoSuchMethodError`
- `UnimplementedError`

---

## Anti-Patterns

```dart
// ❌ Silent catch without documentation
try { ... } catch (e) { }

// ❌ print instead of proper logging/reporting
catch (e) { print(e); }

// ❌ Result discarded — UseCase called but outcome ignored
await loginUseCase.execute(username, password);

// ❌ Future from UseCase not awaited
ref.read(useCaseProvider).execute(); // Future discarded!

// ❌ Raw exception shown to user
Text(error.toString())

// ❌ UseCase without a Result type — raw exception escapes
Future<String?> execute() => room.sendEvent(content);

// ❌ ViewModel reports to Sentry (belongs in UseCase)
catch (e, s) {
  ErrorReporter.reportError(e, s); // Wrong layer!
  state = MyState.failure();
}
```
