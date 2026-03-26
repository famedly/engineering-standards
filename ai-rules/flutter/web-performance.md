---
description: Web-specific performance guidelines for deferred loading, startup optimization, and caching.
globs: lib/**/*.dart, web/**
---

# Web Performance Guidelines

Optimizing Flutter Web performance requires different strategies than mobile. This rule covers critical patterns for fast Time to First Paint (TTFP) and smooth runtime performance.

## Startup Optimization

### Critical vs. Non-Critical Initialization

**Rule**: Never block `runApp()` with heavy initialization. Show UI first, load the rest in parallel.

```dart
// ❌ BAD: Blocking before runApp
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await heavyInit1();  // BLOCKING
  await heavyInit2();  // BLOCKING
  runApp(MyApp());
}

// ✅ GOOD: UI first, init in parallel
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SplashScreen());
  
  // Fire-and-forget: parallel initialization
  unawaited(_initializeNonCritical());
}

Future<void> _initializeNonCritical() async {
  await Future.wait([
    vod.init(),
    SentryFlutter.init(...),
    ServiceWorkerInterface.unregisterOldWorkers(),
  ]);
}
```

### Client Initialization

**Rule**: Don't await full sync before showing UI. Use `waitForFirstSync: false` and let providers handle loading states.

```dart
// ❌ BAD: Blocking on data loading
await client.init(...);
await client.roomsLoading;      // BLOCKING
await client.accountDataLoading; // BLOCKING

// ✅ GOOD: Init only, data loads in background
await client.init(waitForFirstSync: false);
// roomsLoading and accountDataLoading handled by providers with loading UI
```

## Deferred Loading (Code Splitting)

### When to Use `deferred as`

Use deferred imports for features that:
- Are not visible on the first screen
- Are behind user navigation (settings, share, call)
- Have large dependency trees

### Feature-Level Code Splitting

```dart
// In router or feature entry points
import '../../features/call/index.dart' deferred as call;
import '../../features/settings/index.dart' deferred as settings;
import '../../features/share/index.dart' deferred as share;
```

### Deferred Loading Pattern for Routes

```dart
GoRoute(
  path: 'settings',
  pageBuilder: (context, state) async {
    await settings.loadLibrary();
    return defaultPageBuilder(state, const settings.SettingsScreen());
  },
),
```

### Deferred Loader Widget

Use a wrapper widget to handle loading states:

```dart
class DeferredLoader extends StatelessWidget {
  final Future<void> Function() loadLibrary;
  final Widget Function() builder;
  final Widget? loadingWidget;

  const DeferredLoader({
    required this.loadLibrary,
    required this.builder,
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loadLibrary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loadingWidget ?? const Center(child: CircularProgressIndicator());
        }
        return builder();
      },
    );
  }
}
```

## Image Caching

### LRU Cache for MxcImage

**Rule**: Never use unbounded caches. Implement LRU eviction.

```dart
// ❌ BAD: Unbounded cache (memory leak)
static final Map<String, Uint8List> _imageDataCache = {};

// ✅ GOOD: LRU cache with size limit
static final _imageDataCache = LinkedHashMap<String, Uint8List>();
static const _maxCacheEntries = 50;

void _cacheImage(String key, Uint8List data) {
  if (_imageDataCache.length >= _maxCacheEntries) {
    _imageDataCache.remove(_imageDataCache.keys.first); // LRU eviction
  }
  _imageDataCache[key] = data;
}
```

For more sophisticated caching, consider byte-size limits:

```dart
static int _currentCacheBytes = 0;
static const _maxCacheBytes = 50 * 1024 * 1024; // 50 MB

void _cacheImage(String key, Uint8List data) {
  while (_currentCacheBytes + data.length > _maxCacheBytes && 
         _imageDataCache.isNotEmpty) {
    final firstKey = _imageDataCache.keys.first;
    _currentCacheBytes -= _imageDataCache[firstKey]!.length;
    _imageDataCache.remove(firstKey);
  }
  _imageDataCache[key] = data;
  _currentCacheBytes += data.length;
}
```

## Riverpod Performance

### Use `select()` to Minimize Rebuilds

**Rule**: Always use `.select()` when watching providers that update frequently.

```dart
// ❌ BAD: Rebuilds on any room change
final rooms = ref.watch(roomListControllerProvider);

// ✅ GOOD: Only rebuilds when room IDs change
final roomIds = ref.watch(
  roomListControllerProvider.select((state) => state.roomIds),
);

// ✅ GOOD: Only rebuilds when specific field changes
final unreadCount = ref.watch(
  roomSnapshotProvider(roomId).select((room) => room?.unreadCount ?? 0),
);
```

## Web-Specific Anti-Patterns ❌

### Don't: Nested MaterialApps

Avoid nesting `MaterialApp` widgets. If you need an `Overlay` ancestor, provide it manually:

```dart
// ❌ BAD: Nested MaterialApps
MaterialApp(
  home: MaterialApp.router(...), // Creates duplicate theme/localization
)

// ✅ GOOD: Manual Overlay
MaterialApp.router(
  builder: (context, child) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => MyWrapper(child: child)),
      ],
    );
  },
)
```

### Don't: Heavy Sync Operations on Main Thread

Avoid JSON parsing, image decoding, or other CPU-intensive work on the main thread:

```dart
// ❌ BAD: Blocking main thread
final data = jsonDecode(hugeJsonString);

// ✅ GOOD: Use compute/isolate
final data = await compute(jsonDecode, hugeJsonString);
```

### Don't: Recreate Routers on Layout Changes

```dart
// ❌ BAD: Router recreated on every column mode toggle
return isColumnMode ? GoRouter(routes: columnRoutes) : GoRouter(routes: normalRoutes);

// ✅ GOOD: Use responsive routes within single router
GoRoute(
  builder: (context, state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth > 600 
          ? WideLayout() 
          : NarrowLayout();
      },
    );
  },
)
```

### Don't: Ignore Platform Checks

```dart
// ✅ Use kIsWeb for web-specific code paths
if (kIsWeb) {
  // Web-optimized path
} else {
  // Mobile path
}
```

## Performance Checklist

Before merging web-facing changes, verify:

- [ ] `runApp()` is not blocked by heavy initialization
- [ ] Features behind navigation use `deferred as` imports
- [ ] Image caches have size limits (LRU or byte-based)
- [ ] Frequently-updated providers use `.select()`
- [ ] No nested `MaterialApp` widgets
- [ ] CPU-intensive work offloaded to isolates
