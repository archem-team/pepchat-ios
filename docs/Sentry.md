# Sentry Crash Report Analysis

This document explains Sentry crash reports affecting the Revolt iOS app.

---

## Critical Issues Summary (Root Causes of Crashes)

| Issue | Root cause | Critical? |
|-------|------------|-----------|
| **EXC_BREAKPOINT (Issue 9fd0c5e1)** | Unsafe memory access in `swift_arrayDestroy` triggered by concurrent state changes during/after server deletion. | **Yes** — Fatal crash in production. |
| **NSRangeException (Report 1)** | Scroll to invalid table view row after data source cleared during navigation. | **Yes** — Unhandled crash. |
| **EXC_BREAKPOINT (Report 2, 41ebdb19)** | Invalid state during SwiftUI animation/gesture (force unwrap or precondition). | **Yes** — Unhandled crash. |
| **SIGABRT (memory allocation failure)** | App failed to allocate memory (~3 MB); indicates memory exhaustion or leak. | **Yes** — Fatal OOM-style crash. |
| **WatchdogTermination** | OS killed app for overusing RAM. | **Yes** — Root cause of app termination. |
| **App Hanging** | Long work on main thread (e.g. MessageOptionViewController, updateTableViewBouncing). | No — Performance issue; can lead to Watchdog if severe. |
| **HTTP 500 / 503** | Server or network errors; not an app crash. | No — Operational/backend. |

The **single most actionable crash** from the report set you provided is **Issue 9fd0c5e1 (EXC_BREAKPOINT during server deletion)** — see Report 3 below.

---

## Report 1: NSRangeException (UITableView out-of-bounds scroll)

> **Issue ID:** `8cec212e`  
> **Project:** PEPCHAT-IOS-3C / Revolt  
> **Last Seen:** ~13 hours ago (at time of report)

### Overview

The app crashes when attempting to scroll a `UITableView` to a row that does not exist.

---

### The Crash

#### Error Details

| Field | Value |
|-------|-------|
| **Exception Type** | `NSRangeException` |
| **Handled** | No (unhandled — app terminates) |
| **Mechanism** | `nsexception` |
| **Signal** | `SIGABRT` (code 8), `EXC_CRASH` |

#### Error Message

```
Attempted to scroll the table view to an out-of-bounds row (50) when there are only 0 rows in section 0.
```

#### Critical Detail

The `UITableView` involved had **`dataSource: (null)`** at crash time. This means:

- The table view had no data source (it was `nil`)
- The table reports 0 rows in section 0
- Code attempted to scroll to row 50 — a row that does not exist
- The mismatch causes an `NSRangeException` and the app crashes

---

### Environment (When the Crash Occurred)

| Context | Details |
|---------|---------|
| **App** | Revolt, version 1.0.1 (build 7) |
| **Device** | iPhone 11 (N104AP) |
| **OS** | iOS 18.6.2 (build 22G100) |
| **Environment** | Production |
| **Simulator** | No (real device) |
| **User Location** | Los Angeles, United States |
| **Free Memory** | 72.4 MiB |
| **Total Memory** | 3.8 GiB |

---

### Breadcrumbs (Events Leading to the Crash)

Chronological order of events before the crash:

1. **HTTP POST** — `https://peptide.chat/api/channels/.../messages`  
   - Status: 200 OK  
   - A message was successfully sent.

2. **HTTP PUT** — `https://peptide.chat/api/channels/.../ack/...`  
   - Status: 204 No Content  
   - Read receipt / acknowledgment was sent.

3. **Device Event** — `UIKeyboardDidHideNotification`  
   - The keyboard was hidden.

4. **Touch Event** — `backButtonTapped`  
   - The user tapped the back button to leave the screen.

5. **Exception** — `NSRangeException`  
   - Crash occurs immediately after the back tap.

---

### Root Cause Analysis

#### What Happened

1. User was in a channel view (messages table).
2. User sent a message (POST succeeded) and the app acknowledged it (PUT succeeded).
3. Keyboard was dismissed.
4. User tapped the back button to leave the channel.
5. During or right after the back navigation, code attempted to scroll the table to **row 50**.
6. At that moment, the table had **0 rows** and **`dataSource: (null)`**.
7. The invalid scroll caused an `NSRangeException` and the app crashed.

