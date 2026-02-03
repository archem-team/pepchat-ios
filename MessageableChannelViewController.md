# MessageableChannelViewController — Overview & Refactoring Guide

This document explains `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` (~8k lines) and how to refactor it by moving code into extensions and other files for easier navigation. Use `AGENTS.md` for project structure and conventions.

---

## 1. What Is MessageableChannelViewController?

`MessageableChannelViewController` is the main UIKit view controller for **messageable channels** (text channels, DMs, group DMs). It:

- Shows the **message list** (UITableView) with cells, grouping, and prefetching
- Handles **message input** (MessageInputView), keyboard, mentions, replies
- Manages **loading** (initial load, load more, target-message load, nearby load)
- Handles **scroll** (to bottom, to target message, position preservation when inserting at top)
- Integrates **NSFW overlay**, **typing indicators**, **permissions**, **replies UI**
- Coordinates with **ViewState** for messages, users, channels, and navigation

It conforms to:

- `UITextFieldDelegate`, `NSFWOverlayViewDelegate`, `UIGestureRecognizerDelegate`
- Plus `UIScrollViewDelegate`, `UITableViewDelegate`, etc. (some in extensions)

---

## 2. Current Structure (MARK Sections)

Approximate locations of major sections in the main file:

| MARK / Area | Approx. Lines | Responsibility |
|-------------|---------------|-----------------|
| Class + properties + init | 1–315 | Properties, managers, target-message protection, `safeScrollToRow`, `viewDidLoad` setup |
| Setup (header, table, input, bindings, observers) | ~316–1850 | `setupCustomHeader`, `setupTableView`, `setupMessageInput`, `setupNewMessageButton`, `setupBindings`, `setupKeyboardObservers`, `setupAdditionalMessageObservers`, notification handlers, `setupSwipeGesture` |
| UIGestureRecognizerDelegate | ~1813–1832 | Gesture recognizer delegate methods |
| Table view setup + observeValue + deinit | ~1833–1990 | `setupTableView`, KVO for contentSize, `deinit` cleanup |
| New message button + lifecycle | ~559–800, 655–720 | `setupNewMessageButton`, `showNewMessageButton`, `prefersStatusBarHidden`, `viewDidAppear` |
| messagesDidChange + refreshMessages | ~1998–3310 | Message change handling, `refreshMessages`, target-message checks after refresh |
| Mark Unread Protection | ~2467–2630 | `disableAutoAcknowledgment`, `markLastMessageAsSeen`, retry queue, rate limiting |
| loadMoreMessages / loadMoreMessagesIfNeeded | ~2399–2710, 2705+ | Pagination: load older messages |
| loadInitialMessages / loadRegularMessages | ~3587–3920 | Initial and “regular” message load |
| loadMessagesNearby / refreshWithTargetMessage | ~4916–5160, 5856+ | Target-message and “nearby” loading |
| NSFW + Image Handling | ~3044–3060 | `showNSFWOverlay`, `nsfwOverlayViewDidConfirm`, `showFullScreenImage` |
| setupMessageInput | ~3062–3104 | Message input and reply container setup |
| Replies Handling + Fetch Message for Reply | ~4270–4370 | `addReply`/`removeReply`/`clearReplies`, `fetchMessageForReply`, `fetchUserForMessage`, `checkAndFetchMissingReplies` |
| Reply click / scroll to message | ~6286–6468 | `handleReplyClick`, `scrollToMessage`, `highlightMessageBriefly`, `addReply` (Message), `showReplies` |
| Table bouncing + insets + position | ~6664–6805 | `updateTableViewBouncing`, `positionTableAtBottomBeforeShowing`, `showTableViewWithFade` |
| Skeleton Loading | ~6806–6851 | `showSkeletonView`, `hideSkeletonView` |
| Global Fix (Black Screen) | ~6852–6900+ | `applyGlobalFix` |
| Scroll Position Preservation | ~7276–7440 | `maintainScrollPositionAfterInsertingMessages`, `AnchorCellInfo`, `findAnchorCellBeforeInsertion`, `restoreScrollPositionToAnchor`, `maintainScrollPositionWithMessageAnchor`, `scrollToReferenceMessageWithRetry` |
| Scroll to target / reference | ~5160, 6946, 7493+ | `scrollToTargetMessage`, `scrollToReferenceMessageWithRetry`, `attemptScrollToReference` |
| TypingIndicatorView (comment) | ~7749 | Moved to manager |
| Empty State | ~7763–7933 | `showEmptyStateView`, `hideEmptyStateView` (extension in same file) |
| NotificationBanner (private class) | ~7935–8010 | In-file private class |
| generateMessageLink (private global) | ~8016–8045 | Private function at end of file |

