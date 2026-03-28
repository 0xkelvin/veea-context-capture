# Veea iOS Context Capture (Vision Bridge)

## 1. Project Overview
The **Veea Context Capture** system is an iOS-based "Vision Bridge" designed to provide continuous visual context for Edge AI agents. By utilizing a native iOS Broadcast Extension, the system captures system-wide screen state (even in the background) and stores high-efficiency snapshots for processing by local or remote AI models.

## 2. System Architecture
The application employs a **Dual-Process Hybrid Architecture** to satisfy iOS background execution and memory constraints.

* **Host App (Flutter):** Handles User Interface, session management, and the manual "Share" export functionality.
* **Capture Engine (Native Swift):** A lightweight `RPBroadcastSampleHandler` extension that intercepts the system video stream.
* **The Bridge (App Groups):** A shared security container (`group.ai.bluleap.veea`) used for cross-process file sharing.

---

## 3. Functional Requirements (FR)

### FR-1: System-Wide Capture
- Implement `ReplayKit` Broadcast Upload Extension to capture screen content across all applications.
- Maintain persistence while the host app is in the background.

### FR-2: Frame Throttling & Optimization
- **Sampling Rate:** Throttle capture to **1 Frame Per Second (FPS)** or less (configurable).
- **Resolution:** Downscale 1080p frames to **480p/360p** immediately upon capture.
- **Format:** Save frames as **HEIC** (preferred) or high-compression **JPEG** to minimize disk I/O and memory.

### FR-3: Shared Data Pipeline
- Write snapshots to a dedicated directory within the **Shared App Group Container**.
- Utilize a **Circular Buffer** logic (e.g., keeping only the last 10–50 frames) to prevent storage bloat.

### FR-4: Manual Export
- Provide a "Share Context" button in the Flutter UI.
- Integrate the `share_plus` package to allow manual export of snapshots via the native iOS Share Sheet (AirDrop, Email, etc.).

### FR-5: Live Dashboard Preview
- Implement a real-time "Current View" widget in Flutter that auto-refreshes when a new snapshot is detected in the shared container.

---

## 4. Technical Constraints (The "50MB Wall")

| Constraint | Requirement |
| :--- | :--- |
| **RAM Limit** | The Broadcast Extension **must** stay under **50MB**. Exceeding this triggers a "Jetsam" kill by iOS. |
| **Processing** | Resizing must use the **Accelerate** or **Vision** framework for zero-copy memory efficiency. |
| **Privacy** | The system utilizes the standard iOS "Red Recording Bar" as a required transparency feature. |
| **Connectivity** | Local-first storage; no cloud upload occurs without explicit user action. |

---

## 5. Development Roadmap

### Phase 1: Infrastructure
- Configure Apple Developer Portal with `App Group IDs`.
- Establish the Flutter host project and link the `Broadcast Upload Extension` target in Xcode.

### Phase 2: Capture Engine (Native)
- Develop the `SampleHandler.swift` logic:
  - Frame interception.
  - Throttling (dropping 59/60 frames).
  - Memory-efficient resizing to 480p.
  - Writing to the shared container.

### Phase 3: Data Integration (Flutter)
- Implement `AppGroupDirectory` access.
- Build the "Snapshot Gallery" and "Share Sheet" triggers.
- Add a "Janitor" service to clean up old images in the shared folder.

### Phase 4: AI Agent Integration
- Expose the shared folder via a local **MCP (Model Context Protocol)** server for third-party AI agents.

---

## 6. Implementation Notes
- **App Group ID:** `group.ai.bluleap.veea`
- **File Naming:** `snapshot_YYYYMMDD_HHMMSS.heic`
- **Memory Management:** Avoid `UIImage` conversions in the extension; process `CVPixelBuffer` directly to stay under the 50MB limit.

---

## 7. Prerequisites

Before building this project, ensure you have the following installed and configured:

| Requirement | Version / Notes |
| :--- | :--- |
| **Xcode** | 15.0 or later |
| **Flutter SDK** | 3.x or later |
| **Apple Developer Account** | Required to create App Group IDs and provision devices |
| **iOS Device / Simulator** | iOS 16.0 or later (ReplayKit Broadcast Extension requires a real device for full testing) |
| **CocoaPods** *(if used)* | Latest stable release |

---

## 8. Getting Started

