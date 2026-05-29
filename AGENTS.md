API docs: https://developers.revolt.chat/developers/endpoints.html

# Repository Guidelines

## Project Structure & Module Organization

- `Revolt/` contains the main iOS app (Swift/SwiftUI views, networking, and app entry points).
- `notificationservice/` is the Notification Service Extension.
- `ShareExtension/` is the iOS Share Extension target (`ShareViewController.swift`, SwiftUI picker UI) for sharing photos, videos, and files from other apps into a channel.
- `Shared/AttachmentSharing/` holds code compiled into both the main app and Share Extension (`ShareExtensionShared.swift`: `ShareRecipientIndex`, `ShareStorage`, App Group I/O, shared Keychain session read).
- `Types/` holds shared model types.
- `RevoltTests/`, `RevoltUITests/`, and `Tests/` contain unit/UI tests (XCTest).
- `Revolt/Resources/` stores assets, xcassets catalogs, and localized strings (`Localizable.xcstrings`).
- `Revolt/1Storage/` contains local storage managers: `MessageCacheManager` (SQLite-based message cache, reads and internal write API) and `MessageCacheWriter` (single session-scoped write path used by ViewModel, WebSocket, MessageInputHandler, RepliesManager, MessageContentsView).
- `Revolt/Pages/Features/Core/` contains base architecture components (e.g., `BaseViewModel` for MVVM pattern).
- `Revolt/ViewState+Extensions/` contains ViewState extensions split by responsibility (see State Management section below).
- `Revolt/Components/Home/Discover/` contains the Discover servers feature: `DiscoverScrollView`, `DiscoverItem`, `DiscoverItemView`, and `ServerChatDataFetcher` (CSV-backed server list with membership cache).
- `Revolt/Components/MessageRenderer/` contains shared message presentation and reactions: `MessageView`, `MessageContentsView`, `MessageReactionsSheet` (SwiftUI), and `MessageReactionsSheetUIKit` (used from UIKit flows such as `MessageCell+ContextMenu`).
- `Revolt/Pages/Channel/Messagable/` is organized into subdirectories:
  - `Managers/` - Business logic managers (PermissionsManager, RepliesManager, TypingIndicatorManager, ScrollPositionManager, PendingAttachmentsManager, MessageLoader, MessageGroupingManager, CellHeightCache for UITableView height caching, etc.)
  - `Models/` - Data models specific to messageable channels
  - `Views/` - UI components (MessageCell, ToastView, NSFWOverlayView, etc.) and `MessageCell+Extensions/` (Setup, Content, Layout, Attachments, AVPlayer, Reply, Reactions, Swipe, ContextMenu, GestureRecognizer, TextViewDelegate)
  - `Extensions/` - ViewController extensions organized by functionality
  - `Utils/` - Utility functions and helpers
  - `DataSources/` - UITableView data source implementations
  - `Controllers/` - View controllers (e.g., FullScreenImageViewController)
  - `Attachments/` - In-composer attachment picker (`AttachmentsSheet.swift`); `ChannelInfo/`, `Mention/` - Other feature-specific subdirectories
- `Revolt/Pages/Channel/Messagable/ChannelInfo/` contains channel member-management surfaces: `ChannelInfo` (member list/search, group DM owner transfer, server kick/ban sheets) and `AddMembersToChannelView` (friend picker with existing-member disabling and batched invite flow).
- `Package.swift` and `Revolt.xcworkspace` define SwiftPM and Xcode workspace configuration. The workspace also includes CocoaPods (`Pods/`) for some dependencies (e.g., Down).

## Architecture Overview

- UI is primarily SwiftUI, with UIKit used where needed (e.g., complex channel/message views via `MessageableChannelViewController`).
- Feature screens live under `Revolt/Pages/`, while reusable UI is under `Revolt/Components/`.
- Networking and realtime behavior live in `Revolt/Api/` (HTTP + websocket).
- Shared domain models live in `Types/` and are used across UI and networking layers.
- Key flows: auth screens under `Revolt/Pages/Login/`, channel + message UI under `Revolt/Pages/Channel/` (primary list UI is UIKit `MessageableChannelViewController`; SwiftUI `MessageableChannel` also exists), settings under `Revolt/Pages/Settings/`, Discover servers under `Revolt/Components/Home/Discover/` (CSV-backed server list with membership cache for peptide.chat), and system share-sheet attachment sharing via the `ShareExtension` target (recipient index written by the main app; see Share Extension section below).
- DM list virtual scrolling: `ViewState` tracks visible DM batches (`visibleStartBatch` / `visibleEndBatch`, `loadedDmBatches`, `dmBatchSize`) to limit in-memory DM rows while keeping smooth scrolling.
- Data flow: `Revolt/Api/` → `Types/` → view models (ex: `Revolt/Pages/.../*ViewModel.swift`) → views (`Revolt/Pages/`, `Revolt/Components/`).

