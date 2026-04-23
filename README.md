# POC 

<img width="309" height="668" alt="image" src="https://github.com/user-attachments/assets/c1cab894-1416-4a56-a89c-b39c0b030409" />

<img width="308" height="672" alt="image" src="https://github.com/user-attachments/assets/b10a91cb-6d5d-4247-b414-944502acb760" />

<img width="308" height="669" alt="image" src="https://github.com/user-attachments/assets/c8f10446-e663-4f0f-8eee-b3dca03ad8cc" />





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

### FR-2: Adaptive Frame Capture & Optimization
- **[Completed]** **Max Capture Rate:** Configurable upper-bound FPS (**0.1–5.0 FPS**) set directly from the Flutter Dashboard. Acts as a burst-prevention throttle.
- **[Completed]** **Content-Change Detection:** Each eligible frame is compared against the last saved frame using a **perceptual luma difference** on a 16×16 thumbnail. Frames are skipped when the screen has not changed meaningfully (e.g. user is idle on a chat), eliminating redundant storage writes.
- **[Completed]** **Configurable Sensitivity:** A **Change Sensitivity** slider (1–20%, default 3%) in the Flutter UI lets users tune how much visual change is required to trigger a save — low values capture subtle changes; high values capture only major screen transitions.
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
  - **Two-gate adaptive capture:**
    - **Gate 1 – Max Rate:** FPS-based throttle (0.1–5.0 FPS) caps the burst capture rate.
    - **Gate 2 – Visual Diff:** 16×16 perceptual-luma thumbnail diff skips redundant frames when screen is unchanged.
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
- **Change Detection:** A 16×16 RGBA8 thumbnail (~1 KB) of the last saved frame is kept in memory. The perceptual-luma mean absolute difference (MAD) is computed in ~256 integer operations per candidate frame — negligible CPU cost.
- **UserDefaults Keys:**
  - `capture_fps` — max capture rate (Double, 0.1–5.0)
  - `max_frames` — circular buffer size (Int, 30–10,000)
  - `capture_sensitivity` — change threshold as a fraction (Double, 0.01–0.20; default 0.03)

---

&copy; 2026 bluleap.ai / Veea Project
