# Deleted message still shown after app reopen (cache reconciliation)

## Problem

When User A has messages cached for a channel, quits the app, and then another user (User B) deletes one of those messages on the server, User A still sees the deleted message after reopening the app and opening the channel. The deleted message continues to appear in the UI even though it no longer exists on the server.

## Root cause

1. **When the app is running**, message deletion is handled correctly:
   - The WebSocket receives a `message_delete` event (`ViewState+WebSocketEvents.swift`).
   - ViewState updates `deletedMessageIds[channel]` and removes the ID from `channelMessages`.
   - `MessageCacheWriter.shared.enqueueDeleteMessage(...)` is called, so the SQLite cache gets a **tombstone** for that message (`MessageCacheManager` tombstones table).

2. **When the app was closed** at the time of deletion:
   - User A never receives the `message_delete` WebSocket event.
   - `deletedMessageIds` is in-memory only and is not persisted across app restarts.
   - No tombstone is written for the deleted message in the local cache.

3. **When User A reopens the app and opens the channel**:
   - `loadInitialMessages()` first shows messages from the local cache (`MessageableChannelViewController+MessageLoading.swift`). The cache load already excludes tombstones (`MessageCacheManager` uses `AND id NOT IN (SELECT message_id FROM tombstones ...)`), but there is no tombstone for the message deleted by User B.
   - Later, `loadRegularMessages(forceFetchFromServer: true)` runs and fetches the latest page from the API. The code **merged** existing IDs (from cache) with API IDs via `mergeAndSortMessageIds(existing: new:)` and then filtered by `deletedMessageIds`. So it took the **union** of cache + API and never treated “in cache but not on server” as deleted. The deleted message therefore remained in the list.

So the bug had two parts: (1) deletes that happened while the app was closed never produced a tombstone, and (2) the first API response after opening the channel was not used to infer server-side deletes and update both in-memory state and cache.

## Fix (reconcile with server after fetch)

Use the first API response when opening a channel as the source of truth for that page’s time window: any message ID we had locally (e.g. from cache) in that same time window but **not** in the API response is treated as deleted. We then update `deletedMessageIds` and write a tombstone via `MessageCacheWriter.shared.enqueueDeleteMessage(...)` so the message disappears from the UI and from future cache reads.

To avoid false positives (e.g. marking old cached messages as “deleted” when they are simply outside the API’s first page), reconciliation is limited to the **same time window** as the API response:

- Compute the oldest timestamp among the message IDs returned by the API for that page.
- Consider only existing (e.g. cached) IDs whose timestamp is at least that old and that are not in the API response. Those IDs are treated as deleted by the server.

## Code changes

### File: `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`

**Location:** Inside `loadRegularMessages`, in the block that processes a successful `fetchResult` (regular message fetch from the server), immediately after computing `existingIds` and `apiIds`, and **before** computing `sortedIds` and `filteredIds`.

**Change:** Insert a reconciliation step that:

1. Computes the oldest timestamp in the API response: `oldestApiTimestamp = apiIds.map { createdAt(id: $0) }.min() ?? .distantPast` (using the global `createdAt(id:)` from `Revolt/Api/Utils.swift`).
2. Builds the set of message IDs that we had locally (e.g. from cache) in that same time window but that the server did not return: `deletedByServer = existingIds.filter { createdAt(id: $0) >= oldestApiTimestamp && !apiIdSet.contains($0) }`.
3. For each ID in `deletedByServer`, adds it to `viewModel.viewState.deletedMessageIds[channelId]` and calls `MessageCacheWriter.shared.enqueueDeleteMessage(id:channelId:userId:baseURL:)` (using the same `userId` and `baseURL` as for other cache writes in that flow).

The existing logic that builds `sortedIds` and `filteredIds` using `deletedMessageIds` then automatically excludes these reconciled IDs, so the UI no longer shows them. Future cache reads also exclude them because tombstones were written.

**Exact insertion (after the two lines that set `existingIds` and `apiIds`, before the line that sets `sortedIds`):**

```swift
// Reconcile with server: messages we had locally (e.g. from cache) in the same time window as the API page but not returned by the API are treated as deleted (e.g. another user deleted while app was closed). Update ViewState and cache so they disappear from UI and future cache reads.
let oldestApiTimestamp = apiIds.map { createdAt(id: $0) }.min() ?? .distantPast
let apiIdSet = Set(apiIds)
let deletedByServer = existingIds.filter { createdAt(id: $0) >= oldestApiTimestamp && !apiIdSet.contains($0) }
if !deletedByServer.isEmpty, let userId = viewModel.viewState.currentUser?.id, let baseURL = viewModel.viewState.baseURL {
    await MainActor.run {
        for id in deletedByServer {
            self.viewModel.viewState.deletedMessageIds[channelId, default: Set()].insert(id)
            MessageCacheWriter.shared.enqueueDeleteMessage(id: id, channelId: channelId, userId: userId, baseURL: baseURL)
        }
    }
}
```

