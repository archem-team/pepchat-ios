# Repository Guidelines

## Project Structure & Module Organization
- `Revolt/` contains the main iOS app (Swift/SwiftUI views, networking, and app entry points).
- `notificationservice/` is the Notification Service Extension.
- `Types/` holds shared model types.
- `RevoltTests/`, `RevoltUITests/`, and `Tests/` contain unit/UI tests (XCTest).
- `Revolt/Resources/` stores assets, xcassets catalogs, and localized strings (`Localizable.xcstrings`).
- `Revolt/1Storage/` contains local storage managers: `MessageCacheManager` (SQLite-based message cache, reads and internal write API) and `MessageCacheWriter` (single session-scoped write path used by ViewModel, WebSocket, MessageInputHandler, RepliesManager, MessageContentsView).
- `Revolt/Pages/Features/Core/` contains base architecture components (e.g., `BaseViewModel` for MVVM pattern).
- `Revolt/ViewState+Extensions/` contains ViewState extensions split by responsibility (see State Management section below).
- `Revolt/Components/Home/Discover/` contains the Discover servers feature: `DiscoverScrollView`, `DiscoverItem`, `DiscoverItemView`, and `ServerChatDataFetcher` (CSV-backed server list with membership cache).
- `Revolt/Pages/Channel/Messagable/` is organized into subdirectories:
  - `Managers/` - Business logic managers (PermissionsManager, RepliesManager, TypingIndicatorManager, ScrollPositionManager, PendingAttachmentsManager, MessageLoader, MessageGroupingManager, etc.)
  - `Models/` - Data models specific to messageable channels
  - `Views/` - UI components (MessageCell, ToastView, NSFWOverlayView, etc.) and `MessageCell+Extensions/` (Setup, Content, Layout, Attachments, AVPlayer, Reply, Reactions, Swipe, ContextMenu, GestureRecognizer, TextViewDelegate)
  - `Extensions/` - ViewController extensions organized by functionality
  - `Utils/` - Utility functions and helpers
  - `DataSources/` - UITableView data source implementations
  - `Controllers/` - View controllers (e.g., FullScreenImageViewController)
  - `Attachments/`, `ChannelInfo/`, `Mention/` - Feature-specific subdirectories
- `Package.swift` and `Revolt.xcworkspace` define SwiftPM and Xcode workspace configuration. The workspace also includes CocoaPods (`Pods/`) for some dependencies (e.g., Down).

## Architecture Overview
- UI is primarily SwiftUI, with UIKit used where needed (e.g., complex channel/message views via `MessageableChannelViewController`).
- Feature screens live under `Revolt/Pages/`, while reusable UI is under `Revolt/Components/`.
- Networking and realtime behavior live in `Revolt/Api/` (HTTP + websocket).
- Shared domain models live in `Types/` and are used across UI and networking layers.
- Key flows: auth screens under `Revolt/Pages/Login/`, channel + message UI under `Revolt/Pages/Channel/`, settings under `Revolt/Pages/Settings/`, and Discover servers under `Revolt/Components/Home/Discover/` (CSV-backed server list with membership cache for peptide.chat).
- Data flow: `Revolt/Api/` → `Types/` → view models (ex: `Revolt/Pages/.../*ViewModel.swift`) → views (`Revolt/Pages/`, `Revolt/Components/`).