### State Management

- `ViewState` (`Revolt/ViewState.swift`) is a singleton `ObservableObject` managing global app state (users, channels, messages, websocket connection, etc.).
- **`batchUpdate(_:)`** (`ViewState.swift`): wraps multi-property mutations so `objectWillChange` is not fired per field; debounced UserDefaults snapshots for `users` / `channelMessages` and badge flush side effects run once after the block (used heavily on WebSocket hot paths to coalesce SwiftUI updates).
- ViewState persists data to UserDefaults and Keychain, with debounced saves for performance.
- Memory management: automatic cleanup of old messages/users with configurable limits (maxMessagesInMemory, maxUsersInMemory).
- **ViewState Extensions** (`Revolt/ViewState+Extensions/`): The ViewState class is split across multiple extension files for easier navigation:
  - `ViewState+Types.swift` - Supporting types: `LoginState`, `MainSelection` (`.server`, `.dms`, `.discover`), `ChannelSelection`, `NavigationDestination`, `QueuedMessage`, etc.
  - `ViewState+Memory.swift` - Memory limits, cleanup, and preloading (`enforceMemoryLimits`, `smartMessageCleanup`, `cleanupChannelFromMemory`, etc.)
  - `ViewState+WebSocketEvents.swift` - WebSocket event processing (`processEvent` switch and event handlers). On new message (`.message(m)`), updates `messages` and `channelMessages`, then posts `NewMessagesReceived` with `userInfo: ["channelId": m.channel]` so the channel VC for that channel can refresh its table (messages from another device appear without leaving the channel).
  - `ViewState+UsersAndDms.swift` - User/DM loading (`processUsers`, `loadUsersForDmBatch`, `processDMs`, etc.). User preloading prioritizes self plus relationship states (`Friend`, `Incoming`, `Outgoing`, `Blocked`, `BlockedOther`) and lazy-loads additional DM/message authors from `allEventUsers` (placeholder fallback only as last resort).
  - `ViewState+Navigation.swift` - Selection and navigation (`selectServer`, `selectChannel`, `selectDm`, `handleChannelChange`)
  - `ViewState+Unreads.swift` - Unread counts and badges (`getUnreadCountFor`, `cleanupStaleUnreads`, `forceMarkAllAsRead`)
  - `ViewState+Auth.swift` - Authentication (`signIn`, `signOut`, `destroyCache`). `signOut()` clears share-extension App Group data (`clearShareExtensionData()`) and channel cache at the start, then `clearAllDraftsForCurrentAccount()` before `state = .signedOut`; `destroyCache()` repeats draft/share clears and flushes `MessageCacheWriter` with bounded timeout before clearing message cache and in-memory state.
  - `ViewState+ServerCache.swift` - Server cache persistence (`loadServersCacheSync`, `saveServersCacheAsync`)
  - `ViewState+ReadyEvent.swift` - Ready event processing (`extractNeededDataFromReadyEvent`, `processReadyData`). Binds message cache session via `MessageCacheWriter.shared.setSession(userId:baseURL:)` when connected; also loads draft storage via `loadDraftsFromUserDefaults(userId:baseURL:)` so drafts are session-bound. Ready reconciliation is authoritative for server membership/channels (prunes removed channels, resets `loadedServerChannels`, and persists channel/server caches).
  - `ViewState+Notifications.swift` - Push tokens and app badge (`updateAppBadgeCount`, `retryUploadNotificationToken`)
  - `ViewState+QueuedMessages.swift` - Message queuing (`queueMessage`, `trySendingQueuedMessages`)
  - `ViewState+Drafts.swift` - Draft message storage (composer text per channel). Session-bound: loaded in `processReadyData`, cleared in `signOut()` and at the start of `destroyCache()`. Methods: `saveDraft(channelId:text:)`, `loadDraft(channelId:)`, `clearDraft(channelId:)`, `clearAllDraftsForCurrentAccount()`. UserDefaults key `channelDrafts_\(userId)_\(baseURL)`; text-only (no reply/edit context).
  - `ViewState+DMChannel.swift` - DM channel operations (`deactivateDMChannel`, `closeDMGroup`, `removeChannel`)
  - `ViewState+MembershipCache.swift` - Discover server membership cache (`loadMembershipCacheSync`, `saveMembershipCacheAsync`, `updateMembershipCache`) for instant Discover UI on launch and sync across devices via WebSocket
  - `ViewState+ChannelCache.swift` - Server channel list cache: persist per-server text/voice channels for restore; cleared on sign-out/destroyCache
  - `ViewState+ShareIndex.swift` - Share Extension recipient index (`saveShareRecipientIndexAsync`, `clearShareExtensionData`). Builds `ShareRecipientIndex` from DMs, group DMs, friends without an existing DM, and server text channels; persists via `ShareStorage` to the App Group. Called after `processReadyData`, on WebSocket events that change channels/servers/relationships (`shouldRefreshShareRecipientIndex`), and cleared at the start of `signOut()` / `destroyCache()`.

