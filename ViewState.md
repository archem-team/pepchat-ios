# ViewState.swift Overview & Refactoring Guide

## What is ViewState?

`ViewState` is the **central singleton `ObservableObject`** that manages global app state for the Revolt/Peptide chat iOS app. It lives at `Revolt/ViewState.swift` and is approximately **6,073 lines** of code. The file serves as:

- **State container**: Holds all published state (users, channels, messages, servers, DMs, unreads, etc.)
- **Persistence layer**: Handles UserDefaults and Keychain persistence with debounced saves
- **WebSocket event handler**: Processes all real-time events from the server
- **Memory manager**: Enforces limits, cleanup, and preloading for channels/messages/users
- **Navigation & UI state**: Manages selection, path, sheets, alerts, and theme

---

## File Structure Overview

| Section | Approx. Lines | Content |
|---------|---------------|---------|
| **Supporting types** | 1–280 | `UserStateError`, `LoginState`, `LoginSuccess`, `LoginMfa`, `LoginDisabled`, `LoginResponse`, `ConnectionState`, `MainSelection`, `ChannelSelection`, `NavigationDestination`, `UserMaybeMember`, `QueuedMessage` class |
| **ViewState class – properties** | 281–650 | Main class declaration, `@Published` properties, init, `debouncedSave`, `enforceMemoryLimits` |
| **Memory management** | 650–1,800 | `smartMessageCleanup`, `smartUserCleanup`, `cleanupChannelMessages`, `preloadImportantChannels`, `cleanupChannelFromMemory`, `forceMemoryCleanup`, etc. |
| **Auth & HTTP** | 1,800–2,200 | `signIn`, `signOut`, `setSignedOutState`, `destroyCache`, `formatUrl`, `applySystemScheme`, `setBaseUrlToHttp` |
| **WebSocket & queue** | 2,100–2,250 | `backgroundWsTask`, `queueMessage`, `onEvent`, `processEvent` entry |
| **processEvent switch** | 2,250–3,100 | Huge switch on `WsMessage` – `.ready`, `.message`, `.message_update`, `.authenticated`, `.channel_start_typing`, `.message_delete`, `.channel_ack`, `.message_react`, `.channel_create`, `.channel_update`, `.channel_delete`, `.server_member_update`, etc. (~40+ cases) |
| **User & DM loading** | 3,100–4,150 | `processUsers`, `loadUsersForVisibleDms`, `loadUsersForDmBatch`, `loadServerChannels`, `processMembers`, `processDMs`, `loadDmBatch`, `aggressiveVirtualCleanup`, etc. |
| **Channel/Server/DM ops** | 4,150–5,050 | `joinServer`, `markServerAsRead`, `openDm`, `getUnreadCountFor`, `selectServer`, `selectChannel`, `selectDm`, `resolveAvatarUrl`, `getServerMembers`, `addOrReplaceMember`, etc. |
| **Notifications & badge** | 5,050–5,650 | `retryUploadNotificationToken`, `preloadMessagesForServer`, `updateAppBadgeCount`, `cleanupStaleUnreads`, `setupInternetObservation`, `trySendingQueuedMessages` |
| **Extensions** | 5,635–6,073 | Server cache (`loadServersCacheSync`, `saveServersCacheAsync`, `applyServerOrdering`), DM channel (`deactivateDMChannel`, `closeDMGroup`, `removeServer`, `removeChannel`), Ready event (`extractNeededDataFromReadyEvent`, `processReadyData`, `processChannelsFromData`, `processServersFromData`), `getName` |

---

## Refactoring Strategy: Split by Responsibility

The goal is to **move logic into extensions in separate files** without changing behavior. Swift allows splitting a class across multiple files using `extension ViewState`. Existing precedent: `ViewState+Login.swift` in `Revolt/ViewState+Extensions/`.

### Recommended Extensions & New Files