No other files were changed. The fix is localized to the initial load path that merges cache with the first API fetch when opening a channel.

## Related code (unchanged)

- **WebSocket delete handling:** `ViewState+Extensions/ViewState+WebSocketEvents.swift` — `case .message_delete(let e):` updates `deletedMessageIds`, `channelMessages`, and calls `MessageCacheWriter.shared.enqueueDeleteMessage(...)`.
- **Cache tombstones:** `Revolt/1Storage/MessageCacheManager.swift` — `tombstones` table and `_getDeletedMessageIds` / `_loadCachedMessages` exclude tombstoned IDs.
- **Cache writes:** `Revolt/1Storage/MessageCacheWriter.swift` — `enqueueDeleteMessage` enqueues a tombstone write for the current session.
- **ViewState:** `Revolt/ViewState.swift` — `deletedMessageIds: [String: Set<String>]` (channel ID → set of deleted message IDs).

## Summary

- **Problem:** A message deleted by another user while the app was closed still appeared after reopen because the local cache had no tombstone and the merge step did not infer deletes from the API response.
- **Fix:** When the first API page is received after opening a channel, treat the API as the source of truth for that time window; mark as deleted (and tombstone) any message we had in that window that the API did not return. This removes the message from the UI and from future cache reads.

---

# Local delete not reflected in UI instantly

## Problem

When User A deletes a message (their own or one they have permission to delete), the delete API call succeeds and the message is removed on the server, but the message list UI does not update immediately—the deleted message still appears until something else triggers a refresh.

## Root cause

The message list is driven by **UIKit** (`MessageableChannelViewController` + `LocalMessagesDataSource`). The table view uses a **local copy** of message IDs (`localMessages` on the VC and inside the data source). When a message is deleted:

1. **ViewState** is updated correctly: `deletedMessageIds`, `channelMessages`, and `messages` are updated in both delete paths (`RepliesManager` and `MessageContentsView`).
2. The **view controller’s** `localMessages` and the **data source’s** copy were never updated, and the table was never told to reload. So the UI kept showing the old list.

Additionally, in `RepliesManager` the ViewState updates were done inside a nested `Task { }`, so they ran asynchronously and the table had no refresh call at all.

## Fix (refresh table after local delete)

1. **`MessageableChannelViewController`**  
   Add a method `refreshMessagesAfterLocalDelete()` that:
   - Calls `syncLocalMessagesWithViewState()` so `localMessages` is updated from `viewState.channelMessages`.
   - Updates the data source with `(dataSource as? LocalMessagesDataSource)?.updateMessages(localMessages)`.
   - Calls `tableView.reloadData()` and `updateTableViewBouncing()`.

2. **`RepliesManager`** (context-menu delete from `MessageCell`):  
   On delete success, update ViewState **synchronously** (no nested `Task`): update `deletedMessageIds`, enqueue tombstone, remove from `messages` and `channelMessages`. Then call `viewController?.refreshMessagesAfterLocalDelete()` so the table refreshes immediately.

3. **`MessageContentsView`** (SwiftUI delete path):  
   ViewState is already updated in `delete()`. Post a notification `MessageDeletedLocally` with `userInfo: ["channelId": channel.id]`. The view controller observes this notification and, if `viewModel.channel.id == channelId`, calls `refreshMessagesAfterLocalDelete()`. That way, if the user deletes from the SwiftUI message sheet while the UIKit channel screen is visible, the list still updates.

## Code changes (instant UI update)

### 1. `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

- **New method** (before `syncLocalMessagesWithViewState()`):
  - `refreshMessagesAfterLocalDelete()`: syncs `localMessages` from ViewState, updates the data source’s message list, reloads the table, and updates bouncing.

- **New notification observer** (in the same `viewDidLoad` block as other observers):
  - Observe `NSNotification.Name("MessageDeletedLocally")` and call `handleMessageDeletedLocally(_:)`.

- **New selector** `handleMessageDeletedLocally(_:)`:  
  Read `channelId` from `notification.userInfo`. If it equals `viewModel.channel.id`, call `refreshMessagesAfterLocalDelete()`.

### 2. `Revolt/Pages/Channel/Messagable/Managers/RepliesManager.swift`