### Share Extension (Attachment Sharing)

- **Targets**: Main app + `ShareExtension/` + shared module `Shared/AttachmentSharing/ShareExtensionShared.swift`.
- **App Group**: `group.pepchat.shared.data` (`AttachmentSharingConstants.appGroupIdentifier`) — recipient index JSON, session metadata, and temporary attachment copies. Configured in `Revolt.entitlements` and `ShareExtension/ShareExtension.entitlements`.
- **Shared Keychain**: Extension reads session token via `ShareKeychain` / `keychain-access-groups` (`chat.zeko.app.shared`); main app writes session metadata in `processReadyData` via `ShareStorage.saveSessionMetadata`.
- **Main app writer**: After Ready and on relevant WebSocket events, `ViewState+ShareIndex` builds and saves `ShareRecipientIndex` (DMs, group DMs, server text channels, recent channel IDs). Extension cannot use live `ViewState`; it loads the persisted index and token only.
- **Extension sender**: `ShareViewController.swift` hosts SwiftUI (`ShareExtensionViewModel`, destination picker, upload + `/channels/{id}/messages`). Runs in a separate process with limited memory/time; no offline queue across termination.
- **Provisioning**: App Group and Keychain Sharing capabilities must match in Xcode and Apple Developer (see `docs/Feature/AttachmentSharing.md` for setup, activation rules, and debugging notes).

### View Model Pattern

- `BaseViewModel<State, Action>` (`Revolt/Pages/Features/Core/BaseViewModel.swift`) provides MVVM foundation with `UiAction` and `UiEvent` protocols.
- View models extend `BaseViewModel` and implement `send(action:)` for state updates.
- Used in feature screens under `Revolt/Pages/Features/`.

### Local Caching

- **MessageCacheWriter** (`Revolt/1Storage/MessageCacheWriter.swift`): Single serialized, session-scoped cache write path. All cache writes from ViewModel, WebSocket events, MessageInputHandler, RepliesManager, and MessageContentsView go through this writer to prevent races and cross-account leakage. Session is bound via `setSession(userId:baseURL:)` (called from `ViewState+ReadyEvent` when connected); on sign-out, `ViewState.destroyCache()` calls `invalidate(flushFirst: true)` to flush pending writes with a bounded timeout (e.g. 4s) then clear caches. When adding new cache write call sites, use the writer’s `enqueue`* methods rather than writing directly to `MessageCacheManager`.
- **MessageCacheManager** (`Revolt/1Storage/MessageCacheManager.swift`): SQLite-based local message cache. Handles reads (`loadCachedMessages`, `loadCachedUsers`, `cachedMessageCount`, `hasCachedMessages`) and internal write implementation; all persistent writes are invoked via `MessageCacheWriter`. Schema v2 is multi-tenant (messages, users, channel_info, tombstones keyed by `channel_id` + `user_id` + `base_url`); soft deletes use a tombstones table. Caches messages, users, and channel metadata with automatic cleanup and preloading of frequently accessed channels. **Server reconciliation**: When API history is merged after opening a channel (`MessageableChannelViewController+MessageLoading.swift`), message IDs present locally (e.g. from cache) in the fetched page’s time window but absent from the API response are treated as deleted. Reconciliation runs only when the API returns a **full page** (limit 100); a short page means end-of-history, so missing older IDs are not tombstoned. Deleted IDs go to `deletedMessageIds` and `MessageCacheWriter.enqueueDeleteMessage` so UI and cache stay in sync after reopen.
- **UserDefaults channel message IDs**: `ViewState+Memory.channelMessagesPersistenceSnapshot()` caps each channel’s persisted ID list to 200 (`channelMessagesPersistenceCapPerChannel`) to avoid huge JSON encodes; in-memory `channelMessages` is not capped by this.
- **Draft messages** (`ViewState+Drafts.swift`, `ViewState.channelDrafts`): Per-channel composer text only; stored in UserDefaults under `channelDrafts_\(userId)_\(baseURL)`. Not part of the message cache. Session-bound: loaded in `processReadyData` after `setSession`; cleared in `signOut()` and at the start of `destroyCache()`. Saved on leave (viewDidDisappear before cleanup) and via debounced typing; cleared at commit-to-send (offline and online) in `MessageInputHandler`. Restored in `viewWillAppear` when non-empty; when nil/empty the composer is not cleared (preserves same-channel return and return-from-search). See `docs/Feature/DraftMessage.md` for full plan and implementation notes.

