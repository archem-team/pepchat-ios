# Chat Ordering

This document describes how chat-related lists are ordered and how that order is reflected in the UI. See `AGENTS.md` for project structure and state management.

---

## 1. Server list order

### Source of truth

- **User settings**: `UserSettingsStore.cache.orderSettings.servers` (`OrderingSettings.servers`) — array of server IDs in display order.
- **Type**: `Revolt/Api/UserSettingsStore.swift` — `struct OrderingSettings { var servers: [String] }`.

### How it is applied

- **ViewState**: `servers` is an `OrderedDictionary<String, Server>` (from `Collections`). Order is enforced by `applyServerOrdering()`:
  - Reads `userSettingsStore.cache.orderSettings.servers`.
  - Builds ordered list: IDs in that array (existing servers only), then any remaining servers not in the array.
  - Rebuilds `servers` as an `OrderedDictionary` in that order.
- **Where**: `Revolt/ViewState+Extensions/ViewState+ServerCache.swift` — `applyServerOrdering()`.
- **When**: On Ready event (after building server list in `ViewState+ReadyEvent.swift`), when user settings are fetched (`UserSettingsStore` after decoding `"ordering"`), on init if cache has servers and ordering (`ViewState.swift`), and on WebSocket server update when ordering is present (`ViewState+WebSocketEvents.swift`).

### Persistence and sync

- Order is persisted locally via `UserSettingsStore.writeCacheToFile()` when `updateServerOrdering(orders:)` is called.
- Server order is synced to the backend via `prepareOrderingSettings()` (key `"ordering"`) and `viewState.http.setSettings(timestamp:keys:)` when the user finishes a drag.

### UI

- **ServerScrollView** (`Revolt/Components/Home/ServerScrollView.swift`): Iterates `viewState.servers.elements` (order preserved by `OrderedDictionary`). Drag-and-drop uses `viewState.reorderServers(from:to:)` and on drop completion calls `userSettingsStore.updateServerOrdering(orders:)` with `viewState.servers.elements.map { $0.key }`, then syncs to API.

---

## 2. Channel list order (within a server)

### Source of truth

- **Server model** (`Types/Server.swift`): `Server.channels` (uncategorized channel IDs) and `Server.categories` (array of `Category`; each has `id`, `title`, `channels: [String]`). Order is defined by the API/Ready payload and subsequent channel create/update events.

### How it is reflected

- **ServerChannelScrollView** (`Revolt/Components/Home/ServerChannelScrollView.swift`):
  - `nonCategoryChannels = server.channels.filter { !categoryChannels.contains($0) }` where `categoryChannels = server.categories?.flatMap(\.channels) ?? []`.
  - Renders in order:
    1. `ForEach(nonCategoryChannels.compactMap { viewState.channels[$0] })` — uncategorized channels in `server.channels` order.
    2. `ForEach(server.categories ?? [])` — each category in `server.categories` order; inside each, `ForEach(category.channels.compactMap { viewState.channels[$0] })` — channels in `category.channels` order.

No separate "channel ordering" setting is stored in the app; order is whatever the server and WebSocket events provide.

---

## 3. DM list order

### Source of truth

- **Canonical list**: `ViewState.allDmChannelIds` — array of DM channel IDs in display order. This is the full ordered list; `ViewState.dms` is a lazy subset (see below).

### Sort logic

- **Unread first**: A DM is considered unread when it has a `last_message_id` and it is not equal to `unreads[channelId]?.last_id` (i.e. user has not read up to the latest message).
- **Then by latest activity**: Among read/unread groups, DMs are ordered by `last_message_id` descending (ULID comparison → newest first).

Implementation in two places (same logic):

- **processDMs** (`Revolt/ViewState+Extensions/ViewState+UsersAndDms.swift`): When processing DMs from Ready/event data, builds `sortedDmChannels` with the comparator above and sets `allDmChannelIds = sortedDmChannels.map { $0.id }`.
- **reinitializeDmListFromCache** (`Revolt/ViewState.swift`): Rebuilds from `channels` and applies the same sort to set `allDmChannelIds` again.

### Lazy loading and visible list

- **allDmChannelIds**: Holds all DM channel IDs in the chosen order; updated on processDMs / reinitializeDmListFromCache and on each new message (see below).
- **dms**: Only the DMs for "visible" batches (batch size `dmBatchSize`, visible range `visibleStartBatch`–`visibleEndBatch`). Built by `rebuildVisibleDmsList()` from `allDmChannelIds` so the order of `dms` matches the canonical order for the loaded range.
- **loadDmBatch / loadDmBatchesIfNeeded**: Load batches by index into `loadedDmBatches` and then rebuild `dms` from those batches so the UI shows the same order as `allDmChannelIds`.

### Live updates