### State Management
- `ViewState` (`Revolt/ViewState.swift`) is a singleton `ObservableObject` managing global app state (users, channels, messages, websocket connection, etc.).
- ViewState persists data to UserDefaults and Keychain, with debounced saves for performance.
- Memory management: automatic cleanup of old messages/users with configurable limits (maxMessagesInMemory, maxUsersInMemory).
- **ViewState Extensions** (`Revolt/ViewState+Extensions/`): The ViewState class is split across multiple extension files for easier navigation:
  - `ViewState+Types.swift` - Supporting types: `LoginState`, `MainSelection` (`.server`, `.dms`, `.discover`), `ChannelSelection`, `NavigationDestination`, `QueuedMessage`, etc.
  - `ViewState+Memory.swift` - Memory limits, cleanup, and preloading (`enforceMemoryLimits`, `smartMessageCleanup`, `cleanupChannelFromMemory`, etc.)
  - `ViewState+WebSocketEvents.swift` - WebSocket event processing (`processEvent` switch and event handlers)
  - `ViewState+UsersAndDms.swift` - User/DM loading (`processUsers`, `loadUsersForDmBatch`, `processDMs`, etc.)
  - `ViewState+Navigation.swift` - Selection and navigation (`selectServer`, `selectChannel`, `selectDm`, `handleChannelChange`)
  - `ViewState+Unreads.swift` - Unread counts and badges (`getUnreadCountFor`, `cleanupStaleUnreads`, `forceMarkAllAsRead`)
  - `ViewState+Auth.swift` - Authentication (`signIn`, `signOut`, `destroyCache`). `signOut()` calls `clearAllDraftsForCurrentAccount()` before setting `state = .signedOut`; `destroyCache()` calls it again at the very start, then flushes `MessageCacheWriter` with bounded timeout and clears message cache and in-memory state.
  - `ViewState+ServerCache.swift` - Server cache persistence (`loadServersCacheSync`, `saveServersCacheAsync`)
  - `ViewState+ReadyEvent.swift` - Ready event processing (`extractNeededDataFromReadyEvent`, `processReadyData`). Binds message cache session via `MessageCacheWriter.shared.setSession(userId:baseURL:)` when connected; also loads draft storage via `loadDraftsFromUserDefaults(userId:baseURL:)` so drafts are session-bound.
  - `ViewState+Notifications.swift` - Push tokens and app badge (`updateAppBadgeCount`, `retryUploadNotificationToken`)
  - `ViewState+QueuedMessages.swift` - Message queuing (`queueMessage`, `trySendingQueuedMessages`)
  - `ViewState+Drafts.swift` - Draft message storage (composer text per channel). Session-bound: loaded in `processReadyData`, cleared in `signOut()` and at the start of `destroyCache()`. Methods: `saveDraft(channelId:text:)`, `loadDraft(channelId:)`, `clearDraft(channelId:)`, `clearAllDraftsForCurrentAccount()`. UserDefaults key `channelDrafts_\(userId)_\(baseURL)`; text-only (no reply/edit context).
  - `ViewState+DMChannel.swift` - DM channel operations (`deactivateDMChannel`, `closeDMGroup`, `removeChannel`)
  - `ViewState+MembershipCache.swift` - Discover server membership cache (`loadMembershipCacheSync`, `saveMembershipCacheAsync`, `updateMembershipCache`) for instant Discover UI on launch and sync across devices via WebSocket

### View Model Pattern
- `BaseViewModel<State, Action>` (`Revolt/Pages/Features/Core/BaseViewModel.swift`) provides MVVM foundation with `UiAction` and `UiEvent` protocols.
- View models extend `BaseViewModel` and implement `send(action:)` for state updates.
- Used in feature screens under `Revolt/Pages/Features/`.

### Local Caching
- **MessageCacheWriter** (`Revolt/1Storage/MessageCacheWriter.swift`): Single serialized, session-scoped cache write path. All cache writes from ViewModel, WebSocket events, MessageInputHandler, RepliesManager, and MessageContentsView go through this writer to prevent races and cross-account leakage. Session is bound via `setSession(userId:baseURL:)` (called from `ViewState+ReadyEvent` when connected); on sign-out, `ViewState.destroyCache()` calls `invalidate(flushFirst: true)` to flush pending writes with a bounded timeout (e.g. 4s) then clear caches. When adding new cache write call sites, use the writer’s `enqueue*` methods rather than writing directly to `MessageCacheManager`.
- **MessageCacheManager** (`Revolt/1Storage/MessageCacheManager.swift`): SQLite-based local message cache. Handles reads (`loadCachedMessages`, `loadCachedUsers`, `cachedMessageCount`, `hasCachedMessages`) and internal write implementation; all persistent writes are invoked via `MessageCacheWriter`. Schema v2 is multi-tenant (messages, users, channel_info, tombstones keyed by `channel_id` + `user_id` + `base_url`); soft deletes use a tombstones table. Caches messages, users, and channel metadata with automatic cleanup and preloading of frequently accessed channels.
- **Draft messages** (`ViewState+Drafts.swift`, `ViewState.channelDrafts`): Per-channel composer text only; stored in UserDefaults under `channelDrafts_\(userId)_\(baseURL)`. Not part of the message cache. Session-bound: loaded in `processReadyData` after `setSession`; cleared in `signOut()` and at the start of `destroyCache()`. Saved on leave (viewDidDisappear before cleanup) and via debounced typing; cleared at commit-to-send (offline and online) in `MessageInputHandler`. Restored in `viewWillAppear` when non-empty; when nil/empty the composer is not cleared (preserves same-channel return and return-from-search). See `DraftMessage.md` for full plan and implementation notes.

