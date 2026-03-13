# Loading Message Placeholder

This document describes when the **"Loading message..."** placeholder (with spinner) is shown in the channel chat UI.

## Where it comes from

The placeholder is the **fallback cell** produced by `LocalMessagesDataSource` in `MessageableChannelViewController`. The text and spinner are set in `createFallbackCell`:

- **File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
- **Method:** `createFallbackCell(tableView:indexPath:reason:)` (around line 1816)
- **Cell content:** `"Loading message..."` label + `UIActivityIndicatorView`

The table uses this fallback whenever it asks for a cell but the data source cannot provide a real message or system-message cell.

---

## When the placeholder is shown

### 1. Message ID in list but message not loaded (main case)

**Situation:** The channel’s message list already has a **message ID** for that row (`localMessages[indexPath.row]`), but the corresponding **message body** is not yet available.

**Lookup flow in `cellForRowAt`:**

1. Data source reads `messageId = localMessages[indexPath.row]`.
2. It looks up the `Message` in:
  - its own `messageCache`, then  
  - `viewState.messages[messageId]`.
3. If the message is in neither place, it cannot build a real cell and returns the fallback cell with **"Loading message..."**.

**Typical causes:**

- **Channel just opened:** Message IDs may be set (e.g. from cache or first API response), so the table is told there are N rows, but not all message bodies have been loaded into `ViewState` yet.
- **IDs ahead of content:** IDs are in sync (e.g. from cache or API) while full message payloads are still being fetched or applied to `ViewState`.

This is the case where many **"Loading message..."** rows appear: one placeholder per “known but not yet loaded” message.

**Code:** Same file, `cellForRowAt` (around lines 1726–1731), reason string: `"Message not found: \(messageId)"`.

---

### 2. Index out of bounds

**Situation:** The table requests a cell for a row index that is no longer valid (e.g. row ≥ `localMessages.count` or ≥ `lastReturnedRowCount`).

**Why it can happen:** Brief mismatch between the row count the table was given (`numberOfRowsInSection` returning `localMessages.count`) and the current state when `cellForRowAt` runs (e.g. list updated on another queue, or race during updates).

**Behaviour:** The data source returns the same fallback cell instead of crashing. User sees **"Loading message..."** for that row.

**Code:** Same file, `cellForRowAt` (around lines 1706–1715), reason: `"Index out of bounds"`.

---

### 3. Cell dequeue failures

**Situation:** The data source has a valid message and tries to dequeue a `SystemMessageCell` or `MessageCell`, but dequeue returns `nil` or the wrong type.

**Behaviour:** To avoid a crash, it returns the fallback cell. This is a rare failure path, not the normal “still loading” case.

**Code:** Same file, `cellForRowAt` (around lines 1738–1744 for system cell, 1752–1758 for message cell), reasons: `"System cell dequeue failed"` and `"Message cell dequeue failed"`.

---

## Summary


| Situation           | Cause                                      | User-visible result       |
| ------------------- | ------------------------------------------ | ------------------------- |
| Message not found   | ID in list, message not in ViewState/cache | Many loading placeholders |
| Index out of bounds | Row index invalid when cell is configured  | Placeholder for that row  |
| Dequeue failed      | System/Message cell dequeue failed         | Placeholder for that row  |


The **"Loading message..."** placeholder is shown when the chat UI has a message ID for that row but cannot yet (or ever, in error cases) resolve it to a `Message` and render a real message or system-message cell.

---

## Fix: Placeholders never resolving (indefinite "Loading message...")

### Actual issue

The chat UI sometimes shows many **"Loading message..."** placeholders and they **never** turn into real messages: the table is not refreshed after messages are loaded, and/or messages are never loaded for the IDs that are already in the list. So the user sees a permanent loading state instead of message content.

### Why it happens

Two main causes:

1. **Showing IDs without message bodies (memory-only path)**
  In `loadRegularMessages(forceFetchFromServer: false)` (e.g. after a nearby-API failure), when `viewState.channelMessages[channelId]` already has message IDs, the code takes the "memory-only" path: it sets `localMessages` to those IDs, creates the data source, and reloads the table **without checking** that `viewState.messages` actually contains the `Message` objects for those IDs. If the IDs were restored (e.g. from UserDefaults) or left over from a previous load but the message bodies were evicted (memory cleanup) or never loaded, the table shows one row per ID and `cellForRowAt` finds no message → fallback cell → "Loading message...". In this path the code **never** calls the API, so placeholders never resolve.
   **File:** `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`  
   **Location:** The branch that uses `existingMessages` from `viewModel.viewState.channelMessages[channelId]` when `shouldUseMemoryOnly` is true (around lines 454–528). It sets `localMessages = messagesCopy` and reloads the table without verifying that `viewModel.viewState.messages` contains entries for those IDs.