#### Likely Cause

**Sentry's AI (Seer) suggestion:**  
> "The view controller likely tried to scroll after data refresh when the section count was zero."

**Interpretation:**

- **Race condition during teardown:** The back button triggers dismissal. While the view controller or its table is being torn down, something still tries to scroll (e.g. a delayed `scrollToRow`, scroll position restore, or `scrollToTargetMessage`).
- **Data source cleared before scroll:** The table’s `dataSource` is set to `nil` (or the object is deallocated) during navigation, so `numberOfRows(inSection:)` returns 0. A pending scroll operation still runs and uses an old index (50), leading to the crash.
- **Async work firing too late:** A `DispatchWorkItem` or `asyncAfter` for scroll-to-position or scroll-to-target may execute after the view controller has started deallocating, so it scrolls a table that no longer has a valid data source.

#### Relevant Code Areas

Potential sources of the scroll-to-row call:

- `ScrollPositionManager` — `scrollToBottom()`, `restoreScrollPositionToAnchor()`
- `MessageableChannelViewController` — `scrollToTargetMessage()`, `scrollToBottomLegacy()`
- `MessageableChannelViewController+ScrollView` — `scrollToBottom()`
- `MessageableChannelViewController+TargetMessage` — `scrollToRow(at:at:animated:)`
- `MessageableChannelViewController+TableBouncing` — `scrollToRow(at:at:animated:)`

---

### Recommendations

1. **Cancel all scroll work on view disappear / dealloc**
   - Cancel `scrollToBottomWorkItem` and any similar `DispatchWorkItem`s in `viewWillDisappear` or `dealloc`.
   - Ensure no scroll logic runs after the view controller starts being deallocated.

2. **Guard scroll operations**
   - Before any `scrollToRow(at:at:animated:)`:
     - Check `tableView.dataSource != nil`
     - Check `numberOfRows(inSection:)` and that the target row index is valid
   - Add early returns when the view controller or table is in an invalid state.

3. **Avoid scroll during navigation**
   - In `viewWillDisappear`, set a flag (e.g. `isBeingDismissed`) and skip all scroll operations if that flag is set.
   - Ensure scroll position restore and `scrollToTargetMessage` do not run once the user has navigated away.

4. **Use weak references**
   - Ensure closures and `DispatchWorkItem`s hold weak references to the view controller and table view, so they no-op when the controller is deallocated.

---

### Sentry Report Navigation

When viewing this issue in Sentry:

| Tab | Purpose |
|-----|---------|
| **Highlights** | Key attributes (handled, level, trace ID) |
| **Stack Trace** | Call stack leading to the crash |
| **Breadcrumbs** | Chronological events before the crash |
| **Trace** | Performance trace for the session |
| **Contexts** | User, device, OS, app metadata |

---

### Issue Stats (from Report)

- **Events (total):** 6  
- **Users (90d):** 6  
- **First seen:** 2 months ago (release 0.0.26)  
- **Last seen:** 12 hours ago (release 1.0.1)  
- **Status:** Ongoing

---

## Report 2: EXC_BREAKPOINT (SwiftUI animation / invalid state)

> **Issue ID:** `41ebdb19`  
> **Project:** PEPCHAT-IOS-3P / Revolt  
> **Last Seen:** ~10 hours ago (at time of report)

### Overview

The app crashes with an `EXC_BREAKPOINT` exception. Sentry indicates a **Processing Error** due to missing dSYM files, which limits symbolication of the stack trace. The crash is associated with a multi-tap gesture and keyboard interaction in a SwiftUI context.

---

### The Crash

#### Error Details

| Field | Value |
|-------|-------|
| **Exception Type** | `EXC_BREAKPOINT` |
| **Details** | Exception 6, Code 1, Subcode 4309541356 |
| **Handled** | No (unhandled — app terminates) |
| **Mechanism** | `mach` (Mach kernel trap) |
| **Signal** | `SIGTRAP` (0) |

#### What EXC_BREAKPOINT Means

`EXC_BREAKPOINT` is typically triggered by:

