---
description: Dart 3 coding standards — class modifiers, pattern matching, records, and type safety rules.
globs: lib/**/*.dart, test/**/*.dart
alwaysApply: false
---

# Dart 3 Coding Standards

---

## Class Modifiers

| Modifier | When to Use |
|---|---|
| `final class` | **Default** — closed for inheritance, prevents unintended subclassing |
| `sealed class` | State machines with discrete, exhaustively matched variants |
| `abstract class` | Only when a hierarchy with shared behavior is genuinely needed |
| `mixin` | Reusable behavior across unrelated classes (e.g. `KeepAliveClientMixin`) |

```dart
// ✅ Default: use final class
final class LoginUseCase { ... }

// ✅ State machine: use sealed class
sealed class LoginState {
  const factory LoginState.initial() = LoginInitial;
  const factory LoginState.loading() = LoginAuthenticating;
  const factory LoginState.success({required String userId}) = LoginSuccess;
  const factory LoginState.failure({required LoginErrorType error}) = LoginFailure;
}

// ✅ Hierarchy genuinely needed
abstract class BaseUseCase<T> {
  Future<T> execute();
}

// ✅ Reusable behavior
mixin RoomActionsMixin on Notifier<RoomState> {
  Future<void> archive() async { ... }
}
```

---

## Pattern Matching

### Switch Expressions

```dart
// Exhaustive switch on sealed class — compile error if case is missing
final message = switch (result) {
  LoginSuccess(:final userId) => 'Welcome $userId',
  LoginFailure(:final error) => error.localizedMessage,
};
```

### Switch Statements

```dart
switch (state) {
  case SendSuccess():
    this.state = this.state.copyWith(isSending: false);
  case SendError(:final type):
    this.state = this.state.copyWith(isSending: false, errorType: type);
}
```

### If-Case

```dart
if (state case LoginSuccess(:final userId)) {
  context.push('/home/$userId');
}
```

### Destructuring

```dart
// Record destructuring
final (:name, :age) = getUserInfo();

// List pattern
final [first, ...rest] = items;
```

---

## Records

Use records for **grouped return values** that don't warrant a full class:

```dart
// ✅ Record for simple grouped return
({String displayName, String avatarUrl}) getUserSummary() {
  return (displayName: user.name, avatarUrl: user.avatar);
}

// ✅ Positional record for pairs
(String, int) getRange() => ('start', 42);
```

Prefer a named class when:
- The record is returned from a public API
- It has more than 3-4 fields
- It needs methods or a doc comment

---

## Type Safety

| Rule | Example |
|---|---|
| **No `dynamic`** | Use specific types or `Object?` with runtime checks |
| **Prefer explicit types over `var`** | `var` is OK when the type is obvious from the right-hand side |
| **Use `required` for non-optional named params** | `const MyWidget({required this.title})` |
| **Use named parameters for clarity** | Prefer named over positional for 2+ parameters |
| **Avoid `late` without initialization** | Only use `late` when you can guarantee initialization before first access |

```dart
// ❌ dynamic
dynamic processEvent(dynamic event) { ... }

// ✅ Typed
ProcessedEvent processEvent(RawEvent event) { ... }

// ❌ Unnecessary var
var name = computeName(); // What type is this?

// ✅ Explicit or obvious
final String name = computeName();
final items = <String>[]; // OK — type argument makes it clear

// ❌ Positional params for complex constructors
createRoom('room-id', true, false, 'display name');

// ✅ Named params
createRoom(
  roomId: 'room-id',
  isEncrypted: true,
  isPublic: false,
  displayName: 'display name',
);
```

---

## Null Safety

```dart
// ✅ Null-aware operators
final name = user?.displayName ?? 'Unknown';
final length = text?.length ?? 0;

// ✅ Early return on null
final room = ref.read(roomProvider);
if (room == null) return;
// room is non-null from here

// ❌ Force-unwrap without guard
final room = ref.read(roomProvider)!; // Crashes if null
```

---

## Async

```dart
// ✅ Prefer async/await over raw Future chains
Future<LoginResult> login() async {
  final response = await _client.login();
  return LoginResult.success(userId: response.userId);
}

// ✅ Parallel async with Future.wait
final [profile, rooms] = await Future.wait([
  fetchProfile(),
  fetchRooms(),
]);

// ✅ Fire-and-forget: always use unawaited() with a comment
unawaited(_prefetchData()); // Pre-fetch in background, result not needed

// ❌ Discarded future (lint error)
_prefetchData(); // Dart linter flags this
```

---

## Imports

```dart
// Order: dart → flutter → packages → project (enforced by linter)
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:famedly/core/auth/auth_service.dart';
import 'package:famedly/features/chat/index.dart';
```

- Use **package imports** (`package:famedly/...`), not relative imports, for cross-module references.
- Use **relative imports** only within the same module/directory.