### Manager Pattern

- Complex view controllers (e.g., `MessageableChannelViewController`) use dedicated manager classes:
  - `PermissionsManager` - Handles channel permissions and UI configuration
  - `RepliesManager` - Manages message replies and reply UI; on successful local message delete updates ViewState synchronously and calls `viewController?.refreshMessagesAfterLocalDelete()` so the table updates immediately.
  - `TypingIndicatorManager` - Manages typing indicators
  - `ScrollPositionManager` - Handles scroll position preservation
  - `MessageGroupingManager` - Groups consecutive messages from same author
  - `MessageLoader` - Handles message loading and pagination
  - `PendingAttachmentsManager` - Manages pending attachments in the message composer before send (implementation file: `1PendingAttachmentsManager.swift`)
  - `CellHeightCache` - Caches calculated UITableView row heights keyed by message/layout inputs; wired from `MessageableChannelViewController` and `MessageableChannelViewController+TableView`

## Dependencies & Third-Party Libraries

- **Networking**: Alamofire (HTTP), Starscream (WebSocket)
- **Image Loading**: Kingfisher
- **Error Tracking**: Sentry
- **UI Components**: SwiftUI-Flow, SwiftUIMasonry, ExyteGrid, NavigationTransitions, PopupView, SwiftUITooltip, SwiftyCrop
- **Parsing**: SwiftParsec, Parsing, MarkdownKit, Down
- **Utilities**: ULID, KeychainAccess, Collections, OrderedCollections, CodableWrapper, AnyCodable
- **Other**: HCaptcha, SubviewAttachingTextView, Highlightr, OggDecoder, SwiftCSV
- Dependencies are managed via Swift Package Manager (SPM) in `Revolt.xcworkspace` and CocoaPods (`Podfile`) for some libraries (e.g., Down).

## Project Documentation

- `FEATURES.md` - Product features summary (onboarding, messaging, servers, settings, etc.).
- `docs/Sentry.md` - Sentry crash report analysis, root causes, and fix recommendations (scroll/navigation guards, memory management).
- `docs/ForceUnwrap.md` - Force unwrap audit (`!`, `as!`, `try!`) by risk level and file location; use when hardening crash-prone paths.
- `docs/Implementation.md` - Auto-generated per-file Swift / SwiftUI / UIKit stack map across the repo (high-level orientation, not a substitute for reading source).
- `docs/claude-code-setup.md` - Local tooling setup notes for Claude Code workflows.
- **Feature logs** (`docs/Feature/`): `PinMessage.md`, `VerifiedBadges.md`, `DraftMessage.md`, `Channel.md`, `MentionIndicator.md` (mention counts / unread styling in channel and DM lists, `UnreadMentionsView`, etc.), `AttachmentSharing.md` (iOS Share Extension, App Group recipient index, shared Keychain, extension UI and upload flow).
- **Fix / investigation logs** (`docs/Fix/`): `DeleteMessagesIssue.md`, `ContactMessage.md`, `MessageReaction.md`, `ChatSynchronization.md`, `ChatOrdering.md`, `DuplicateMessage.md`, `ProfilePicture.md`, `ReplyMessageLoadingCrash.md`, `LoadingMessagePlaceholder.md`, `MultilineMessage.md`, `LinkPreviewImage.md`, `BrokenInvites.md`, and related notes.
- `docs/TestCases.md` - Rules and template for AI agents to derive and write test cases: user POV, step-by-step format, expected outcome/result, edge-case coverage, and feature-area mapping; use when preparing manual or automated test cases for a feature or flow.
- `docs/UIKitImplementation.md` - UIKit channel architecture and implementation notes.

## Build, Test, and Development Commands