- **Assertion failures** (`assert()`, `assertionFailure()`)
- **Force unwrap of `nil`** (e.g. `value!` when `value` is `nil`)
- **Precondition failures** (`preconditionFailure()`)
- **`fatalError()`** or similar runtime traps
- Swift runtime traps for illegal state (e.g. invalid enum, array index out of bounds in certain cases)

---

### Processing Error: Missing dSYM Files

Sentry reports:

> **"A required debug information file was missing"**

| Detail | Value |
|--------|-------|
| **File** | `Revolt` (app binary) |
| **Debug ID** | `820e24d2-2a06-35c6-a074-5177848ec2a9` |
| **Path** | `/private/var/containers/Bundle/Application/.../Revolt.app/` |

**Images with missing symbolication:**

- `Revolt` (main app)
- `Foundation`
- `CoreFoundation`
- `UIKitCore`

Without dSYMs, Sentry cannot convert memory addresses into readable function names and line numbers, making the stack trace harder to interpret. The CI script (`ci_scripts/ci_post_xcodebuild.sh`) uploads dSYMs for this project; ensure it runs for the `PEPCHAT-IOS-3P` project and that the correct `SENTRY_AUTH_TOKEN` and org/project are configured.

---

### Environment (When the Crash Occurred)

| Context | Details |
|---------|---------|
| **App** | Revolt, version 1.0.1 (build 7) |
| **Device** | iPhone 13 Pro (D63AP) |
| **OS** | iOS 26.2.1 (build 23C71) |
| **Environment** | Production |
| **Simulator** | No (real device) |
| **User Location** | Albuquerque, United States |
| **Free Memory** | 968.4 MiB |
| **Total Memory** | 5.5 GiB |
| **Trace ID** | `b79609c13e72466d8a2de0ba34ea9b7b` |

---

### Breadcrumbs (Events Leading to the Crash)

Chronological order of events before the crash:

1. **Device Event** — `UIKeyboardDidShowNotification`  
   - The on-screen keyboard was shown (appeared twice in quick succession).

2. **Touch Event** — `_handleMultiTapGesture:`  
   - A multi-tap gesture was detected (~7 seconds before crash).

3. **UI Lifecycle** — 7 lifecycle items (collapsed in report).

4. **Exception** — `EXC_BREAKPOINT`  
   - Crash occurs.

---

### Root Cause Analysis

#### What Happened

1. User interacted with the app; keyboard was shown.
2. User performed a multi-tap gesture.
3. Shortly after, the app hit an `EXC_BREAKPOINT` and crashed.

#### Likely Cause

**Sentry's AI (Seer) suggestion:**  
> "The breakpoint likely stems from an invalid state change during a SwiftUI animation or transaction."

**Interpretation:**

- **SwiftUI state inconsistency:** A state update during or after a SwiftUI animation may have produced an invalid view hierarchy or data binding.
- **Force unwrap / precondition:** Code may force-unwrap an optional or hit a precondition when the keyboard or multi-tap changes state.
- **Animation / transaction conflict:** Concurrent SwiftUI animations or transactions could leave the view in an invalid state.
- **Multi-tap handling:** The `_handleMultiTapGesture` handler (or related logic) might trigger a state change that leads to a trapped condition.

#### Relevant Code Areas

Potential areas to investigate (files with `onTapGesture` and keyboard-related UI):

- `MessageView.swift` — Message taps
- `MessageableChannel.swift` — Channel message input, keyboard
- `UserSheet.swift` — User profile taps
- `MessageReply.swift`, `MessageReactions.swift`, `MessageAttachment.swift` — Message interaction
- `ProfileSettings.swift`, `UserSettings.swift` — Settings with photo pickers
- `EmojiPicker.swift` — Emoji selection (keyboard context)
- SwiftUI views that show/hide the keyboard and update state in response
- Force unwraps (`!`), `fatalError`, or `preconditionFailure` near keyboard or gesture code
- SwiftUI `withAnimation` or `Transaction` usage that could race with state updates

---

### Recommendations

1. **Upload dSYMs for PEPCHAT-IOS-3P**
   - Ensure `ci_scripts/ci_post_xcodebuild.sh` runs for this project and uploads dSYMs to the correct Sentry org/project.
   - Verify `SENTRY_AUTH_TOKEN` and org/project settings. The script currently uses `-o revolt -p apple-ios`; PEPCHAT-IOS-3P may need different configuration.