- In the `.success` branch of the delete API result: remove the inner `Task { }`. Update `viewState.messages` and `viewState.channelMessages[channelId]` synchronously in the same `MainActor.run` block. Then call `viewController?.refreshMessagesAfterLocalDelete()`.

### 3. `Revolt/Components/MessageRenderer/MessageContentsView.swift`

- In `MessageContentsViewModel.delete()`, after updating ViewState on success, post:
  - `NotificationCenter.default.post(name: NSNotification.Name("MessageDeletedLocally"), object: nil, userInfo: ["channelId": channel.id])`.

## Summary (instant UI update)

- **Problem:** After a local delete, ViewState was updated but the UIKit message list (VC `localMessages` and data source) was not, so the table did not refresh.
- **Fix:** Introduce `refreshMessagesAfterLocalDelete()` on the VC; call it from `RepliesManager` after a successful delete, and from the VC when it receives `MessageDeletedLocally` (posted by `MessageContentsView` after a successful delete) for the current channel. Also make ViewState updates in `RepliesManager` synchronous so the refresh runs against the updated state.

---

# New message from another device not shown until leaving channel

## Problem

When the same account is logged in on two devices (e.g. Device A and Device B), sending a message from Device B does not show up on Device A until the user leaves the channel and re-enters (or otherwise triggers a refresh). Device A should show the new message as soon as it is received over the WebSocket.

## Root cause

When a new message arrives via WebSocket (`.message(m)` in `ViewState+WebSocketEvents.swift`), ViewState is updated correctly: `messages[m.id] = m` and `channelMessages[m.channel]?.append(m.id)`. A notification `NewMessagesReceived` is posted so the channel view can react.

The channel list is driven by **UIKit** (`MessageableChannelViewController` + `LocalMessagesDataSource`), which keeps a **local copy** of message IDs (`localMessages` and the data source’s list). The observer for `NewMessagesReceived` was `handleNewMessages`, which only decided whether to **scroll to bottom** (using `viewModel.messages.count` vs a stored count). It did **not**:

1. Sync `localMessages` from ViewState’s `channelMessages`.
2. Update the data source with the new list.
3. Reload the table.

So ViewState had the new message, but the table’s data source still had the old list and was never reloaded. The new message only appeared after a full reload (e.g. leaving and re-entering the channel).

## Fix

1. **Include channel in the notification**  
   In `ViewState+WebSocketEvents.swift`, when posting `NewMessagesReceived` after processing a new message, pass `userInfo: ["channelId": m.channel]` so observers know which channel the message belongs to.

2. **Sync and reload in `handleNewMessages`**  
   In `MessageableChannelViewController+Notifications.swift`, in `handleNewMessages`:
   - After the existing guards (loading, target message protection), if the notification has a `channelId` in `userInfo`, return early unless it equals `viewModel.channel.id` (so only the VC for that channel refreshes).
   - Then: call `syncLocalMessagesWithViewState()` so `localMessages` is updated from `viewState.channelMessages`.
   - Update the data source with `(dataSource as? LocalMessagesDataSource)?.updateMessages(localMessages)`.
   - Call `tableView.reloadData()` and `updateTableViewBouncing()`.
   - Keep the existing scroll/count logic so the list scrolls to bottom when appropriate.

Result: when Device B sends a message, the WebSocket event updates ViewState and posts `NewMessagesReceived` with that channel’s ID; the channel VC for that channel on Device A runs the new sync/reload and the new message appears immediately.

## Code changes (cross-device new message)

### 1. `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`

- Where `NotificationCenter.default.post(name: NSNotification.Name("NewMessagesReceived"), object: nil)` is called after processing a new `.message(m)`:
  - Change to post with `userInfo: ["channelId": m.channel]` so observers can filter by channel.

### 2. `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`

- In `handleNewMessages(_:)`:
  - After the existing early returns (e.g. loading, target message protection), if `notification.userInfo?["channelId"] as? String` is present and not equal to `viewModel.channel.id`, return (ignore notifications for other channels).
  - Call `syncLocalMessagesWithViewState()`, then update the data source with `localMessages`, then `tableView.reloadData()` and `updateTableViewBouncing()`.
  - Leave the rest of the method (message count check, scroll-to-bottom logic) unchanged so it runs with the updated list.

## Summary (cross-device new message)

- **Problem:** New messages sent from another device (same account) were added to ViewState by the WebSocket handler but the channel VC never refreshed its table, so they only appeared after leaving and re-entering the channel.
- **Fix:** Post `NewMessagesReceived` with `userInfo: ["channelId": m.channel]`, and in `handleNewMessages` for the channel VC, when the notification is for the current channel, sync `localMessages` from ViewState, update the data source, and reload the table so the new message appears immediately.