```bash
# 1. Clone the repository
git clone https://github.com/0xkelvin/veea-context-capture.git
cd veea-context-capture

# 2. Install Flutter dependencies
flutter pub get

# 3. Open the Xcode workspace (required to configure the Broadcast Extension target)
open ios/Runner.xcworkspace
```

Once in Xcode:

1. Select the **Runner** target → **Signing & Capabilities** → add the `App Groups` entitlement and set the group ID to `group.ai.bluleap.veea`.
2. Repeat for the **Broadcast Upload Extension** target.
3. Build and run on a physical iOS device (`ReplayKit` screen recording is unavailable in the simulator).

---

## 9. Contributing

Contributions, issues, and feature requests are welcome.

1. Fork the repository and create your branch: `git checkout -b feat/my-feature`.
2. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/).
3. Open a Pull Request describing your changes and referencing any related issues.

Please search existing issues before opening a new one to avoid duplicates.

---

## 10. License

This project is proprietary software. All rights reserved by bluleap.ai unless otherwise stated. See the copyright notice below.

---

## 11. Technical Concerns & Open Questions

The following questions and concerns were raised during a technical review of the requirements above. They should be answered or resolved before implementation begins.

---

### 11.1 Memory Management & the 50 MB Wall

**Q1 — Monitoring strategy:** The 50 MB Jetsam limit is a hard constraint, but there is no defined strategy for monitoring memory consumption during development or CI. How will the team measure RSS usage of the extension — via Instruments, a unit-test memory probe, or automated profiling in CI?

**Q2 — Memory spike handling:** Even if the average frame-processing path stays under 50 MB, temporary allocations (e.g., during HEIC encoding) may create peaks that exceed the limit. Is there a defined safety margin (e.g., target ≤ 40 MB to leave 10 MB headroom)?

**Q3 — Accelerate vs. Vision:** The constraints table lists both `Accelerate` and `Vision` as acceptable resizing frameworks. These have different memory and CPU profiles. Which is preferred, and under what circumstances should one be chosen over the other?

---

### 11.2 Frame Throttling (FR-2)

**Q4 — Variable source frame rate:** The roadmap describes throttling as "dropping 59/60 frames," which assumes a fixed 60 Hz source. In practice, `RPBroadcastSampleHandler` delivers frames at the display's native refresh rate, which varies (30 Hz on older devices, 60 Hz standard, 120 Hz ProMotion on newer iPhones). Should the throttle be time-based (keep one frame per second using a `CACurrentMediaTime` timestamp comparison) rather than count-based, to be device-agnostic?

**Q5 — Configurability mechanism:** FR-2 states the sampling rate is "configurable." What is the configuration mechanism — a user-facing in-app setting, a remote-config flag, a compile-time constant, or a file in the shared container that the AI agent can write to?

---

### 11.3 Image Encoding (FR-2)

**Q6 — HEIC CPU cost vs. RAM budget:** HEIC encoding is more CPU-intensive than JPEG. Although it produces smaller files, the encoding pipeline may require temporary buffers that push RAM usage closer to the 50 MB limit. Has this trade-off been profiled? Is there a fallback to JPEG if HEIC encoding risks exceeding the memory budget?

**Q7 — Hardware encoder availability:** HEIC hardware acceleration is available on Apple A-series chips (iPhone 7+), but the behavior may differ on older or simulator builds. Is there a minimum supported device model, and how should the code handle encoding errors on unsupported hardware?

---

### 11.4 Circular Buffer & Thread Safety (FR-3)

**Q8 — Concurrency model:** The Broadcast Extension (one OS process) writes frames to the shared container while the Flutter host app (a separate OS process) reads from it. Standard file I/O is not inherently atomic across processes. What synchronization primitive will be used to prevent torn reads or a corrupted file list — `NSFileCoordinator`, advisory file locks, atomic renames, or a shared index file with a write-intent flag?

**Q9 — Default buffer size:** The spec states "10–50 frames." At 480p HEIC (~100 KB/frame), 50 frames ≈ 5 MB of disk, which is acceptable. But the choice affects both the AI agent's available context window and storage pressure on low-storage devices. What is the default, and is it user-adjustable?

**Q10 — Partial-write resilience:** If the extension process is killed (Jetsam or user action) while writing a frame, the destination file may be incomplete. How will the reader (Flutter side) detect and discard partially written files?

---

### 11.5 Live Dashboard (FR-5) — Change Detection

**Q11 — File-system event strategy:** The Flutter host app needs to detect when new snapshots appear in the shared container. Options include:

