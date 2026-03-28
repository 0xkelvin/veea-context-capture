# Code Review — Veea Context Capture

> Review performed against the requirements described in `README.md`.  
> All issues below were identified, addressed, and committed in this PR.

---

## Summary

| # | File | Severity | Category | Status |
|---|------|----------|----------|--------|
| 1 | `ios/CaptureEngine/SampleHandler.swift` | 🔴 Bug | Upscaling frames shorter than 480 px | ✅ Fixed |
| 2 | `ios/CaptureEngine/SampleHandler.swift` | 🟠 Performance | `DateFormatter` re-created on every frame | ✅ Fixed |
| 3 | `ios/CaptureEngine/SampleHandler.swift` | 🟠 Performance | `UserDefaults` read on every sample buffer | ✅ Fixed |
| 4 | `ios/CaptureEngine/SampleHandler.swift` | 🟡 Correctness | Missing `en_US_POSIX` locale on `DateFormatter` | ✅ Fixed |
| 5 | `ios/Runner/AppDelegate.swift` | 🟡 Deprecated API | `UserDefaults.synchronize()` | ✅ Fixed |
| 6 | `lib/main.dart` | 🔴 Bug | Nested `setState` in `_deleteSelected` | ✅ Fixed |
| 7 | `lib/main.dart` | 🟡 Deprecated API | `Color.withOpacity()` (8 usages) | ✅ Fixed |
| 8 | `lib/main.dart` | 🟡 Style | Old-style `Key? key` constructors (3 widgets) | ✅ Fixed |
| 9 | `lib/main.dart` | 🟠 Correctness | No error handling on `BridgeService` async methods | ✅ Fixed |
| 10 | `pubspec.yaml` | 🟡 Maintenance | Unused dependencies `shared_preferences` + `path_provider` | ✅ Fixed |
| 11 | `test/widget_test.dart` | 🔴 Bug | Stale test references non-existent `MyApp` class | ✅ Fixed |

---

## Detailed Findings

### 1. 🔴 Bug — Upscaling frames shorter than 480 px

**File:** `ios/CaptureEngine/SampleHandler.swift`

**Problem:**  
The scale formula `480.0 / ciImage.extent.height` produces a value greater than `1.0` when the
captured frame is shorter than 480 pixels (e.g. small windows, portrait orientation on some
devices). Instead of downscaling, the extension was **enlarging** those frames — wasting memory
and CPU, and potentially violating the 50 MB Jetsam limit.

```swift
// ❌ Before
let scale = 480.0 / ciImage.extent.height

// ✅ After
// Cap at 1.0 so we never upscale frames that are already shorter than 480 px.
let scale = min(1.0, 480.0 / ciImage.extent.height)
```

---

### 2. 🟠 Performance — `DateFormatter` re-created on every frame

**File:** `ios/CaptureEngine/SampleHandler.swift`