2. **Locate force unwraps and assertions**
   - Search for `!`, `fatalError`, `preconditionFailure`, and `assert` in SwiftUI views, especially those tied to keyboard or gesture handling.

3. **Add defensive checks around gestures**
   - Ensure multi-tap handlers validate state before use (e.g. optional binding instead of force unwrap).
   - Consider wrapping risky state updates in `Task { @MainActor in ... }` to avoid timing issues.

4. **Reproduce locally**
   - Try to reproduce by focusing on screens where the keyboard is shown and the user can perform multi-tap (e.g. message input, settings, profile).

---

### Issue Stats (from Report)

- **Events (total):** 49  
- **Users (90d):** 30  
- **First seen:** 24 days ago (release 1.0.0)  
- **Last seen:** 10 hours ago (release 1.0.1)  
- **Status:** Ongoing  
- **Attachments:** 49

---

## Report 3: EXC_BREAKPOINT — swift_arrayDestroy during server deletion (critical)

> **Issue ID:** `9fd0c5e1`  
> **Project:** PEPCHAT-IOS-3D / Revolt  
> **Last Seen:** a day ago (at time of report)

### Overview

The app crashes with a **fatal** `EXC_BREAKPOINT` in **`swift_arrayDestroy`**. Sentry’s trace and breadcrumbs show this occurs in the context of **server deletion**: multiple `DELETE` requests to the same server, with one success (204) and subsequent HTTP errors. Sentry Seer’s initial guess: *"The breakpoint likely stems from an unsafe memory access during array destruction in SwiftUI/Core, possibly triggered by concurrent state changes after failed server deletions."*

This is a **critical, root-cause crash**: the app terminates in production (13 events, 13 users; high priority).

---

### The Crash

#### Error Details

| Field | Value |
|-------|--------|
| **Exception Type** | `EXC_BREAKPOINT` |
| **Details** | Exception 6, Code 1, Subcode 7894682656 |
| **Trace** | **Fatal — EXC_BREAKPOINT swift_arrayDestroy** |
| **Handled** | No (unhandled — app terminates) |
| **Mechanism** | `mach` |
| **Level** | Fatal |
| **Environment** | Production (e.g. release 1.0.1 (7), iOS 26.2.1, iPhone 17 Pro Max) |

#### What This Means

- **`swift_arrayDestroy`** is part of the Swift runtime. A breakpoint here usually means the runtime is tearing down a Swift `Array` that is in an **invalid state** (e.g. double-free, use-after-free, or the array’s storage was corrupted by concurrent mutation).
- **Grouping** points to **`function App.main`** — the crash surfaces on the main thread, likely when SwiftUI or app code reacts to state changes (e.g. `ViewState.servers` or derived arrays).

---

### Processing Error: Missing dSYM

Sentry reports **"A required debug information file was missing"** for the `Revolt` app binary (Debug ID: `820e24d2-2a06-35c6-a074-5177848ec2a9`). As a result, the stack is not fully symbolicated and the **exact line** inside the app cannot be read from this report. The **root cause** is still clear from breadcrumbs, trace label, and Seer: server-deletion flow → concurrent state changes → invalid array → crash in `swift_arrayDestroy`.

---

### Breadcrumbs (Events Leading to the Crash)

Chronological context:

1. **HTTP DELETE** — `https://peptide.chat/api/servers/01KE771KP49EJYNWF3NANXNZMX`  
   - At least one request returns **204 No Content** (success).

2. **HTTP error** — Same `DELETE` endpoint, same server ID, logged as **HTTP error** (e.g. no content or already deleted).  
   - Suggests **repeated or concurrent** delete calls (e.g. double-tap, retry, or WebSocket + UI both reacting).

3. **Exception** — `EXC_BREAKPOINT: Exception 6, Code 1, Subcode 7894682656`  
   - Crash occurs in this flow.

So: the app successfully deletes the server once, but other delete attempts or events still run. State (e.g. `ViewState.servers`, or arrays derived from it for SwiftUI) is updated from more than one place and can be mutated while being read or destroyed, leading to the crash in `swift_arrayDestroy`.

