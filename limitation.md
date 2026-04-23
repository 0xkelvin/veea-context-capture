# Platform Limitations

## iOS — Screen Recording Cannot Restart Automatically After Unlock

### Background

When the iPhone screen is locked, iOS unconditionally terminates any active
ReplayKit broadcast extension. This is an OS-level privacy enforcement
mechanism that cannot be overridden by any third-party app or entitlement.

### Why Fully-Automatic Restart Is Not Possible

Apple's broadcast APIs (`RPBroadcastActivityViewController` and
`RPSystemBroadcastPickerView`) are the only two ways to start a ReplayKit
broadcast extension. Both are **hardened against programmatic triggering**
— they require a genuine, user-initiated physical tap every time a broadcast
is started:

| Attempted method | iOS response |
|---|---|
| `sendActions(for: .touchUpInside)` on the picker button | iOS 15+: silently ignored or shows a second system confirmation sheet |
| `RPBroadcastActivityViewController` presented in code | Requires a user tap on the presented UI to proceed |
| Background task / `BGTask` / `BGAppRefreshTask` | Not permitted to start a broadcast extension at all |
| Screen-on notification → background app → auto-start | No background API exists to start a broadcast extension |

This is intentional. Apple does not allow any app to silently start recording
the user's screen without an explicit physical tap every single time.

### What This App Does (Best Possible UX)

The app implements a two-path flow that surfaces a one-tap restart button
immediately after the screen is unlocked. The single tap on the **●** button
in the banner is the absolute minimum interaction iOS requires.

**Path A — app was in the foreground when the screen locked:**

```
screen unlock
  → applicationDidBecomeActive
  → restartCaptureIfNeeded()      (stale-flag reset + isRunning check)
  → showRestartBanner()           (UIKit overlay floats above Flutter UI)
     └── RPSystemBroadcastPickerView  ← user taps ● → broadcast resumes
```

**Path B — app was backgrounded when the screen locked:**

```
screen lock
  → SampleHandler.broadcastFinished()
  → scheduleRestartNotification() (2-second local notification delay)

user unlocks → taps "Recording paused" notification → app foregrounds
  → applicationDidBecomeActive (also fires)
  → showRestartBanner()           (UIKit overlay floats above Flutter UI)
     └── RPSystemBroadcastPickerView  ← user taps ● → broadcast resumes
```

If the user stopped recording intentionally (tapped **Stop** in the app),
`capture_wants_active` is set to `false` so the restart banner and
notification are **not** shown.

### Summary

| Goal | Possible? |
|---|---|
| Zero-tap fully automatic restart after unlock | ❌ Not possible on iOS |
| One-tap restart with automatic native UI prompt | ✅ Implemented |
| Banner appears automatically on unlock (app foregrounded) | ✅ Implemented |
| Notification if app was backgrounded at lock time | ✅ Implemented |
| No prompt if user stopped recording intentionally | ✅ Implemented |

### Relevant Source Files

| File | Purpose |
|---|---|
| `ios/Runner/AppDelegate.swift` | `applicationDidBecomeActive`, `showRestartBanner`, notification delegates |
| `ios/CaptureEngine/SampleHandler.swift` | `broadcastFinished`, `scheduleRestartNotification` |