**Problem:**  
`DateFormatter` was instantiated inside `saveSnapshot()`, meaning a new object was allocated and
initialised on **every saved frame** (up to 5 times per second). `DateFormatter` is
[documented by Apple](https://developer.apple.com/documentation/foundation/dateformatter) as
expensive to create and should be reused.

```swift
// ❌ Before — new DateFormatter on every save call
private func saveSnapshot(data: Data) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
    let filename = "snapshot_\(formatter.string(from: Date())).heic"
    ...
}

// ✅ After — initialised once as a lazy stored property
private lazy var dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss_SSS"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private func saveSnapshot(data: Data) {
    let filename = "snapshot_\(dateFormatter.string(from: Date())).heic"
    ...
}
```

---

### 3. 🟠 Performance — `UserDefaults` read on every sample buffer

**File:** `ios/CaptureEngine/SampleHandler.swift`

**Problem:**  
`TargetFPS` and `MaxFrames` were Swift computed properties that opened a `UserDefaults` suite
on **every call**. Because `processSampleBuffer` is invoked by ReplayKit at the display refresh
rate (up to 60 Hz) before the throttle guard fires, this caused dozens of unnecessary disk reads
per second in the extension — the worst possible place for I/O given the 50 MB memory ceiling.

```swift
// ❌ Before — UserDefaults opened on every frame
private var TargetFPS: Double {
    let defaults = UserDefaults(suiteName: appGroupID)
    return (defaults?.double(forKey: "capture_fps") ?? 0) > 0
        ? defaults!.double(forKey: "capture_fps") : 1.0
}

// ✅ After — cached, refreshed at most once every 2 seconds
// Note: RPBroadcastSampleHandler delivers buffers serially on a single
// background thread, so no locking is required for these fields.
private var cachedFPS: Double = 1.0
private var cachedMaxFrames: Int = 300
private var settingsLastReadTime: TimeInterval = 0
private let settingsCacheInterval: TimeInterval = 2.0

private func refreshSettingsIfNeeded() {
    let now = CACurrentMediaTime()
    guard now - settingsLastReadTime >= settingsCacheInterval else { return }
    settingsLastReadTime = now
    let defaults = UserDefaults(suiteName: appGroupID)
    let fps = defaults?.double(forKey: "capture_fps") ?? 0
    cachedFPS = fps > 0 ? fps : 1.0
    let max = defaults?.integer(forKey: "max_frames") ?? 0
    cachedMaxFrames = max > 0 ? max : 300
}
```

---

### 4. 🟡 Correctness — Missing `en_US_POSIX` locale on `DateFormatter`

**File:** `ios/CaptureEngine/SampleHandler.swift`

**Problem:**  
Without an explicit locale, `DateFormatter` inherits the device's current locale. On some
locales, date/time separators or digit systems differ from ASCII, which can produce filenames
that are unreadable or cause file-lookup failures in the Flutter gallery.

```swift
// ✅ Fixed (part of finding #2 above)
f.locale = Locale(identifier: "en_US_POSIX")
```

---

### 5. 🟡 Deprecated API — `UserDefaults.synchronize()`

**File:** `ios/Runner/AppDelegate.swift`

**Problem:**  
`UserDefaults.synchronize()` has been deprecated since iOS 12. The OS automatically persists
`UserDefaults` to disk; calling `synchronize()` is a no-op in modern iOS and generates a
compiler deprecation warning.

```swift
// ❌ Before
defaults?.set(value, forKey: key)
defaults?.synchronize()  // ⚠️ deprecated

// ✅ After
defaults?.set(value, forKey: key)
```

---

### 6. 🔴 Bug — Nested `setState` in `_deleteSelected`

**File:** `lib/main.dart`

**Problem:**  
`_deleteSelected` called `_loadSnapshots()` **inside** the `setState` callback.
`_loadSnapshots` itself calls `setState`, resulting in a nested `setState` which Flutter
forbids and will throw a `FlutterError` at runtime in debug mode.

```dart
// ❌ Before — _loadSnapshots (which calls setState) is inside setState
void _deleteSelected() {
  ...
  setState(() {
    _selectedPaths.clear();
    _loadSnapshots(); // ← calls setState inside setState!
  });
}

// ✅ After — _loadSnapshots called after setState completes
void _deleteSelected() {
  ...
  setState(() {
    _selectedPaths.clear();
  });
  _loadSnapshots();
}
```

---

### 7. 🟡 Deprecated API — `Color.withOpacity()` (8 usages)

**File:** `lib/main.dart`

**Problem:**  
`Color.withOpacity()` is deprecated in Flutter 3.27+ / Dart 3.10+ in favour of
`Color.withValues(alpha:)`. All 8 usages generated deprecation warnings.

```dart
// ❌ Before
Theme.of(context).colorScheme.primary.withOpacity(0.4)
Colors.black.withOpacity(0.5)
Colors.white.withOpacity(0.05)

// ✅ After
Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
Colors.black.withValues(alpha: 0.5)
Colors.white.withValues(alpha: 0.05)
```

---

### 8. 🟡 Style — Old-style `Key? key` constructors

**File:** `lib/main.dart`

**Problem:**  
Three widget constructors used the old Dart 2 pattern `{Key? key} : super(key: key)`.  
Dart 2.17+ introduced the `super.key` shorthand which is preferred by `flutter_lints`.

```dart
// ❌ Before
class VeeaContextApp extends StatelessWidget {
  const VeeaContextApp({Key? key}) : super(key: key);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

class GlassMorphCard extends StatelessWidget {
  const GlassMorphCard({Key? key, required this.child}) : super(key: key);

// ✅ After
class VeeaContextApp extends StatelessWidget {
  const VeeaContextApp({super.key});

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

class GlassMorphCard extends StatelessWidget {
  const GlassMorphCard({super.key, required this.child});
```

---

### 9. 🟠 Correctness — No error handling on `BridgeService` async methods

**File:** `lib/main.dart`

**Problem:**  
`setFPS`, `getFPS`, `setMaxFrames`, `getMaxFrames`, and `launchCapture` had no `try/catch`.
A `PlatformException` from the native side (e.g. wrong platform, extension not configured,
or iOS permission denial) would propagate unhandled and crash the calling widget.

```dart
// ❌ Before
static Future<void> setFPS(double fps) async {
  await _channel.invokeMethod('setSetting', {'key': 'capture_fps', 'value': fps});
}

// ✅ After
static Future<void> setFPS(double fps) async {
  try {
    await _channel.invokeMethod('setSetting', {'key': 'capture_fps', 'value': fps});
  } catch (e) {
    debugPrint("Bridge setFPS Error: $e");
  }
}
```

> Same pattern applied to `getFPS`, `setMaxFrames`, `getMaxFrames`, and `launchCapture`.

---

### 10. 🟡 Maintenance — Unused dependencies in `pubspec.yaml`

**File:** `pubspec.yaml`

**Problem:**  
`shared_preferences` and `path_provider` are declared as runtime dependencies but are never
imported or referenced anywhere in the Dart codebase. They bloat the compiled artifact and
increase the attack surface without providing any value.

```yaml
# ❌ Before
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  share_plus: ^12.0.1
  shared_preferences: ^2.5.5   # ← never used
  path_provider: ^2.1.5        # ← never used

# ✅ After
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  share_plus: ^12.0.1
```

---

### 11. 🔴 Bug — Stale widget test references non-existent `MyApp`

**File:** `test/widget_test.dart`

**Problem:**  
The test file was the unchanged Flutter counter-app template. It imported and instantiated
`MyApp`, which does not exist in this project. Running `flutter test` would fail immediately
with a compile error.

```dart
// ❌ Before — references non-existent MyApp
testWidgets('Counter increments smoke test', (WidgetTester tester) async {
  await tester.pumpWidget(const MyApp()); // ← compile error
  expect(find.text('0'), findsOneWidget);
  ...
});

// ✅ After — tests the actual VeeaContextApp
testWidgets('VeeaContextApp renders without crashing', (WidgetTester tester) async {
  await tester.pumpWidget(const VeeaContextApp());
  expect(find.byType(MaterialApp), findsOneWidget);
});

testWidgets('DashboardScreen shows header text', (WidgetTester tester) async {
  await tester.pumpWidget(const VeeaContextApp());
  await tester.pump();
  expect(find.text('Veea Edge AI'), findsOneWidget);
  expect(find.text('Live Context Bridge'), findsOneWidget);
});

testWidgets('DashboardScreen shows empty state when no snapshots', (WidgetTester tester) async {
  await tester.pumpWidget(const VeeaContextApp());
  await tester.pump();
  expect(find.text('No Context Available'), findsOneWidget);
});
```

---

## Files Changed

| File | Changes |
|------|---------|
| `ios/CaptureEngine/SampleHandler.swift` | Findings #1 #2 #3 #4 |
| `ios/Runner/AppDelegate.swift` | Finding #5 |
| `lib/main.dart` | Findings #6 #7 #8 #9 |
| `pubspec.yaml` | Finding #10 |
| `test/widget_test.dart` | Finding #11 |

---

*© 2026 bluleap.ai / Veea Project*
