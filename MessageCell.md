# MessageCell — Overview & Refactoring Guide

This document explains `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift` (~4.6k+ lines) and how to refactor it by moving code into extensions and other files for easier navigation. Use `AGENTS.md` for project structure and conventions.

---

## 1. What Is MessageCell?

`MessageCell` is the main `UITableViewCell` subclass used to display a **single message** in messageable channels (text channels, DMs, group DMs). It:

- Renders **message content** (text with markdown, links, mentions, custom/Unicode emoji)
- Shows **reply preview** (author + snippet of replied message, tap to scroll)
- Displays **image attachments** (grid layout with tap-to-fullscreen)
- Displays **file attachments** (audio player, video player, generic file rows)
- Shows **link embeds** (LinkPreviewView)
- Renders **reactions** (emoji + count, tappable)
- Supports **swipe-to-reply**, **long-press context menu** (edit, delete, copy, reply, etc.)
- Handles **continuation** (grouped messages: hide avatar/username for consecutive messages from same author)
- Handles **pending** (optimistic) messages with visual state
- Integrates with **ViewState** for users, emojis, URLs, and navigation

It conforms to:

- `UITextViewDelegate` (link taps, URL handling)
- `AVPlayerViewControllerDelegate` (video cleanup, PiP)
- `UIGestureRecognizerDelegate` (pan/long-press/tap behavior)

---

## 2. Current Structure (MARK Sections)

Approximate locations of major sections in the main file:

| MARK / Area | Approx. Lines | Responsibility |
|-------------|---------------|----------------|
| Class + properties + init | 1–122 | Stored properties (views, reply UI, reactions, swipe state, callbacks), `MessageAction` enum, `init`, `required init(coder:)` |
| prepareForReuse | 124–256 | Reset all content, cancel downloads, clean attachments/reactions/embeds, clear constraints, cleanup temp videos |
| Cleanup Helper | 258–274 | `cleanupTempVideos()` |
| setupUI | 276–468 | Create and constrain: reply view, avatar, username, time, bridge badge, contentLabel, reactions container |
| updateAppearanceForContinuation | 470–556 | Toggle avatar/username visibility and constraints for continuation vs first-in-group |
| updatePendingAppearance | 558–587 | Pending message opacity and clock indicator |
| loadEmbeds | 589–641 | Link preview embeds (LinkPreviewView) |
| setupGestureRecognizer / setupSwipeGestureRecognizer | 636–671 | Long press, link long press, tap, pan; `setupSwipeReplyIcon()` |
| Swipe (handlePanGesture, updateSwipeReplyIcon, triggerReplyAction) | 625–831 | Swipe-to-reply logic |
| handleContentTap / handleLinkLongPress / showLinkContextMenu | 833–~950 | Content tap, link long press, link context menu (copy, open) |
| handleLongPress | ~949–~1130 | Message context menu (edit, delete, copy, reply, mention, etc.) |
| configure(with:author:member:viewState:isContinuation:) | 1134–~1520 | Main configuration: set message/author, reply preview, content (markdown/emoji), attachments, embeds, reactions, layout |
| loadImageAttachments | 1526–1771 | Image grid layout, Kingfisher loading, tap handler |
| **File Attachments Support** | 1773–2790 | `isImageFile`, `isAudioFile`, `isVideoFile`, `loadFileAttachments` (audio/video/file rows), video window/PiP, loading overlays |
| **Reactions Management** | 2792–3338 | `updateReactions`, reaction buttons, `createSimpleReactionButton`, `setupReactionsContainerConstraints`, `layoutReactionsWithFlowLayout`, reaction tap handlers |
| **Markdown Processing Helpers** | 3340–3381 | `removeEmptyMarkdownLinks(from:)` |
| **Audio Duration Preloading** | 3384–3426 | `preloadAudioDurations(for:viewState:)` |
| Helpers (tempVideoURLs, createLoadingView, clearDynamicConstraints, etc.) | 3428–3955 | Temp video storage, loading view, constraint cleanup, `checkCanReply`, etc. |
| **AVPlayerViewControllerDelegate** (extension) | 3957–4025 | PiP/dismiss/fullscreen cleanup, video window teardown |
| **UITextViewDelegate** (extension) | 4028–4533 | URL interaction (mention, invite, link open), link handling |
| **UIGestureRecognizerDelegate** (extension) | 4536–4605 | Pan/long-press/tap should-begin and simultaneous recognition |
| **Safe Array Access** (extension on Array) | 4608–4615 | `Array[safe:]` subscript |