| New File | Content to Move | Est. Lines |
|----------|-----------------|------------|
| **ViewState+Types.swift** | `UserStateError`, `LoginState`, `LoginSuccess`, `LoginMfa`, `LoginDisabled`, `LoginResponse`, `ConnectionState`, `MainSelection`, `ChannelSelection`, `NavigationDestination`, `UserMaybeMember`, `QueuedMessage` | ~280 |
| **ViewState+Memory.swift** | `enforceMemoryLimits`, `smartMessageCleanup`, `smartUserCleanup`, `cleanupMemory`, `smartChannelCleanup`, `cleanupOrphanedMessages`, `preloadImportantChannels`, `preloadSpecificChannel`, `startPeriodicMemoryCleanup`, `cleanupChannelFromMemory`, `cleanupUnusedUsers`, `forceMemoryCleanup` | ~600 |
| **ViewState+WebSocketEvents.swift** | Entire `processEvent(_:)` switch body; optionally split into smaller helpers like `processReadyEvent`, `processMessageEvent`, `processChannelEvent`, etc. | ~850 |
| **ViewState+UsersAndDms.swift** | `processUsers`, `loadUsersForVisibleDms`, `loadUsersForDmBatch`, `loadUsersForFirstDmBatch`, `loadUsersForVisibleMessages`, `restoreMissingUsersForMessages`, `processMembers`, `processDMs`, `loadDmBatch`, `aggressiveVirtualCleanup`, `loadMoreDmsIfNeeded`, `ensureNoBatchGaps`, `resetAndReloadDms`, etc. | ~700 |
| **ViewState+Navigation.swift** | `selectServer`, `selectChannel`, `selectDms`, `selectDiscover`, `selectDm`, `handleChannelChange`, `handlePathChange` | ~200 |
| **ViewState+Unreads.swift** | `getUnreadCountFor(channel:)`, `getUnreadCountFor(server:)`, `getUnreadCountFromUnread`, `formattedMentionCount`, `cleanupStaleUnreads`, `forceMarkAllAsRead`, `showUnreadCounts`, `getUnreadCountsString` | ~400 |
| **ViewState+Auth.swift** | `signIn`, `signOut`, `innerSignIn`, `setSignedOutState`, `destroyCache` (or merge with existing `ViewState+Login.swift` if it already covers login) | ~150 |
| **ViewState+ServerCache.swift** | `serversCacheURL`, `loadServersCacheSync`, `saveServersCacheAsync`, `applyServerOrdering` | ~80 |
| **ViewState+ReadyEvent.swift** | `ReadyEventData`, `extractNeededDataFromReadyEvent`, `processReadyData`, `processChannelsFromData`, `processServersFromData` | ~250 |
| **ViewState+Notifications.swift** | `retryUploadNotificationToken`, `storePendingNotificationToken`, `loadPendingNotificationToken`, `updateAppBadgeCount`, `clearAppBadge`, `refreshAppBadge`, `preloadMessagesForServer`, `preloadChannelMessages` | ~250 |
| **ViewState+QueuedMessages.swift** | `queueMessage`, `trySendingQueuedMessages` (core logic) | ~200 |
| **ViewState+DMChannel.swift** | `deactivateDMChannel`, `closeDMGroup`, `removeServer`, `removeChannel` | ~80 |

### What Stays in ViewState.swift

Keep in the main file:

1. **Class declaration** and all `@Published` properties
2. **Init** and `debouncedSave`
3. **Core lifecycle** that many extensions depend on (e.g. `handleChannelChange` if tightly coupled to properties)
4. Small, frequently used helpers like `formatUrl`, `isURLSet`, `resolveAvatarUrl`

The main file would shrink to roughly **800–1,000 lines** of properties, init, and glue code.

---

## Step-by-Step Refactoring Process

1. **Create extension file** (e.g. `ViewState+Memory.swift`).
2. **Add the same imports** as `ViewState.swift` if needed.
3. **Add** `extension ViewState { … }` and move the selected methods.
4. **Ensure methods stay `internal` or `public`** as before; avoid changing access.
5. **Build** to confirm no compilation errors.
6. **Run tests** to verify behavior.
7. **Update Xcode project** (`project.pbxproj`) so the new file is part of the Revolt target.
8. **Repeat** for the next extension.

---

## Notes

- **Extensions can access private members** only if they are in the same Swift file. Methods that use `private` vars (e.g. `saveWorkItems`, `allEventUsers`) must either stay in the main file or have those vars made `internal` (or moved to a shared helper).
- **`processEvent`** is the largest single block. Consider extracting each `case` into a dedicated method (e.g. `processMessageEvent(_:)`, `processReadyEvent(_:)`) and calling them from the switch.
- The **ViewState+Extensions** folder already exists; new extension files can go there or in a subfolder like `ViewState+Extensions/Memory/`, etc.
- **QueuedMessage** is a separate class; it can live in `ViewState+Types.swift` or a dedicated `QueuedMessage.swift` if you prefer.