---

### Root Cause Analysis

#### What Happened

1. User (or system) triggers server deletion (e.g. from `DeleteServerSheet`).
2. One `DELETE` call succeeds (204); `DeleteServerSheet` calls `viewState.removeServer(with: server.id)` and dismisses the sheet.
3. Either:
   - Another `DELETE` is in flight or retried (e.g. double-tap, or duplicate request), and fails (server already gone), or  
   - WebSocket delivers a `server_delete` event; `ViewState+WebSocketEvents` handles it and schedules `servers.removeValue(forKey: e.id)` on the main queue after 0.75 s.
4. **Concurrent state changes**: `servers` (and any arrays built from it, e.g. for `ForEach` or navigation) are modified from:
   - The success path in `DeleteServerSheet` (main thread), and  
   - The delayed WebSocket handler (main thread, 0.75 s later), and/or  
   - Other code still holding or iterating over server/channel lists.
5. A Swift `Array` (or storage used by SwiftUI/App) ends up in an invalid state; when the runtime destroys it, **`swift_arrayDestroy`** hits an `EXC_BREAKPOINT` and the app crashes.

#### Likely Cause (summary)

**Root cause:** **Concurrent or overlapping updates to server state during/after server deletion**, leading to **invalid Swift array state** and a **fatal crash in `swift_arrayDestroy`** (and surfaced in `App.main` on the main thread).

---

### Relevant Code Areas

- **`Revolt/Components/Sheets/DeleteServerSheet.swift`** — Calls `viewState.http.deleteServer(...)` then on success `viewState.removeServer(with: server.id)` and toggles sheets. No guard against double submission or duplicate DELETE.
- **`Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`** — `case .server_delete(let e)`: updates selection/path, then `DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { self.servers.removeValue(forKey: e.id) }`. Overlaps with immediate removal in `DeleteServerSheet`.
- **`Revolt/ViewState+Extensions/ViewState+DMChannel.swift`** — `removeServer(with:)` only does `servers.removeValue(forKey: serverID)`; no coordination with WebSocket handler.
- **`Revolt/RevoltApp.swift`** — Many `viewState.servers[id]` bindings and navigation; when `servers` is mutated during deletion, SwiftUI may be iterating over arrays derived from this state.

---

### Recommendations

1. **Avoid duplicate server removal**
   - In `DeleteServerSheet`, disable the Delete/Leave button after first tap (e.g. `@State private var isDeleting = false`) and set it true when the task starts; only call `removeServer` once on first success.
   - In `ViewState`, make server removal **idempotent**: e.g. in `removeServer(with:)` and in the `server_delete` WebSocket handler, check `servers[serverID] != nil` before removing, and perform removal on the main actor in a single, serialized way.

2. **Single source of truth for “server deleted”**
   - Prefer either:
     - **UI-initiated delete:** On 204, call `removeServer` and **do not** rely on a later WebSocket `server_delete` for the same server for UI state; or  
     - **WebSocket-driven:** On `server_delete`, remove server and update UI; UI only calls API and does not remove from state (backend is source of truth).  
   - Avoid both UI and WebSocket independently removing the same server at different times without coordination.

3. **Remove or shorten the delayed removal in WebSocket**
   - The `asyncAfter(deadline: .now() + 0.75)` in `server_delete` increases the window where the same server can be removed twice (once from UI, once from WebSocket). Consider removing the delay and removing the server immediately on `server_delete`, or ensure only one code path removes the server for a given delete event.

4. **Upload dSYMs for this project**
   - Ensure dSYMs for the Revolt app are uploaded to Sentry for the project that receives this issue (e.g. PEPCHAT-IOS-3D). That will allow the exact line and function for `App.main` / `swift_arrayDestroy` to be identified in future occurrences.

---

### Issue Stats (from Report)

- **Events (total):** 13  
- **Users (90d):** 13  
- **Releases affected:** 1.0.1 (7), 0.0.27 (0.0.27)  
- **Status:** High priority, fatal, production  
- **Trace ID (example):** `4184c3aac9064cf5a245564b1de3dc77`