There are also: reply loading (fetch message for reply, show loading, timeout), `handleReplyTap`, `handleAvatarTap`, `handleUsernameTap`, `findParentViewController`, and various constraint helpers scattered in the ranges above.

---

## 3. Refactoring Plan — What to Move Where

Goal: **keep the main file as “cell declaration + stored properties + init + prepareForReuse + setupUI + configure”** and move **coherent blocks** into **extensions** (and, where useful, helpers or small types) so navigation and reviews are easier. No behavior change; only file organization.

Swift **extensions cannot add stored properties**. So all stored properties (e.g. `messageContentView`, `avatarImageView`, `contentLabel`, `replyView`, `reactionsContainerView`, `imageAttachmentsContainer`, `fileAttachmentsContainer`, swipe state, `currentMessage`, `viewState`, etc.) must remain in the main `MessageCell.swift` file.

### 3.1 Extensions (in `Messagable/Views/` or `Messagable/Views/MessageCell/`)

Suggested extension files next to or under `MessageCell.swift`:

| Extension file | What to move | Rationale |
|----------------|--------------|-----------|
| **MessageCell+Setup.swift** | `setupUI` (full method), `setupGestureRecognizer`, `setupSwipeGestureRecognizer`, `setupSwipeReplyIcon` | All one-time view and gesture setup in one place; main file keeps init calling these. |
| **MessageCell+Layout.swift** | `updateAppearanceForContinuation`, `updatePendingAppearance`, `clearContentLabelBottomConstraints`, `clearDynamicConstraints`, `clearReactionsContainerConstraints`, and any other constraint/layout helpers used only by the cell | Continuation/pending and dynamic constraint logic in one place. |
| **MessageCell+Reply.swift** | Reply UI and behavior: reply view config in configure, `handleReplyTap`, reply loading (show/hide indicator, timeout), fetch message for reply, `currentReplyId` usage | Reply preview and “tap to scroll to message” in one file. |
| **MessageCell+Attachments.swift** | `loadImageAttachments`, `loadFileAttachments`, `loadEmbeds`, `isImageFile`, `isAudioFile`, `isVideoFile`, image tap handler, file attachment creation (audio/video/generic), loading overlays, temp video cleanup | All attachment rendering and cleanup in one place. |
| **MessageCell+Reactions.swift** | `updateReactions`, `createSimpleReactionButton`, `setupReactionsContainerConstraints`, `layoutReactionsWithFlowLayout`, reaction button tap/release handlers | Reactions UI and layout in one file. |
| **MessageCell+Content.swift** | Content text: markdown/attributed string building, `removeEmptyMarkdownLinks`, `processCustomEmojis` (emoji processing), `preloadAudioDurations`, and any helpers used only for content rendering | Text and emoji processing in one place. |
| **MessageCell+ContextMenu.swift** | `handleLongPress`, `showLinkContextMenu`, message context menu (edit, delete, copy, reply, mention, mark unread, copy link, copy id, react), `checkCanReply` if used only here | Long-press and context menu logic in one file. |
| **MessageCell+Swipe.swift** | `handlePanGesture`, `updateSwipeReplyIcon`, `triggerReplyAction`, handleContentTap, handleLinkLongPress (or keep link in ContextMenu if preferred) | Swipe-to-reply and content/link gestures in one place. |
| **MessageCell+AVPlayer.swift** | Already an extension in file: move the whole `extension MessageCell: AVPlayerViewControllerDelegate` block to **MessageCell+AVPlayer.swift** | Protocol conformance and video cleanup isolated. |
| **MessageCell+TextViewDelegate.swift** | Move the whole `extension MessageCell` (UITextViewDelegate) block to **MessageCell+TextViewDelegate.swift** | Link/mention handling in one file. |
| **MessageCell+GestureRecognizer.swift** | Move the whole `extension MessageCell` (UIGestureRecognizerDelegate) block to **MessageCell+GestureRecognizer.swift** | Gesture delegate logic in one file. |