2. **refreshMessages() returns before checking for missing messages**
  In `refreshMessages()`, the guard that returns early is:
   So when `localMessages` already equals `channelMessages` (e.g. after sync elsewhere), the method returns **before** checking whether `viewState.messages` actually has the message bodies for those IDs. If we have IDs in both but no bodies (e.g. after memory cleanup), no one triggers `loadInitialMessages()`, and placeholders stay forever.
   **File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`  
   **Location:** `refreshMessages(forceUpdate:)` (around lines 1478–1483). The "only IDs, no actual messages" handling (and the call to `loadInitialMessages()`) lives **after** this guard, so it never runs when the lists are already in sync.
3. **No reactive reload when a missing message appears**
  When `LocalMessagesDataSource` returns a fallback cell for "message not found", it does not notify the view controller to load missing messages or to reload the table when `viewState.messages` is later updated. So even if messages are loaded elsewhere, the table is not refreshed and placeholders remain until some other code path triggers a reload.

### What should be done to fix it

- **Ensure we never show a table with IDs we can’t resolve:** Before using the "memory-only" path in `loadRegularMessages`, verify that (enough) message IDs have corresponding entries in `viewState.messages`. If  fetch from the server (onot, do not use memory-only;r cache) and then show the table.
- **Always run the "IDs but no messages" logic in refreshMessages:** In `refreshMessages()`, run the check for "we have channel message IDs but no actual message objects" **before** the guard that returns when `localMessages == channelMessages`, and trigger `loadInitialMessages()` when that’s the case so placeholders eventually resolve.
- **Optional: resolve placeholders when messages arrive:** When the data source shows a "message not found" fallback, trigger a load for the channel (or for missing IDs) and, when messages are in `viewState.messages`, reload the table (or the affected rows) so those placeholders are replaced by real cells.

### Step-by-step implementation

#### Step 1: Fix the memory-only path in `loadRegularMessages`

**File:** `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`

**Current behaviour:** When `existingMessages` (IDs) exist and `shouldUseMemoryOnly` is true, the code sets `localMessages = messagesCopy` and reloads the table without checking `viewState.messages`.

**Change:** Before using the in-memory list, verify that at least one (or a majority of) the IDs have a corresponding entry in `viewModel.viewState.messages`. If not, do **not** use the memory-only branch; fall through to the "No messages in memory, fetch from server" path so the API (or cache) is used and message bodies are loaded before the table is shown.

**Code to replace** (conceptually — the exact condition can be tuned):

Find the block that starts with:

```swift
if let existingMessages = viewModel.viewState.channelMessages[channelId],
   !existingMessages.isEmpty,
   shouldUseMemoryOnly
{
    // CRITICAL FIX: Create an explicit copy to avoid reference issues
    let messagesCopy = Array(existingMessages)

    // Update our local messages array directly
    self.localMessages = messagesCopy
    // ... rest of branch that creates data source and reloads
}
```

**Replace with:** Add a check that message bodies exist before using the memory-only path. If they don’t, skip this branch and let the code fall through to the API fetch.

**Code to add (logic):**

```swift
if let existingMessages = viewModel.viewState.channelMessages[channelId],
   !existingMessages.isEmpty,
   shouldUseMemoryOnly
{
    // CRITICAL FIX: Only use memory path if we actually have message bodies for these IDs.
    // Otherwise we'd show "Loading message..." forever (IDs in list but no Message in viewState).
    let hasEnoughMessageBodies = existingMessages.contains { viewModel.viewState.messages[$0] != nil }
    if hasEnoughMessageBodies {
        // Existing memory-only branch: messagesCopy, localMessages, data source, reloadData(), etc.
        let messagesCopy = Array(existingMessages)
        self.localMessages = messagesCopy
        // ... rest of current block (DispatchQueue.main.async { ... })
    }
    // If !hasEnoughMessageBodies, fall through to the else branch below (fetch from server)
}
```

So: keep the existing `if let existingMessages ... shouldUseMemoryOnly` and its closing brace, but **inside** it add the `hasEnoughMessageBodies` check and only run the "update localMessages and reload table" logic when it’s true; otherwise do nothing in this branch so execution continues to the `else { ... fetch from server }` path.

**Reason:** This prevents the table from ever showing rows for IDs that don’t have `Message` objects in `viewState.messages`, which is what causes indefinite "Loading message..." placeholders in this path.

---

#### Step 2: Check "IDs but no messages" before the list-equality guard in `refreshMessages`

**File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Current behaviour:** The method returns when `channelMessages` is nil/empty or when `localMessages == channelMessages`, so the "only message IDs, no actual messages" block (which calls `loadInitialMessages()`) is never reached when the two lists are already in sync.

**Change:** After ensuring `channelMessages` is non-nil and non-empty, **immediately** check whether there are any actual message objects in `viewState.messages` for those IDs. If there are only IDs and no (or almost no) message bodies, trigger `loadInitialMessages()` and return, **without** requiring `localMessages != channelMessages`.

**Code to replace:**

Current pattern (simplified):

```swift
// Get new messages directly - no async overhead
guard let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
    !channelMessages.isEmpty,
    localMessages != channelMessages