There are also many other methods (e.g. `loadInitialMessagesImmediate`, `loadUsersForVisibleMessages`, various scroll/table helpers) interspersed in the ranges above.

---

## 3. What’s Already Extracted

The file header and comments already document extracted pieces. Use these as the pattern for further extractions.

### 3.1 Managers (`Messagable/Managers/`)

- **PermissionsManager** — Channel permissions and UI configuration
- **RepliesManager** — Reply UI and reply list
- **TypingIndicatorManager** — Typing indicators
- **ScrollPositionManager** — Scroll position preservation (partial; see below)
- **MessageGroupingManager** — Grouping consecutive messages by author
- **MessageLoader** — Message loading/pagination (if used)
- **MessageInputHandler** — Input handling (in `Utils/`)

### 3.2 Models (`Messagable/Models/`)

- **ReplyMessage**, **MessageableChannelConstants**, **MessageableChannelErrors**

### 3.3 Views (`Messagable/Views/`)

- **ToastView**, **NSFWOverlayView**

### 3.4 Utils (`Messagable/Utils/`)

- **MessageInputHandler**

### 3.5 Extensions (`Messagable/Extensions/`)

- **MessageableChannelViewController+Extensions.swift** — `showErrorAlert`, `UITableViewDataSourcePrefetching`, extra memory/helpers
- **MessageableChannelViewController+Keyboard.swift** — Keyboard observers and layout
- **MessageableChannelViewController+MessageCell.swift** — Message cell–related logic
- **MessageableChannelViewController+NSFW.swift** — NSFW-specific logic (if any beyond overlay)
- **MessageableChannelViewController+Permissions.swift** — Permission-related UI (or delegates to PermissionsManager)
- **MessageableChannelViewController+ScrollView.swift** — `UIScrollViewDelegate` (scroll events, load-more trigger)
- **MessageableChannelViewController+TableView.swift** — `UITableViewDelegate` and table behavior
- **MessageableChannelViewController+TextView.swift** — `UITextViewDelegate` for input

### 3.6 Other Files in Messagable/

- **MessageableChannelViewController+NotificationBanner.swift** — Notification banner (or similar) if split out
- **MessageableChannelViewControllerRepresentable.swift** — SwiftUI wrapper

So: a lot of **protocol conformance** and **focused behavior** is already in extensions; the remaining bulk is **setup**, **lifecycle**, **message loading**, **scroll/target-message logic**, **replies fetch**, **mark-unread**, **empty state**, and **bouncing/insets/skeleton/global fix**.

---

## 4. Refactoring Plan — What to Move Where

Goal: **keep the main file as “core + wiring”** and move **coherent blocks** into **extensions** (or helpers/managers) so navigation and reviews are easier. No behavior change; only file organization.

### 4.1 New Extensions (in `Messagable/Extensions/`)

