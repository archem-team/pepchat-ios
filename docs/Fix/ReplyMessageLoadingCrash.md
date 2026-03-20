# Reply Message Loading Crash (Open Channel → SIGABRT)

**Status:** Fix applied in `MessageableChannelViewController.swift` (use `reloadData()` instead of `reloadRows(at:with:)` in the reply-refresh block).

This document explains a crash that can occur when a user **opens a channel** (taps into a chat). The app may abort immediately or shortly after the channel screen appears. The crash is reported as **SIGABRT** (abort) and is triggered by an assertion inside the system’s table view code.

---

## 1. Plain-Language Explanation (For Non-Coders)

### What the user did
The user **opened a channel**—they tapped on a chat to view the conversation.

### What happened
The app **crashed** (closed unexpectedly). The device or TestFlight reported a crash; technically it was an **“abort”** (the app deliberately stopped itself because an internal check failed).

### Why it happened (simple story)
1. When you open a channel, the app loads the list of messages from the server.
2. Some messages have **replies** (like threads). The app then loads the content of those replies in the background.
3. When that reply loading finishes, the app tries to **refresh only the specific rows** on screen that show those replies, instead of refreshing the whole list.
4. At almost the same time, the “open channel” flow is **updating the whole message list** (merging new data and refreshing the table).
5. Refreshing “only these rows” while the list is changing causes the table view to get into an invalid state. The system then runs a safety check, the check fails, and the app aborts.

So: **the crash is caused by refreshing only some rows of the message list while the list is being updated elsewhere.** The fix is to avoid that unsafe partial refresh in this situation (see below).

### Where in the app it happens
- **Screen:** The channel chat screen (message list).
- **Code:** The part that “refreshes the table after loading reply message content,” inside the channel view controller.  
- **Exact line:** See “Exact code location” below.

---

## 2. Technical Summary

| Item | Detail |
|------|--------|
| **Exception** | `EXC_CRASH (SIGABRT)` |
| **Trigger** | `UITableView` assertion in `_endCellAnimationsWithContext` |
| **App call** | `tableView.reloadRows(at:with:)` |
| **Cause** | Row count or data source changes during/around the partial reload, so the table view’s internal state is inconsistent. |
| **Flow** | Open channel → `loadInitialMessages` → `loadRegularMessages` → `fetchReplyMessagesContentAndRefreshUI` → `fetchReplyMessagesContent` → `MainActor.run` → `reloadRows(at:with:)` → UIKit assertion → crash. |

---

## 3. Root Cause (Code Level)

- **File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
- **Method:** `fetchReplyMessagesContent(for:)`
- **Block:** The `await MainActor.run { ... }` block that runs after reply messages are fetched (around lines 2083–2126).

In that block the code:

1. Gets the currently visible rows from the table.
2. Builds a list of index paths for rows that show messages with newly loaded replies.
3. Calls `tableView.reloadRows(at: indexPathsToReload, with: .none)` (line 2123).

Meanwhile, `loadRegularMessages` (in `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`) has already received the server response and will:

- Merge message IDs and update `localMessages`.
- Schedule a **full table reload** (`reloadData()`) on the main queue.

So two things can happen on the main thread in quick succession:

- This block runs and calls `reloadRows(at: indexPathsToReload, with: .none)`.
- The merge + `reloadData()` from `loadRegularMessages` runs (before or during the row reload).

When the table’s row count or data source changes during the partial reload, `UITableView` can hit an assertion (e.g. “number of rows in section changed during the update”) in `_endCellAnimationsWithContext` and abort.

The code only checks `indexPath.row < localMessages.count`; it does **not** ensure that the table’s *current* number of rows (from its data source) still matches, or that another full reload isn’t about to run. So the crash is a **race** between this partial refresh and the full reload.

---

## 4. Exact Code Location