else { return }

// CRITICAL: Check if actual message objects exist before refreshing
let hasActualMessages =
    channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
if !hasActualMessages {
    // ... loadInitialMessages() ...
    return
}
```

**Replace with:** Run the "we have IDs but no messages" logic as soon as we have non-empty `channelMessages`, and only use the `localMessages != channelMessages` guard for the **normal** sync path (where we update localMessages and reload).

**Code to add / reorder:**

1. Keep the guard that ensures `channelMessages` exists and is non-empty (so we have something to refresh).
2. **Before** any guard that returns on `localMessages == channelMessages`, add:
  - Compute `hasActualMessages` as above (at least one ID has a corresponding `viewState.messages[id]`).
  - If `!hasActualMessages`, run the existing block that hides the table, shows the spinner, and starts `Task { await loadInitialMessages() }`, then `return`.
3. **Then** for the normal refresh path (update data source and reload), guard on `localMessages != channelMessages` so we only update and reload when the list actually changed.

**Reason:** This way, whenever the channel has message IDs but no (or insufficient) message bodies, we trigger a load and eventually replace placeholders with real messages, even when `localMessages` was already synced to `channelMessages` (e.g. after memory cleanup or restore).

---

#### Step 3 (optional): Trigger load and reload when the data source hits "message not found"

**File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` (and optionally the data source type)

**Idea:** When `LocalMessagesDataSource` creates a fallback cell for reason "Message not found: messageId)", notify the view controller so it can:

1. Trigger a load for the current channel (e.g. call `loadInitialMessages()` or a dedicated "load missing messages for this channel" method).
2. When the load completes and `viewState.messages` is updated, reload the table (or the visible rows) so `cellForRowAt` runs again and returns real message cells instead of placeholders.

**Implementation outline:**

- Add a weak reference from the data source to the view controller (already exists as `viewControllerRef`).  
- Add a method on the view controller, e.g. `onMissingMessageDetected(messageId: String)` or `onMissingMessagesDetected()`, that starts a load for the channel and, on completion (e.g. on MainActor after API/cache work), calls `tableView.reloadData()` or reloads the relevant index paths.  
- In `cellForRowAt`, when returning the fallback cell for "message not found", call that method (e.g. `viewControllerRef?.onMissingMessageDetected(messageId: messageId)`).  
- To avoid duplicate work, guard the load (e.g. with a flag or debounce) so we don’t fire many loads when many rows are missing at once.

**Reason:** This makes the UI self-correcting: as soon as we show a "Loading message..." because of a missing message, we trigger a load and a subsequent reload so that placeholder is replaced once the message is in `viewState.messages`.

---

### Summary


| Root cause                                                        | Fix                                                                                                                                                                                                            |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Memory-only path shows table with IDs that have no message bodies | In `loadRegularMessages`, only use the memory-only branch when `viewState.messages` contains entries for (enough of) those IDs; otherwise fetch from server.                                                   |
| refreshMessages() returns before "IDs but no messages" check      | In `refreshMessages()`, check for "channel has IDs but no message bodies" **before** the guard that returns when `localMessages == channelMessages`, and trigger `loadInitialMessages()` when that’s the case. |
| No reload when missing messages are later loaded                  | (Optional) When the data source returns a "message not found" fallback, call a view controller method that triggers a channel load and then reloads the table when messages are available.                     |


Implementing Step 1 and Step 2 removes the main causes of indefinite "Loading message..." placeholders; Step 3 improves robustness when messages are loaded asynchronously or after the fact.