| New extension file | What to move | Rationale |
|--------------------|--------------|------------|
| **MessageableChannelViewController+Setup.swift** | `setupCustomHeader`, `setupTableView`, `setupMessageInput`, `setupNewMessageButton`, `setupSwipeGesture`, `setupBindings`, `setupKeyboardObservers`, `setupAdditionalMessageObservers`, and any small setup helpers used only by these | All “one-time setup” in one place; main file keeps init + `viewDidLoad` calling these. |
| **MessageableChannelViewController+Lifecycle.swift** | `viewDidAppear`, `viewWillDisappear`, `observeValue(forKeyPath:…)`, `deinit`, and any other lifecycle/observer teardown | Clear lifecycle and KVO in one file. |
| **MessageableChannelViewController+MessageLoading.swift** | `loadInitialMessages`, `loadRegularMessages`, `loadInitialMessagesImmediate`, `loadMoreMessages`, `loadMoreMessagesIfNeeded`, `loadMoreMessages(before:server:messages)`, `loadNewerMessages(after:)`, `loadMessagesNearby`, `loadUsersForVisibleMessages`, and any small helpers used only for loading | All “load messages” entry points and helpers in one place. |
| **MessageableChannelViewController+TargetMessage.swift** | Target-message logic: `scrollToTargetMessage`, `scrollToTargetMessage(_:animated:)`, `refreshWithTargetMessage`, `scrollToReferenceMessageWithRetry`, `attemptScrollToReference`, `scrollToMessage(messageId:)`, `scrollToReferenceMessageWithRetry`, plus properties like `targetMessageId`, `targetMessageProcessed`, `clearTargetMessageTimer`, `lastTargetMessageHighlightTime`, `isInTargetMessagePosition`, and methods `activateTargetMessageProtection`, `clearTargetMessageProtection`, `debugTargetMessageProtection`, `safeScrollToRow`, `logScrollToBottomAttempt` | Single place for “scroll to message” and “target message” behavior; main file can keep a minimal facade if needed. |
| **MessageableChannelViewController+ScrollPosition.swift** | Scroll position preservation: `maintainScrollPositionAfterInsertingMessages`, `AnchorCellInfo`, `findAnchorCellBeforeInsertion`, `restoreScrollPositionToAnchor`, `maintainScrollPositionWithMessageAnchor` | Complements existing ScrollView extension; keeps “insert-at-top” scroll preservation in one file. |
| **MessageableChannelViewController+MarkUnread.swift** | Mark-unread protection: `disableAutoAcknowledgment`, `markLastMessageAsSeen`, `extractRetryAfter`, `addToRetryQueue`, `processRetryQueue`, `RetryTask`, and related properties (`lastMessageSeenTime`, `messageSeenThrottleInterval`, `isAcknowledgingMessage`, `retryQueue`, `isAutoAckDisabled`, etc.) | Isolated “mark read” / “unread protection” behavior. |
| **MessageableChannelViewController+Replies.swift** | Reply fetching and UI: `fetchMessageForReply`, `fetchUserForMessage`, `checkAndFetchMissingReplies`, `handleReplyClick`, `highlightMessageBriefly`, `showReplies`, and the duplicate `addReply(_ message: Types.Message)` (deprecated) | Keeps “fetch for reply” and “reply click → scroll” in one place; thin wrappers can stay in main if they just call RepliesManager. |
| **MessageableChannelViewController+TableBouncing.swift** | Table bouncing and insets: `updateTableViewBouncing`, `positionTableAtBottomBeforeShowing`, `showTableViewWithFade`, and any inset/adjustment helpers used only here | Single place for “when do we bounce / show bottom” and related layout. |
| **MessageableChannelViewController+Skeleton.swift** | `showSkeletonView`, `hideSkeletonView` | Small, self-contained. |
| **MessageableChannelViewController+GlobalFix.swift** | `applyGlobalFix` and any small helpers only used by it | Isolates “black screen” recovery logic. |
| **MessageableChannelViewController+EmptyState.swift** | Move the **in-file** `showEmptyStateView` / `hideEmptyStateView` extension (and any empty-state helpers) into this dedicated extension file | Matches existing comment “Moved to MessagableChannelViewController+Extensions” by actually moving to a named EmptyState file. |
| **MessageableChannelViewController+Notifications.swift** | All `@objc` notification handlers: `handleNewMessages`, `handleNetworkError`, `handleChannelSearchClosed`, `handleVideoPlayerDismiss`, `handleNewSocketMessage`, `handleChannelSearchClosing`, `handleMemoryWarning`, `handleSystemLog`, `checkForScrollNeeded`, and any other `NotificationCenter` selectors | One place for “reaction to notifications”; main file only adds/removes observers. |