### 3.2 Move Out of MessageCell (Not Extensions)

| Target | What to move | Rationale |
|--------|--------------|-----------|
| **Utils/** or **Messagable/Utils/** | `extension Array { subscript(safe:) }` — move to e.g. `Array+SafeSubscript.swift` or a general `SafeArray.swift` | It’s a global Array extension; reusable and not specific to MessageCell. |
| **Messagable/Utils/** (optional) | `removeEmptyMarkdownLinks(from:)` could be a free function or a small `MarkdownHelpers` type if used elsewhere | Reuse for other message/text UI. |

### 3.3 What to Keep in the Main File

- Class declaration and **all stored properties**.
- **init**, **required init(coder:)**, **prepareForReuse** (can call into extension methods for cleanup if you split cleanup helpers).
- **configure(with:author:member:viewState:isContinuation:)** — or move to **MessageCell+Configure.swift** and keep main file to a short “configure” that calls into the extension.
- **MessageAction** enum and callback properties (`onMessageAction`, `onImageTapped`, etc.).
- **deinit** (cleanup of timers/alerts).
- Optionally: minimal “routing” methods that only call into extensions.

After refactoring, the main `MessageCell.swift` should mostly contain:

- Property declarations  
- init / prepareForReuse / deinit  
- configure (or a thin wrapper)  
- High-level flow and callbacks  

---

## 4. Suggested Order of Refactors

1. **MessageCell+AVPlayer.swift** — Move existing `AVPlayerViewControllerDelegate` extension (no new logic).
2. **MessageCell+TextViewDelegate.swift** — Move existing `UITextViewDelegate` extension.
3. **MessageCell+GestureRecognizer.swift** — Move existing `UIGestureRecognizerDelegate` extension.
4. **Array+SafeSubscript.swift** (in Utils) — Move `Array[safe:]` out of MessageCell.
5. **MessageCell+Content.swift** — Markdown + emoji + audio preload helpers.
6. **MessageCell+Reactions.swift** — Reactions UI and layout.
7. **MessageCell+Attachments.swift** — Image, file, and embed loading.
8. **MessageCell+Reply.swift** — Reply preview and tap/loading.
9. **MessageCell+ContextMenu.swift** — Long-press and context menus.
10. **MessageCell+Swipe.swift** — Swipe-to-reply and content/link gestures.
11. **MessageCell+Layout.swift** — Continuation/pending and constraint helpers.
12. **MessageCell+Setup.swift** — setupUI and gesture setup.

This order minimizes merge conflicts and keeps each step reviewable. After refactors, the main `MessageCell.swift` should be much shorter and easier to navigate, with behavior unchanged.

---

## 5. Navigation Tips (AGENTS.md)

- **Views:** `Revolt/Pages/Channel/Messagable/Views/` — MessageCell and its extensions can live here; optionally in a subfolder `Views/MessageCell/` (e.g. `MessageCell+Setup.swift`).
- **Utils:** `Revolt/Pages/Channel/Messagable/Utils/` — Shared helpers (e.g. `Array+SafeSubscript`, markdown helpers) if used by more than the cell.
- **ViewState** is split by responsibility in `Revolt/ViewState+Extensions/`; the same “one concern per file” idea applies to MessageCell.

When adding new behavior:

- Prefer a **new extension** for a new concern (e.g. reactions, attachments, swipe) rather than appending to the 4.6k-line file.
- If a group of methods grows large (e.g. file attachment types, video vs audio), consider a **helper type** or **manager** that the cell calls into, similar to the manager pattern used in `MessageableChannelViewController`.
