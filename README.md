# veea-context-capture

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
- **[Completed]** Implement `ReplayKit` Broadcast Upload Extension to capture screen content across all applications.
- **[Completed]** Maintain persistence while the host app is in the background.

### FR-2: Frame Throttling & Optimization
- **[Completed]** **Sampling Rate:** Throttle capture configurable between **0.1 FPS and 5.0 FPS** directly from the Flutter Dashboard.
- **[Completed]** **Resolution:** Downscale 1080p frames to **~480p** immediately upon capture.
- **[Completed]** **Format:** Save frames as **HEIC** using `CIContext.heifRepresentation(...)` directly from the PixelBuffer to minimize disk I/O and memory.

### FR-3: Shared Data Pipeline
- **[Completed]** Write snapshots to a dedicated directory within the **Shared App Group Container**.
- **[Completed]** Utilize a **Circular Buffer Background Janitor** in Swift. Max storage is completely configurable via the Flutter UI (slider from **30 up to 10,000 frames**).

### FR-4: UI Management (Export & Delete)
- **[Completed]** Provide a multi-selection state in Flutter to select precise frames.
- **[Completed]** Utilize the `share_plus` package for exporting natively via the iOS Share Sheet.
- **[Completed]** Provide a native UI Delete function to selectively prune physical files from the App Group.

### FR-5: Live Dashboard Preview
- **[Completed]** Implement a real-time, sleek dashboard widget in Flutter that auto-refreshes using polling when new snapshots arrive.

---

## 4. Technical Constraints (The "50MB Wall")

| Constraint | Status | Requirement |
| :--- | :--- | :--- |
| **RAM Limit** | ✅ Successfully Mitigated | The Broadcast Extension **must** stay under **50MB**. Exceeding this triggers a "Jetsam" kill by iOS. |
| **Processing** | ✅ Implemented via CoreImage | Resizing uses `CIImage` and `CIContext` to avoid `UIImage` allocations for zero-copy memory efficiency. |
| **Privacy** | ✅ Native Implementation | The system utilizes the standard iOS "Red Recording Bar" alongside `RPSystemBroadcastPickerView`. |
| **Connectivity** | ✅ Local App Group | Local-first storage; no cloud upload occurs without explicit user action. |

---

## 5. Development Roadmap 

### Phase 1: Infrastructure (✅ Completed)
- Configure Apple Developer Portal with `App Group IDs`.
- Establish the Flutter host project and link the `Broadcast Upload Extension` target in Xcode.

### Phase 2: Capture Engine (Native) (✅ Completed)
- Develop the `SampleHandler.swift` logic:
  - Frame interception.
  - Sub-framerate Throttling (reading `Double` from UserDefaults).
  - Memory-efficient resizing to 480p.
  - Writing to the shared container.
  - Sub-process Background Janitor to delete old images automatically.

### Phase 3: Data Integration (Flutter) (✅ Completed)
- Implement `MethodChannel` Bridge access for `getSharedDir` and settings management.
- Build the "Snapshot Gallery" and "Share Sheet/Trash" triggers.
- Wrap the iOS `RPSystemBroadcastPickerView` trigger cleanly into the Dart layer.

### Phase 4: AI Agent Integration (In Progress / Future)
- Expose the shared folder via a local **MCP (Model Context Protocol)** server for third-party AI agents.

---

## 6. Implementation Notes
- **App Group ID:** `group.ai.bluleap.veea`
- **File Naming:** `snapshot_YYYYMMDD_HHMMSS.heic`
- **Memory Management:** Avoid `UIImage` conversions in the extension; process `CVPixelBuffer` directly to stay under the 50MB limit.

---

&copy; 2026 bluleap.ai / Veea Project
