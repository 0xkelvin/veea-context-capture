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
- Implement `ReplayKit` Broadcast Upload Extension to capture screen content across all applications.
- Maintain persistence while the host app is in the background.

### FR-2: Frame Throttling & Optimization
- **Sampling Rate:** Throttle capture to **1 Frame Per Second (FPS)** or less (configurable).
- **Resolution:** Downscale 1080p frames to **480p/360p** immediately upon capture.
- **Format:** Save frames as **HEIC** (preferred) or high-compression **JPEG** to minimize disk I/O and memory.

### FR-3: Shared Data Pipeline
- Write snapshots to a dedicated directory within the **Shared App Group Container**.
- Utilize a **Circular Buffer** logic (e.g., keeping only the last 10–50 frames) to prevent storage bloat.

### FR-4: Manual Export (The "User Way")
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

## 5. Proposed Roadmap for Antigravity

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

&copy; 2026 bluleap.ai / Veea Project
