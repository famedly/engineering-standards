---
description: Debug logging standards for Flutter Web runtime diagnosis
globs: lib/core/observability/debug_log.dart
alwaysApply: false
---

# Debug Logging with `debugLog()`

When debugging runtime issues in this Flutter Web project, use the project's `debugLog()` utility at `lib/core/observability/debug_log.dart`.

## Usage

```dart
import 'package:famedly/core/observability/debug_log.dart';

// Inside the function you want to instrument:
// #region agent log
debugLog('file.dart:methodName', 'Description of what is being logged', {
  'hypothesisId': 'A',
  'someValue': someVariable,
  'isNull': someObject == null,
});
// #endregion
```

## Rules

1. **Always wrap in `// #region agent log` / `// #endregion`** so the editor auto-folds instrumentation
2. **Never log secrets** (passwords, tokens, API keys, PII). Log lengths/nullability instead:
   - `'hasPassword': password != null` or `'passwordLength': password?.length ?? 0`
3. **Include `hypothesisId`** in the data map to link each log to a specific debug hypothesis
4. **Use `location` format** `'filename.dart:methodName'` or `'filename.dart:methodName:checkpoint'`
5. **Keep logs minimal** - 3-8 instrumentation points per debug session
6. **Remove after fix is verified** - instrumentation is temporary; clean up after log-based proof

## How It Works

`debugLog()` sends NDJSON via HTTP POST to Cursor's debug server (`127.0.0.1:7242`). Logs are written to `.cursor/debug.log` and can be read after reproduction.

## Workflow

1. Formulate 3-5 hypotheses about the bug
2. Add `debugLog()` calls at critical points (function entry/exit, before/after async gaps, branch decisions, state mutations)
3. Ask user to reproduce
4. Read `.cursor/debug.log` to evaluate hypotheses (CONFIRMED/REJECTED)
5. Fix only with log-based proof
6. Verify fix with a second run
7. Remove instrumentation after confirmed success