- Open the workspace: `open Revolt.xcworkspace` (recommended for local dev).
- Resolve SwiftPM packages: `xcodebuild -resolvePackageDependencies`.
- Build from CLI (example): `xcodebuild -scheme Revolt -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Run tests (example): `xcodebuild -scheme Revolt -destination 'platform=iOS Simulator,name=iPhone 15' test`.

## Coding Style & Naming Conventions

- Use Swift standard formatting with 4-space indentation.
- Types and files: `UpperCamelCase` (e.g., `MessageableChannelViewModel.swift`).
- Properties, functions, and locals: `lowerCamelCase`.
- Keep SwiftUI view files scoped to their feature folders under `Revolt/Pages/`.
- No repo-wide formatter is configured; keep diffs minimal and consistent with nearby code.

## Testing Guidelines

- Tests use XCTest and live in `RevoltTests/`, `RevoltUITests/`, and `Tests/`.
- Name tests descriptively (e.g., `testLoginSucceedsWithValidCredentials`).
- Prefer updating/adding tests alongside behavioral changes to networking and view models.
- When generating test cases (manual or automated), follow `docs/TestCases.md` for format, user POV, steps, expected outcome/result, edge-case coverage, and feature-area mapping.

## Commit & Pull Request Guidelines

- Commit messages in history are short, sentence-style summaries (no conventional prefix); follow that pattern.
- PRs should include: a brief summary, testing performed, and screenshots or recordings for UI changes.
- Link related issues or tickets when applicable.

## Security & Configuration Tips

- Avoid committing secrets (tokens, API keys). Use environment variables or Xcode build settings for local overrides.
- When modifying entitlements or provisioning (`Revolt/Revolt.entitlements`), document the reason in the PR.
- Session tokens are stored in Keychain via `KeychainAccess` library (`chat.peptide.app` service). The Share Extension reads the same session via a **Keychain Access Group** (`chat.zeko.app.shared`); do not duplicate token storage in UserDefaults.
- App Group `group.pepchat.shared.data` holds share-extension recipient index and temp files only; treat as session-scoped and clear via `clearShareExtensionData()` on sign-out / `destroyCache()`.
- UserDefaults is used for non-sensitive app state persistence (with debounced saves for performance).

## Performance Considerations

- Message caching: `MessageCacheManager` provides instant message loading from SQLite cache. All cache writes go through `MessageCacheWriter` for serialization and session safety; sign-out flushes pending writes with a bounded timeout before clearing caches.
- Discover membership cache: `ViewState+MembershipCache` persists server join/leave state to disk for instant Discover UI on launch; updated on join/leave events (local or via WebSocket).
- Memory management: ViewState implements automatic cleanup of old messages/users to prevent memory issues.
- Debounced saves: Large data structures (users, emojis, messages) use debounced UserDefaults saves to prevent UI blocking. Persisted `channelMessages` ID lists are capped per channel (200) in `ViewState+Memory` before encode.
- Background operations: Heavy operations (cache updates, data encoding) are performed on background queues.
- Channel preloading: Important channels are preloaded in the background for faster access.
- UITableView message list: `CellHeightCache` avoids repeated height calculation for stable rows; DM sidebar uses batched visible-window loading in `ViewState` to cap loaded DM batches.
- SwiftUI refresh churn: `ViewState.batchUpdate` reduces redundant view invalidations when many properties change in one WebSocket tick.

## Code Organization Notes

- **ViewState refactoring**: The main `ViewState.swift` file contains class properties and init. Logic is split into extension files in `Revolt/ViewState+Extensions/` for easier navigation and maintainability.
- When adding new ViewState functionality, place it in the appropriate extension file based on responsibility (e.g., memory-related code in `ViewState+Memory.swift`).
- **Message cache writes**: Any new code that should persist messages/users to the SQLite cache must use `MessageCacheWriter.shared` (e.g. `enqueueCacheMessagesAndUsers`, `enqueueUpdateMessage`, `enqueueDeleteMessage`), not direct `MessageCacheManager` write APIs, to avoid races and cross-account leakage.
- **Scroll/Navigation safety**: When modifying `MessageableChannelViewController`, `ScrollPositionManager`, or `MessageableChannelViewController+TargetMessage`, guard scroll operations: ensure `tableView.dataSource != nil` and target row index is valid before `scrollToRow(at:animated:)`. Cancel pending scroll `DispatchWorkItem`s in `viewWillDisappear` to avoid crashes during navigation (see `docs/Sentry.md`).
- **Draft messages**: Implemented per `docs/Feature/DraftMessage.md`. Draft storage lives in `ViewState+Drafts.swift` and `ViewState.channelDrafts`; do not use the message cache for drafts. Clear drafts at commit-to-send (in `MessageInputHandler`), not only after API success; clear on sign-out in both `signOut()` and at the start of `destroyCache()`. When restoring in `viewWillAppear`, if there is no stored draft do not clear the composer (same-channel return and return-from-search). Debounced save uses `draftSaveWorkItem` in `MessageableChannelViewController`; cancel it in `viewWillDisappear`.
- **Ready-event resilience/perf**: `processEvent(.ready)` preserves `currentChannel` / `currentSelection`, processes extracted ready data, then restores selection and eagerly reloads the selected server’s channels if needed. Unreads are fetched in parallel with ready processing and merged afterward; stale unreads are cleaned after ready reconciliation.
- **Message channel UI sync**: The channel message list is UIKit (`MessageableChannelViewController` + `LocalMessagesDataSource`) and keeps a local copy of message IDs. (1) **Local delete**: After a successful delete (from `RepliesManager` or `MessageContentsView`), ViewState is updated and the table must refresh: `refreshMessagesAfterLocalDelete()` syncs `localMessages` from ViewState, updates the data source, and reloads the table; it is called from `RepliesManager` on success and from the VC when it receives the `MessageDeletedLocally` notification (posted by `MessageContentsView` after delete). (2) **New messages from other devices**: When a new message arrives via WebSocket, ViewState is updated and `NewMessagesReceived` is posted with `userInfo: ["channelId": m.channel]`. `handleNewMessages` (`MessageableChannelViewController+Notifications.swift`) only runs sync/reload when the notification is for the current channel; it then syncs from ViewState, updates the data source, and reloads the table so messages sent from another device appear without leaving the channel.
- **New DM edge cases**: For first-message reliability in newly opened DMs and delete-to-empty transitions, see `docs/Fix/ContactMessage.md`. Keep `openDm(with:)` channel hydration (`channels`, `allEventChannels`, `channelMessages`) and ensure `syncLocalMessagesWithViewState()` correctly handles fully empty sources to clear stale `localMessages`.
- **DM ordering contract**: DM sorting in `processDMs` prioritizes unread channels first, then `last_message_id` descending, with Ready payload order as a tie-breaker. Preserve this fallback so same-timestamp/missing-last-message DMs stay consistent across devices/clients.
- **Verified username badge**: Verified state is derived from user badge bitfield (`Types/User.hasVerifiedBadge()`, currently using `Badges.responsible_disclosure` bit). Username-level verified indicator in message rows is rendered as yellow SF Symbol `checkmark.seal.fill` in both UIKit (`MessageCell`) and SwiftUI (`MessageView`). Keep spacing behavior (collapsed width when hidden) and continuation-row hiding consistent; see `docs/Feature/VerifiedBadges.md`.
- **Message reactions**: SwiftUI sheet (`MessageReactionsSheet`) and UIKit-oriented wrapper (`MessageReactionsSheetUIKit`) live under `Revolt/Components/MessageRenderer/`; reaction add/remove should stay consistent with ViewState / WebSocket updates (see `docs/Fix/MessageReaction.md` when debugging stale counts or UI).
- **Mention unread UI**: Server and DM channel rows show mention-aware unread affordances via `UnreadMentionsView` and unread enum cases (`mentions`, `unreadWithMentions`) in components such as `ServerChannelScrollView` and `ChannelIcon`; see `docs/Feature/MentionIndicator.md`.
- **Attachment sharing (Share Extension)**: Do not read `ViewState` from the extension. Extend `Shared/AttachmentSharing/` for shared models/storage; refresh the recipient index from the main app via `ViewState+ShareIndex`. New share-related persistence must stay session-bound (`userId` + `baseURL`) and be cleared in `signOut()` / `destroyCache()`. See `docs/Feature/AttachmentSharing.md`.
- **Save attachment to Photos**: `FullScreenImageViewController` (`Messagable/Controllers/`) saves the displayed image (preferring original URL/data with auth when available) via `PHPhotoLibrary` add-only authorization. In-composer pending files remain `PendingAttachmentsManager` / `1PendingAttachmentsManager.swift`.
- **API history reconcile**: When merging fetched messages in `MessageableChannelViewController+MessageLoading.swift`, only treat cache-only IDs as server-deleted if the API page is full (100 messages); otherwise older local IDs may simply be off the end of the fetched window.