| Strategy | Battery impact | Latency | Notes |
| :--- | :--- | :--- | :--- |
| Polling (`Timer`) | High | ~0.5–2 s | Simple but wasteful |
| Darwin notifications (`CFNotificationCenter`) | Low | <50 ms | Requires native platform channel |
| `DispatchSource` file-system events | Low | <50 ms | Not directly accessible from Flutter |
| `NSFileCoordinator` presenter | Low | <50 ms | Designed for cross-process coordination |

Which approach is intended? A platform channel bridging Darwin notifications or `NSFileCoordinator` is recommended to avoid polling.

---

### 11.6 MCP Server (Phase 4)

**Q12 — Transport protocol:** The spec says "expose the shared folder via a local MCP server," but does not define the transport. HTTP, WebSocket, and Unix domain sockets all have different security and performance trade-offs. Which is planned?

**Q13 — Process placement:** Will the MCP server run inside the Flutter host app, as an extension, or as a background `URLSession` task? Running it inside the 50 MB Broadcast Extension is not feasible. Running it inside the host app means it stops when the host app is suspended. This needs clarification.

**Q14 — Authentication & security:** The MCP server will expose all captured screenshots to any local process that knows the endpoint. Is there a planned authentication layer (e.g., a shared secret, local-only socket path, or entitlement check) to prevent unauthorized access by other apps or processes on the same device?

**Q15 — Port conflict management:** If the user runs multiple AI agent tools simultaneously, how are port conflicts avoided? Is a fixed port used, or is a dynamically assigned port advertised via Bonjour/mDNS?

---

### 11.7 File Naming & Collision (§6)

**Q16 — Sub-second collisions:** The naming scheme `snapshot_YYYYMMDD_HHMMSS.heic` has 1-second granularity. If the throttle is set to exactly 1 FPS and the system delivers frames at irregular intervals, two frames could fall within the same second and collide. Should the scheme be extended to millisecond precision (e.g., `snapshot_YYYYMMDD_HHMMSS_mmm.heic`) or use a monotonic counter?

---

### 11.8 Privacy & Entitlements (FR-1)

**Q17 — Mid-session permission revocation:** The red recording bar is the system's transparency mechanism, but there is no mention of what happens if the user taps the bar and stops the broadcast mid-session. How will the extension signal this event to the Flutter app, and how will the app recover or prompt the user to restart?

**Q18 — `Info.plist` keys:** Does the extension's `Info.plist` include `NSBroadcastUsageDescription`? Has the required `RPBroadcastProcessMode` key been set to `RPBroadcastProcessModeSampleBuffer`? These are required for App Store submission and for the extension to function correctly.

---

### 11.9 Platform Scope

**Q19 — Android:** The README describes an entirely iOS-specific architecture (ReplayKit, App Groups, HEIC, `CVPixelBuffer`). If Android support is a future requirement, the entire capture engine would need to be rebuilt using Android's `MediaProjection` API with a different IPC mechanism. Is Android intentionally out of scope, and if so, should the README make this explicit?

---

### 11.10 Testing Strategy

**Q20 — Extension unit testing:** `RPBroadcastSampleHandler` cannot be instantiated in a standard XCTest target. How will the frame-processing logic (throttle, resize, write) be unit-tested — via a protocol abstraction that can be mocked, or exclusively through integration/manual testing on a device?

**Q21 — Automated memory regression:** Is there a plan to add an XCTest `measure` block or an Instruments automation script that fails the build if the extension's peak RSS exceeds a defined threshold (e.g., 40 MB)?

---

### 11.11 App Store Distribution Risk

**Q22 — Review policy:** Continuous system-wide screen recording is a sensitive capability. Apple's App Review guidelines (§5.1.1 — Data Collection and Storage) require clear disclosure of what is captured and why. Has a privacy policy and App Store review strategy been defined? Is the intended distribution channel the App Store, TestFlight only, or enterprise/ad-hoc?

---

### 11.12 Flutter–Native Integration

**Q23 — App Group path access from Flutter:** The spec mentions `share_plus` for export, but does not specify how the Flutter layer reads files from the App Group container. The standard `path_provider` package does not support App Group paths on iOS. Will this be handled via a custom platform channel, a Dart FFI binding, or a community plugin such as `app_group_directory`? The chosen approach should be documented before Phase 3 begins.

---

© 2026 bluleap.ai / Veea Project