Optional:

- **MessageableChannelViewController+NewMessageButton.swift** — `setupNewMessageButton`, `newMessageButtonTapped`, `showNewMessageButton` (and related state) if you want the “new message” UI isolated.

### 4.2 Move Out of the Main File (Not Extensions)

| Target | What to move | Rationale |
|--------|--------------|------------|
| **Managers/** (e.g. **TargetMessageManager.swift**) | If target-message logic grows further, consider a **TargetMessageManager** that owns `targetMessageId`, protection state, timers, and scroll-to-message; VC calls into it. | Same pattern as PermissionsManager / RepliesManager; keeps VC thinner. |
| **MessageableChannelViewController+NotificationBanner.swift** (or **Views/**) | The **private class NotificationBanner** at the end of the main file | Reusable UI component; doesn’t need to live in the VC file. |
| **Utils/** or **Messagable/Utils/** | **generateMessageLink** (private global function at end of file) | Pure helper; no need to be in VC. |

### 4.3 What to Keep in the Main File

- Class declaration and **all stored properties** (extensions can’t add stored properties in Swift).
- **init**, **viewDidLoad** (calling setup methods from extensions).
- **messagesDidChange** and **refreshMessages** can stay in main file initially (they’re central); optionally move to something like `MessageableChannelViewController+Messages.swift` later.
- Any minimal “routing” methods that only call into managers or extensions.
- **loadingHeaderView** and other lazy UI that’s used across several extensions (or define in one extension and use from others).

After refactoring, the main file should mostly contain:

- Property declarations
- init / viewDidLoad
- High-level flow (e.g. “on message change → refreshMessages”)
- Delegation to managers and extensions

---

## 5. Navigation Tips (AGENTS.md)

- **Managers:** `Revolt/Pages/Channel/Messagable/Managers/`
- **Extensions:** `Revolt/Pages/Channel/Messagable/Extensions/`
- **Models:** `Revolt/Pages/Channel/Messagable/Models/`
- **Views:** `Revolt/Pages/Channel/Messagable/Views/`
- **Utils:** `Revolt/Pages/Channel/Messagable/Utils/`
- **ViewState** is split by responsibility in `Revolt/ViewState+Extensions/`; the same “one concern per file” idea applies here.

When adding new behavior:

- Prefer a **new extension** for a new concern (e.g. target message, mark unread, empty state) rather than appending to the 8k-line file.
- If a group of methods and state grows large, consider a **Manager** (e.g. TargetMessageManager) and keep the VC as a thin coordinator.

---

## 6. Suggested Order of Refactors

1. **MessageableChannelViewController+EmptyState.swift** — Move the existing empty-state extension out of the main file (quick win).
2. **MessageableChannelViewController+Setup.swift** — Move all `setup*` methods; main file keeps only `viewDidLoad` and calls.
3. **MessageableChannelViewController+Notifications.swift** — Move all notification handlers.
4. **MessageableChannelViewController+MarkUnread.swift** — Isolate mark-unread and retry queue.
5. **MessageableChannelViewController+MessageLoading.swift** — Move all load methods.
6. **MessageableChannelViewController+TargetMessage.swift** — Move target-message and scroll-to-message logic.
7. **MessageableChannelViewController+ScrollPosition.swift** — Move scroll-position preservation.
8. **MessageableChannelViewController+Replies.swift** — Move reply fetch and reply-click handling.
9. **MessageableChannelViewController+TableBouncing.swift**, **+Skeleton.swift**, **+GlobalFix.swift** — Small, independent pieces.
10. Extract **NotificationBanner** and **generateMessageLink** to their own types/files.

This order minimizes merge conflicts and keeps each step reviewable. After refactors, the main `MessageableChannelViewController.swift` should be much shorter and easier to navigate, with behavior unchanged.