**File:**  
`Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

**Line:**  
**2123**

**Snippet:**
```swift
tableView.reloadRows(at: indexPathsToReload, with: .none)
```

This is inside:

- Method: `fetchReplyMessagesContent(for:)`
- Block: `await MainActor.run { ... }` that starts around line 2083 (“CRITICAL FIX: Force UI refresh after fetching replies”).

**Call chain (for navigation):**

- `loadInitialMessages()`  
  → `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift` (around line 422)
- `loadRegularMessages(forceFetchFromServer:)`  
  → same file, around line 608
- `fetchReplyMessagesContentAndRefreshUI(for:)`  
  → `MessageableChannelViewController.swift`, around line 1954
- `fetchReplyMessagesContent(for:)`  
  → same file, around lines 2084 and 2123 (closure and `reloadRows` call)

---

## 5. How to Fix the Crash

### Idea
Avoid calling `reloadRows(at:with:)` when the table’s content might be changing. In this “force refresh after loading replies” block, use a **full table reload** instead of a partial one. A full reload does not depend on specific index paths and does not conflict with a later full reload from `loadRegularMessages`.

### What to change
In the same `MainActor.run` block (lines 2083–2126), **replace** the logic that builds `indexPathsToReload` and calls `reloadRows(at:with:)` with a single, safe call to **`reloadData()`** when we need to refresh the table after loading replies.

Optionally, keep a guard so we only touch the table when it has a data source (consistent with `AGENTS.md` scroll/navigation safety).

### Where to change it
- **File:** `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
- **Region:** Inside `fetchReplyMessagesContent(for:)`, in the `await MainActor.run { ... }` block that starts at line 2083.

### Code fix

**Remove** the block that:

- Gets `visibleIndexPaths`
- Builds `indexPathsToReload` from visible rows with newly fetched replies
- Calls `tableView.reloadRows(at: indexPathsToReload, with: .none)`

**Replace** it with a single full reload when we have a table and need to refresh after loading replies:

```swift
// FORCE refresh UI to show newly loaded reply content
if !replyIdsToFetch.isEmpty {
    print(
        "🔗 FORCE_REFRESH: Forcing UI refresh after loading \(replyIdsToFetch.count) reply messages"
    )
    if let tableView = self.tableView, tableView.dataSource != nil {
        tableView.reloadData()
    }
}
```

So the entire block from “Find visible cells that might have replies” through “tableView.reloadRows(at: indexPathsToReload, with: .none)” is replaced by the `reloadData()` approach above.

### Why this fixes the crash
- `reloadData()` tells the table to refresh all rows from the current data source. It does not rely on previously computed index paths, so it is safe even if the list was updated or is about to be updated by `loadRegularMessages`.
- Calling `reloadData()` twice in a row (here and in `loadRegularMessages`) is safe and idempotent; it does not trigger the “row count changed during update” assertion that `reloadRows` did.

---

## 6. Optional: Safer partial reload (if you need it later)

If you later want to keep a **partial** refresh (only rows with new replies) in other contexts where the table is stable:

1. Before calling `reloadRows(at:with:)`, ask the table how many rows it currently has:  
   `let rowCount = tableView.numberOfRows(inSection: 0)`.
2. Filter `indexPathsToReload` to only include index paths with `indexPath.row < rowCount`.
3. If any index path was dropped, or if `rowCount != localMessages.count`, fall back to `reloadData()` instead of `reloadRows(at:with:)`.

For the **open-channel** path, the recommended fix is still to use only `reloadData()` in this block, as in section 5.

---

## 7. Related project notes

- **AGENTS.md** describes the channel/message architecture: `MessageableChannelViewController`, `LocalMessagesDataSource`, and the message loading flow in `Revolt/Pages/Channel/Messagable/` and `Extensions/MessageableChannelViewController+MessageLoading.swift`.
- **Scroll/Navigation safety:** When changing this view controller, keep table operations safe: ensure the table has a data source and that index paths are valid before scrolling or updating rows (see `AGENTS.md` and `docs/Sentry.md`).
- **Message list updates:** Table updates should be consistent with `localMessages` and the data source; partial reloads are only safe when the table is not being fully reloaded elsewhere at the same time.

---

## 8. References

- Crash report: `.cursor/debug.log` (SIGABRT, `fetchReplyMessagesContent`, line 2123).
- Architecture and navigation: `AGENTS.md`.
- Other table-view and crash notes: `docs/Sentry.md`.