### Manager Pattern
- Complex view controllers (e.g., `MessageableChannelViewController`) use dedicated manager classes:
  - `PermissionsManager` - Handles channel permissions and UI configuration
  - `RepliesManager` - Manages message replies and reply UI
  - `TypingIndicatorManager` - Manages typing indicators
  - `ScrollPositionManager` - Handles scroll position preservation
  - `MessageGroupingManager` - Groups consecutive messages from same author
  - `MessageLoader` - Handles message loading and pagination
  - `PendingAttachmentsManager` - Manages pending attachments in the message composer before send

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
- `Sentry.md` - Sentry crash report analysis, root causes, and fix recommendations (scroll/Navigation guards, memory management).
- `ForceUnwrap.md` - Force unwrap audit (`!`, `as!`, `try!`) by risk level and file location; use when hardening crash-prone paths.
- `DraftMessage.md` - Message drafts implementation plan and implementation log: composer text saved per channel, session-bound storage, save/restore/clear touchpoints, and what was changed in the codebase (if present in repo; may be gitignored).

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

## Commit & Pull Request Guidelines
- Commit messages in history are short, sentence-style summaries (no conventional prefix); follow that pattern.
- PRs should include: a brief summary, testing performed, and screenshots or recordings for UI changes.
- Link related issues or tickets when applicable.

## Security & Configuration Tips
- Avoid committing secrets (tokens, API keys). Use environment variables or Xcode build settings for local overrides.
- When modifying entitlements or provisioning (`Revolt/Revolt.entitlements`), document the reason in the PR.
- Session tokens are stored in Keychain via `KeychainAccess` library.
- UserDefaults is used for non-sensitive app state persistence (with debounced saves for performance).

## Performance Considerations
- Message caching: `MessageCacheManager` provides instant message loading from SQLite cache. All cache writes go through `MessageCacheWriter` for serialization and session safety; sign-out flushes pending writes with a bounded timeout before clearing caches.
- Discover membership cache: `ViewState+MembershipCache` persists server join/leave state to disk for instant Discover UI on launch; updated on join/leave events (local or via WebSocket).
- Memory management: ViewState implements automatic cleanup of old messages/users to prevent memory issues.
- Debounced saves: Large data structures (users, emojis, messages) use debounced UserDefaults saves to prevent UI blocking.
- Background operations: Heavy operations (cache updates, data encoding) are performed on background queues.
- Channel preloading: Important channels are preloaded in the background for faster access.

## Code Organization Notes
- **ViewState refactoring**: The main `ViewState.swift` file contains class properties and init. Logic is split into extension files in `Revolt/ViewState+Extensions/` for easier navigation and maintainability.
- When adding new ViewState functionality, place it in the appropriate extension file based on responsibility (e.g., memory-related code in `ViewState+Memory.swift`).
- **Message cache writes**: Any new code that should persist messages/users to the SQLite cache must use `MessageCacheWriter.shared` (e.g. `enqueueCacheMessagesAndUsers`, `enqueueUpdateMessage`, `enqueueDeleteMessage`), not direct `MessageCacheManager` write APIs, to avoid races and cross-account leakage.
- **Scroll/Navigation safety**: When modifying `MessageableChannelViewController`, `ScrollPositionManager`, or `MessageableChannelViewController+TargetMessage`, guard scroll operations: ensure `tableView.dataSource != nil` and target row index is valid before `scrollToRow(at:animated:)`. Cancel pending scroll `DispatchWorkItem`s in `viewWillDisappear` to avoid crashes during navigation (see `Sentry.md`).
- **Draft messages**: Implemented per `DraftMessage.md`. Draft storage lives in `ViewState+Drafts.swift` and `ViewState.channelDrafts`; do not use the message cache for drafts. Clear drafts at commit-to-send (in `MessageInputHandler`), not only after API success; clear on sign-out in both `signOut()` and at the start of `destroyCache()`. When restoring in `viewWillAppear`, if there is no stored draft do not clear the composer (same-channel return and return-from-search). Debounced save uses `draftSaveWorkItem` in `MessageableChannelViewController`; cancel it in `viewWillDisappear`.