- **New message in a DM** (`ViewState+WebSocketEvents.swift`, Message handler):
  - The DM channel's `last_message_id` is updated in `channels` and in the `dms` array (when that channel is in the visible list).
  - The DM is moved to the top of the visible list when present: removed from its current index in `dms` and inserted at `0`.
  - **Canonical order**: `allDmChannelIds` is always updated (remove channel from current index, insert at 0; or insert at 0 if not yet in list), regardless of current tab or whether the channel is in the visible `dms` list, so the list stays "most recent at top" when the user opens DMs or when `loadDmBatch` rebuilds from `allDmChannelIds`.
- **New DM created** (`channel_create` for DM/group DM): Channel is inserted at index 0 in `dms` and stored in `channels`; `allDmChannelIds` is not updated in this path (consistency is restored on next processDMs or reinitializeDmListFromCache).

### UI

- **DMScrollView** (`Revolt/Components/Home/DMScrollView.swift`): Uses `viewState.dms` filtered to active DMs only (`dmChannel.active`), then `ForEach(Array(dmsList.enumerated()), id: \.element.id)` so the list order is exactly the order of `dms` (which mirrors `allDmChannelIds` for the loaded batches).

---

## 4. Message order within a channel

### Source of truth

- **ViewState**: `channelMessages[channelId]` — array of message IDs in **chronological order (oldest first)**. This is the display order for the channel.
- **MessageableChannelViewModel**: `messages` — same ordered array of message IDs, kept in sync with `viewState.channelMessages[channel.id]`.

### How order is established

- **Initial load** (`MessageableChannelViewModel`): API messages are sorted by creation time (e.g. `createdAt(id:)` from ULID) ascending and stored as IDs in `viewState.channelMessages[channel.id]` and in the view model's `messages`.
- **Pagination "before" (older messages)**: New IDs are prepended in chronological order (reversed result + existing) so the combined array stays oldest-first.
- **Pagination "after" (newer messages)**: New IDs are appended; existing order remains oldest-first.
- **New message (WebSocket)**: New message ID is appended to `channelMessages[channelId]` (and to the view model when applicable).
- **Preload** (`ViewState+Notifications.swift`): Cached messages are stored with IDs sorted by creation time ascending into `channelMessages[channelId]`.

### UI

- **MessageableChannelViewController** and its data source use the view model's `messages` (or equivalent ordering from `channelMessages`) to render rows; order is always chronological (oldest at top, newest at bottom) for the main timeline.

---

## Fixes

### DM list not ordered by most recent at top (old conversations at top, new buried)

**Issue (user report):** Conversations in direct and group chat were not ordered by most recent at the top. Sometimes old conversations appeared at the top and new ones were buried many items deep.

**Reason:** The canonical DM order is stored in `allDmChannelIds`. The visible list `dms` is rebuilt from `allDmChannelIds` when batches load (e.g. on scroll) in `loadDmBatch` (`ViewState+Extensions/ViewState+UsersAndDms.swift`). When a new message arrived in a DM, the code only updated `allDmChannelIds` when **both** `isDmListInitialized` and `currentSelection == .dms` were true. So when the user was on a server (or Discover) tab, incoming DM messages did not update the canonical order. When they later opened DMs, the first paint could show correct order (from in-memory `dms`), but as soon as any batch load ran (e.g. scrolling), `dms` was rebuilt from the stale `allDmChannelIds`, so the order reverted: old conversations at top, recently active ones buried.

**Approach:**

1. **Always** update `allDmChannelIds` when a message arrives in a DM (move that channel to index 0), regardless of `currentSelection` and regardless of whether the channel is in the current `dms` list.
2. Keep the existing **visible list** (`dms`) update as-is: when the channel is in `dms`, remove it and re-insert at 0 so the UI updates immediately for users on the DMs tab.

**Code changes** in `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`, inside the `case .message(let m):` branch:

1. **Removed** the conditional block that updated `allDmChannelIds` only when `isDmListInitialized && currentSelection == .dms` (the inner `if` with "FIX: Ensure DM list state is maintained" comment).

2. **Added** a new block that runs for every message whose channel is a DM (`.dm_channel` or `.group_dm_channel`), and updates `allDmChannelIds`: if the channel is already in the array, remove it and insert at 0; if not (e.g. new DM from another device), insert at 0. Placed after the `if let index = dms.firstIndex(...)` block and before `if var existing = channels[m.channel] {`.

**Added code:**

```swift
            // Always keep canonical DM order (most recent at top), even when user is not on DMs tab,
            // so that when they open DMs the list is correct and does not revert on scroll.
            let isDM: Bool = {
                if let ch = channels[m.channel] {
                    if case .dm_channel = ch { return true }
                    if case .group_dm_channel = ch { return true }
                }
                return false
            }()
            if isDM {
                if let idx = allDmChannelIds.firstIndex(of: m.channel) {
                    allDmChannelIds.remove(at: idx)
                    allDmChannelIds.insert(m.channel, at: 0)
                } else {
                    // New DM (e.g. from another device) or not yet in list
                    allDmChannelIds.insert(m.channel, at: 0)
                }
            }
```

**Result:** Every new message in a DM moves that channel to the top of `allDmChannelIds`. When the user opens DMs and the list is rebuilt (e.g. on scroll), they see "most recent at top" consistently.

