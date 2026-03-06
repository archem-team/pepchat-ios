# UIKit Implementation Guide

This document lists every file in the app that uses **UIKit** (Apple’s older UI framework) and explains what each one does in plain language, whether the same can be done in **SwiftUI**, and how hard it would be to convert.

**Audience:** Product, design, and non-engineers can use this to understand where UIKit is used and what migration would involve.

---

## How to read this document

- **What it does (simple):** What the user sees or what the feature does, in non-technical terms.
- **What it does (UI):** What appears on screen or how the interface behaves.
- **Can we do this in SwiftUI?** Yes / Partially / No, with a short reason.
- **Convert to SwiftUI:** How feasible and how much effort (Easy / Medium / Hard / Very hard).

---

# Part 1: Purely UIKit-based files

These files use **only** UIKit (no SwiftUI). They are the main candidates for a future SwiftUI migration.

---

## Messaging screen – main controller and list

### `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`  
*(Also in Part 2 – uses both SwiftUI and UIKit)*

- **What it does (simple):** This is the **main chat screen**. It shows the list of messages, the text box where you type, the channel name at the top, and buttons for back, search, and “scroll to bottom.” It also handles loading older messages when you scroll up, showing a loading state, and reacting to the keyboard.
- **What it does (UI):** Full-screen chat: scrollable message list (table), header bar, input area at the bottom, “new messages” button, reply bar, and optional skeleton/loading view.
- **Can we do this in SwiftUI?** Yes, but the message list would be rebuilt (e.g. with `LazyVStack` or `List`). Table behavior like scroll-position preservation and safe updates are more work in SwiftUI.
- **Convert to SwiftUI:** **Hard.** Large file, many behaviors (scroll, keyboard, replies, loading, navigation). Would likely be split into several SwiftUI views and view models.

---

### `Revolt/Pages/Channel/Messagable/DataSources/MessageTableViewDataSource.swift`

- **What it does (simple):** Tells the message table **how many rows** there are and **what to show in each row** (normal message cell or system message cell). It’s the “data source” for the message list.
- **What it does (UI):** No visible UI by itself; it drives which cell type is used for each message (user message vs “User joined” style).
- **Can we do this in SwiftUI?** Yes. In SwiftUI you use a list of data and let the framework build rows; you don’t write a separate “data source” object.
- **Convert to SwiftUI:** **Easy.** Replaced by passing an array to a `List` or `LazyVStack` and switching on message type inside the row view.

---

### `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`

- **What it does (simple):** One **row in the chat**: avatar, username, message text, time, reply preview, images/files, and reactions. It also handles tap/long-press (reply, copy, delete, etc.) and swipe-to-reply.
- **What it does (UI):** A single message bubble: left side avatar + name/time, right side content (text, attachments, reply strip, reaction pills).
- **Can we do this in SwiftUI?** Yes. Same layout can be done with `HStack`/`VStack`, and gestures/context menus exist in SwiftUI.
- **Convert to SwiftUI:** **Medium.** Lots of layout and gesture logic; needs careful reimplementation but no UIKit-only concepts.

---

### `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Setup.swift`  
### `MessageCell+Layout.swift`  
### `MessageCell+Content.swift`  
### `MessageCell+Attachments.swift`  
### `MessageCell+Reply.swift`  
### `MessageCell+Reactions.swift`  
### `MessageCell+ContextMenu.swift`  
### `MessageCell+GestureRecognizer.swift`  
### `MessageCell+Swipe.swift`  
### `MessageCell+TextViewDelegate.swift`  
### `MessageCell+AVPlayer.swift`

- **What they do (simple):** These are **extensions** of `MessageCell`. Each adds one piece: **Setup** (creating subviews), **Layout** (positioning), **Content** (filling text/content), **Attachments** (images/files), **Reply** (reply preview), **Reactions** (emoji pills), **ContextMenu** (long-press menu), **GestureRecognizer** (taps), **Swipe** (swipe to reply), **TextViewDelegate** (links/mentions in text), **AVPlayer** (inline video).
- **What they do (UI):** They define how that one part of the message row looks and behaves.
- **Can we do this in SwiftUI?** Yes. Each concern maps to SwiftUI views and modifiers (e.g. context menu, gestures, `Text`/attributed content).
- **Convert to SwiftUI:** **Medium** per extension. Easiest: Layout, Content, Attachments, Reply, Reactions. More care: Swipe, ContextMenu, TextViewDelegate (rich text/links), AVPlayer (wrap `AVPlayerViewController` in SwiftUI).

---

### `Revolt/Pages/Channel/Messagable/Views/SystemMessageCell.swift`

- **What it does (simple):** A **special row** for system messages like “User joined the channel” or “User left.” Centered, muted text, no avatar or actions.
- **What it does (UI):** One centered line of gray text in the message list.
- **Can we do this in SwiftUI?** Yes. A simple centered `Text` in a `List` or stack.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`

- **What it does (simple):** The **text box and send area** at the bottom of the chat: text field, send button, attachment button, and (when replying) a reply bar. It also hosts the list of pending attachments (thumbnails before send).
- **What it does (UI):** Bottom bar with text input, attachment and send buttons, optional reply strip and attachment previews.
- **Can we do this in SwiftUI?** Yes. `TextField`/`TextEditor`, `Button`, and a horizontal list of thumbnails are standard in SwiftUI.
- **Convert to SwiftUI:** **Medium.** Logic for mentions, attachments, and focus is nontrivial but well within SwiftUI.

---

### `Revolt/Pages/Channel/Messagable/Views/ToastView.swift`

- **What it does (simple):** A **temporary popup** at the top of the screen (e.g. “Message copied,” “Link copied”). It fades in, stays for a couple of seconds, then fades out.
- **What it does (UI):** Small dark rounded bar at top center with white text.
- **Can we do this in SwiftUI?** Yes. Overlay view + `transition` and timer, or a library like SwiftUI’s overlay + state.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Views/TypingIndicatorView.swift`

- **What it does (simple):** Shows **“Someone is typing…”** (or a list of typers) above the message input when others are typing.
- **What it does (UI):** A thin bar with label and optional animated dots.
- **Can we do this in SwiftUI?** Yes. Simple `HStack` with `Text` and optional animation.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Views/NSFWOverlayView.swift`

- **What it does (simple):** When you open an **age-restricted (NSFW) channel**, this blocks the content with a dark overlay and a warning. You must tap “I’m over 18” to continue.
- **What it does (UI):** Full-screen dark overlay with icon, channel name, warning text, and a confirm button.
- **Can we do this in SwiftUI?** Yes. A full-screen overlay with `ZStack` and a button.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Views/RepliesContainerView.swift`

- **What it does (simple):** The **reply strip** that appears above the text box when you’re replying to a message: shows the original message snippet and a “close” (X) to cancel the reply.
- **What it does (UI):** Horizontal bar with a line, quoted text, and dismiss button.
- **Can we do this in SwiftUI?** Yes. `HStack` with border, text, and button.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Views/MessageOptionViewController.swift`

- **What it does (simple):** The **action sheet** when you long-press a message: quick emoji reactions at the top, then options like Reply, Copy, Edit, Delete, etc., depending on permissions.
- **What it does (UI):** Bottom sheet (or popover) with emoji row and a list of actions.
- **Can we do this in SwiftUI?** Yes. `.contextMenu` or a custom sheet with buttons.
- **Convert to SwiftUI:** **Medium.** Layout and permission-based options are straightforward; presentation is easy in SwiftUI.

---

## Links, embeds, and rich content

### `Revolt/Pages/Channel/Messagable/Views/LinkPreviewView.swift`  
### `Revolt/Pages/Channel/Messagable/Views/1LinkPreviewView.swift`

- **What they do (simple):** Show **link previews** for messages: when a message contains a link, they show a card with site icon, title, description, and optional image or video. Used for website embeds and similar content.
- **What they do (UI):** A card with left border, icon, title, description, and optional media.
- **Can we do this in SwiftUI?** Yes. Same layout with `VStack`/`HStack` and optional `AsyncImage` or video player.
- **Convert to SwiftUI:** **Medium.** Logic is the same; only the view layer changes.

---

### `Revolt/Pages/Channel/Messagable/Views/AttachmentPreviewView.swift`  
### `Revolt/Pages/Channel/Messagable/Views/1AttachmentPreviewView.swift`

- **What they do (simple):** **Thumbnails of attachments** you’re about to send (images/videos/documents) in the compose area. You can remove one by tapping X.
- **What they do (UI):** Small image/document tiles with a remove button.
- **Can we do this in SwiftUI?** Yes. ScrollView or HStack of thumbnails with overlay button.
- **Convert to SwiftUI:** **Easy.**

---

## Mention picker and text

### `Revolt/Pages/Channel/Messagable/Mention/MentionInputView.swift`

- **What it does (simple):** When you type **@** in the message box, this shows a **list of people** you can mention (filtered by what you type). Tapping a name inserts the mention.
- **What it does (UI):** A dropdown or overlay list of avatars and names above the keyboard.
- **Can we do this in SwiftUI?** Yes. Overlay list bound to cursor position and filtered by text; SwiftUI has the tools (e.g. `List`, focus, positioning).
- **Convert to SwiftUI:** **Medium.** Keyboard and positioning need attention; logic (filtering, selection) is reusable.

---

### `Revolt/Pages/Channel/Messagable/Utils/MarkdownProcessor.swift`

- **What it does (simple):** Turns **message text** into formatted display: bold, italics, code, lists, links. It uses UIKit’s attributed text (font, color) and caches results for performance.
- **What it does (UI):** No direct UI; it produces the styled text that message cells display.
- **Can we do this in SwiftUI?** Partially. SwiftUI has `AttributedString` and markdown in `Text`. For very rich or custom parsing you might keep a small UIKit/AttributedString path or use a SwiftUI-native approach.
- **Convert to SwiftUI:** **Medium.** Logic can stay; the part that uses `UIFont`/`UIColor` would be replaced by SwiftUI `Font`/`Color` or `AttributedString`.

---

## Scroll and table behavior

### `UITableView+ScrollPositionPreservation.swift`  
*(At repository root)*

- **What it does (simple):** When **new (older) messages are loaded at the top** of the chat, the table view inserts new rows above. This extension keeps the list from jumping so you stay looking at the same message.
- **What it does (UI):** Invisible; it adjusts scroll position after insertions so the content doesn’t jump.
- **Can we do this in SwiftUI?** Yes, but differently. SwiftUI’s `ScrollViewReader` and stable IDs, or a `LazyVStack` with an anchor, can achieve similar behavior.
- **Convert to SwiftUI:** **Medium.** Concept is the same; implementation uses SwiftUI scroll APIs.

---

### `Revolt/Pages/Channel/Messagable/Managers/ScrollPositionManager.swift`

- **What it does (simple):** Decides **when to scroll to the bottom** (e.g. after sending or when new messages arrive) and when *not* to (e.g. when the user has scrolled up to read). It also handles the “scroll to bottom” button and protects scroll-to-message from being overridden.
- **What it does (UI):** No visible UI; it controls when the list scrolls.
- **Can we do this in SwiftUI?** Yes. Same logic with `ScrollViewReader`, state for “user scrolled up,” and optional “scroll to bottom” button.
- **Convert to SwiftUI:** **Medium.** Logic is portable; only the scroll API changes.

---

## Channel screen extensions (MessageableChannelViewController)

These files add one behavior each to the main chat screen (all UIKit-only except where noted):

### `MessageableChannelViewController+Keyboard.swift`

- **What it does (simple):** Moves the **message input up** when the keyboard appears and back down when it hides, so the text field stays above the keyboard.
- **Convert to SwiftUI:** **Easy.** SwiftUI’s keyboard avoidance and `.ignoresSafeArea(.keyboard)` or focused field handling cover this.

### `MessageableChannelViewController+Permissions.swift`

- **What it does (simple):** Uses **channel permissions** to show/hide or enable/disable the send button, reply, and other actions.
- **Convert to SwiftUI:** **Easy.** Same permission checks; only the way views react (disabled/grayed) changes.

### `MessageableChannelViewController+ScrollView.swift`

- **What it does (simple):** Configures the **message list scroll view** (scroll indicators, bounce, etc.) and ties it to scroll events.
- **Convert to SwiftUI:** **Medium.** Same behavior with `ScrollView` modifiers and `ScrollViewReader` if needed.

### `MessageableChannelViewController+TableView.swift`

- **What it does (simple):** Sets up the **table view** (cell registration, delegate, estimated row height) and connects it to the data source.
- **Convert to SwiftUI:** **Easy.** Replaced by `List` or `LazyVStack`; no separate table setup.

### `MessageableChannelViewController+TextView.swift`

- **What it does (simple):** Handles **focus and behavior of the message text field** (e.g. first responder, dismiss).
- **Convert to SwiftUI:** **Easy.** `@FocusState` and `FocusState` in SwiftUI.

### `MessageableChannelViewController+UIViewExtensions.swift`

- **What it does (simple):** **Helper methods** on UIView (e.g. finding views, layout). Used by the channel screen.
- **Convert to SwiftUI:** **N/A or Easy.** Most code would move to SwiftUI layout; any pure logic can stay as-is.

---

## Managers (logic + UIKit glue)

### `Revolt/Pages/Channel/Messagable/Managers/PermissionsManager.swift`

- **What it does (simple):** Loads **channel permissions** and tells the UI what the user can do (send, delete, add reactions, etc.). UIKit is used to update buttons/labels.
- **Convert to SwiftUI:** **Easy.** Same logic; UI updates become `@Published` or binding-driven views.

### `Revolt/Pages/Channel/Messagable/Managers/TypingIndicatorManager.swift`

- **What it does (simple):** Tracks **who is typing** in the channel and shows/hides the typing indicator bar. Uses UIKit to add/remove the typing view.
- **Convert to SwiftUI:** **Easy.** State holds list of typers; one SwiftUI view shows the bar when non-empty.

### `Revolt/Pages/Channel/Messagable/Managers/1PendingAttachmentsManager.swift`

- **What it does (simple):** Keeps the **list of attachments** the user added before sending (images, files), enforces limits and size, and provides add/remove. Used by the input area.
- **Convert to SwiftUI:** **Easy.** Same logic; can be an `ObservableObject` or state in the SwiftUI input view.

---

## Constants and models

### `Revolt/Pages/Channel/Messagable/Models/MessageableChannelConstants.swift`

- **What it does (simple):** **Numbers and constants** for the channel screen (e.g. row heights, debounce times, scroll intervals). Uses UIKit for things like font metrics where needed.
- **Convert to SwiftUI:** **Easy.** Keep constants; replace any `UIFont`/`UIColor` usage with SwiftUI equivalents if needed.

---

## Media and full-screen

### `Revolt/Pages/Channel/Messagable/Controllers/FullScreenImageViewController.swift`

- **What it does (simple):** When you **tap an image** in chat, this opens it **full screen** with pinch-to-zoom, a close button, and optional download. You can pan and zoom the image.
- **What it does (UI):** Full-screen black background, image in the center, zoomable, close and download buttons.
- **Can we do this in SwiftUI?** Yes. Full-screen cover + `ScrollView` with zoom, or wrap a `UIScrollView` in `UIViewControllerRepresentable` for identical behavior.
- **Convert to SwiftUI:** **Medium.** Wrapping existing view controller is quick; pure SwiftUI zoom/pan is more work.

---

### `Revolt/Components/AudioPlayer/AudioPlayerView.swift`

- **What it does (simple):** **Inline audio player** for voice messages (or audio attachments): play/pause, progress bar, current time, download button, and optional waveform/title.
- **What it does (UI):** A horizontal bar with play button, progress slider, time label, and download.
- **Can we do this in SwiftUI?** Yes. Same layout and bindings to an audio engine; SwiftUI has sliders and buttons.
- **Convert to SwiftUI:** **Medium.** Playback logic stays; UI is straightforward in SwiftUI.

### `Revolt/Components/AudioPlayer/AudioPlayerManager.swift`  
### `Revolt/Components/AudioPlayer/AudioSessionManager.swift`

- **What they do (simple):** **Audio playback** (load, play, pause, seek) and **audio session** (e.g. play in background, respect silent switch). Mostly logic; some UIKit for progress/callbacks.
- **Convert to SwiftUI:** **Easy.** Keep as-is or expose via `ObservableObject`; SwiftUI views just observe state.

### `Revolt/Components/AudioPlayer/VideoPlayerView.swift`

- **What it does (simple):** **Inline video** in messages: thumbnail, play button, duration, download. Tapping play can open full-screen or inline player.
- **What it does (UI):** Card with thumbnail, play icon, duration, and optional title/size.
- **Can we do this in SwiftUI?** Yes. Same idea with `AsyncImage` or thumbnail + `AVPlayerViewController` wrapped in SwiftUI.
- **Convert to SwiftUI:** **Medium.** Wrapping `AVPlayerViewController` is easy; custom controls are more work if needed.

### `Revolt/Components/AudioPlayer/DownloadProgressView.swift`

- **What it does (simple):** **Progress bar** for file download (audio/video). Used inside the audio/video views.
- **Convert to SwiftUI:** **Easy.** `ProgressView` in SwiftUI.

---

## User sheet (UIKit-only version)

### `Revolt/Components/Sheets/UserSheetViewController.swift`

- **What it does (simple):** A **bottom sheet** showing a **user’s profile**: avatar, name, ID, mutual friends/groups, and actions (Message, Unfriend, Report). Used when you tap a user in the app (e.g. from a message).
- **What it does (UI):** Sheet with avatar, labels, and action buttons.
- **Can we do this in SwiftUI?** Yes. There is already a SwiftUI `UserSheet`; this is the UIKit variant. Migration = use the SwiftUI version everywhere.
- **Convert to SwiftUI:** **Easy.** Prefer existing SwiftUI sheet.

---

## Extensions and helpers

### `Revolt/Extensions/UIFont.swift`  
### `Revolt/Extensions/UIImage.swift`

- **What they do (simple):** **Convenience methods** for fonts and images (e.g. resizing, tinting, app-specific defaults). Used by UIKit views.
- **Convert to SwiftUI:** **Medium.** For SwiftUI you’d use `Font` and `Image`/`AsyncImage`; some helpers can be mirrored (e.g. `Image` resizing).

### `Revolt/Pages/Channel/Messagable/Extensions/UIViewExtensions.swift`

- **What it does (simple):** **UIView utilities** (e.g. finding subviews, layout). Used by the channel/message UI.
- **Convert to SwiftUI:** **N/A or Easy.** Most usage goes away with SwiftUI layout; any pure logic can stay.

### `Revolt/Extensions/1EmojiParser.swift`  
### `Revolt/Extensions/EmojiParser.swift`

- **What they do (simple):** **Parse and convert emoji** in text (shortcodes, Unicode). Used for rendering messages. Use `UIImage`/UIKit only for drawing or caching where needed.
- **Convert to SwiftUI:** **Easy.** Parsing logic is framework-agnostic; replace any UIKit drawing with SwiftUI `Text`/images if needed.

### `Revolt/Components/RemoteImageTextAttachment.swift`

- **What it does (simple):** Lets **images (e.g. emoji or custom emoji)** appear **inside the message text** in the UIKit text view. It loads images from the network and inserts them as attachments.
- **What it does (UI):** Inline images inside the text block of a message.
- **Can we do this in SwiftUI?** Partially. SwiftUI’s `Text` + markdown or `AttributedString` can show images in some cases; for complex inline custom emoji you might use a custom layout or keep a small representable.
- **Convert to SwiftUI:** **Medium.** Depends how rich the inline content is; simple cases are easy in SwiftUI.

---

## API / backend

### `Revolt/Api/Websocket.swift`

- **What it does (simple):** **WebSocket connection** to the server for real-time events (new messages, typing, etc.). Uses UIKit only for things like ensuring callbacks run on the main thread or updating app state that the UI observes.
- **Convert to SwiftUI:** **Easy.** Logic stays; any “update UI” becomes SwiftUI state/`@Published`; no UI views in this file.

---

# Part 2: SwiftUI + UIKit (both) files

These files **import both** SwiftUI and UIKit. They usually either embed a UIKit screen in SwiftUI or share code between both.

---

### `Revolt/Pages/Channel/Messagable/MessageableChannelViewControllerRepresentable.swift`

- **What it does (simple):** **Bridges the main chat screen** (UIKit) into SwiftUI. The app’s navigation is SwiftUI; when you open a channel, SwiftUI uses this to show the UIKit `MessageableChannelViewController`. It also forwards “scroll to this message” and refresh from SwiftUI to the UIKit controller.
- **What it does (UI):** No own UI; it’s the wrapper that puts the chat screen on screen.
- **Can we do this in SwiftUI?** If the chat screen is rewritten in SwiftUI, this file is **no longer needed**; SwiftUI would show a SwiftUI view directly.
- **Convert to SwiftUI:** **N/A** once the chat screen is SwiftUI; then delete this representable.

---

### `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`  
*(See Part 1 for full description.)*

- Uses both because it’s the main chat controller and is embedded in SwiftUI via the representable; some APIs (e.g. navigation, theme) may use SwiftUI types.

---

### `Revolt/Pages/Channel/Messagable/MessageableChannelViewModel.swift`

- **What it does (simple):** **View model** for the chat screen: holds messages, channel, and user state; loads messages; handles send, reply, and reactions. Used by both the UIKit controller and SwiftUI (e.g. for navigation or previews).
- **What it does (UI):** No direct UI; it drives what the UI shows.
- **Convert to SwiftUI:** **Easy.** Keep as-is; SwiftUI views will bind to the same view model.

---

### `Revolt/Pages/Channel/Messagable/MessageableChannel.swift`

- **What it does (simple):** **SwiftUI entry** for opening a channel: it shows the `MessageableChannelViewControllerRepresentable` (UIKit chat) inside the SwiftUI layout (e.g. with sidebar or navigation).
- **What it does (UI):** The container that decides “show the chat screen here.”
- **Convert to SwiftUI:** **Easy.** Replace the representable with a SwiftUI chat view; rest stays SwiftUI.

---

### `Revolt/Pages/Channel/Messagable/MessageableChannelViewController+NotificationBanner.swift`

- **What it does (simple):** Shows a **small banner** at the top of the chat when there’s a **network or sync issue** (e.g. “Reconnecting…”). Uses UIKit for the banner view inside the UIKit controller.
- **Convert to SwiftUI:** **Easy.** Same banner as a SwiftUI overlay or inline view when the view model says “show banner.”

---

### All `MessageableChannelViewController+*.swift` extensions  
*(EmptyState, Extensions, GlobalFix, Lifecycle, MarkUnread, MessageCell, MessageLoading, NSFW, Notifications, Replies, ScrollPosition, Setup, Skeleton, TableBouncing, TargetMessage)*

- **What they do (simple):** Each adds one **behavior** to the main chat screen: empty state, lifecycle, unread badge, loading messages, NSFW flow, notifications, reply UI, scroll-to-message, setup, skeleton loading, table bounce, etc. They use both SwiftUI and UIKit because the controller lives in a SwiftUI app and may use SwiftUI types for state or presentation.
- **Convert to SwiftUI:** Ranges from **Easy** to **Medium** per file; once the main screen is SwiftUI, these become modifiers, separate views, or logic in the SwiftUI chat view.

---

### `Revolt/Pages/Channel/Messagable/Managers/RepliesManager.swift`

- **What it does (simple):** **Manages reply state**: which message is being replied to, loading that message, and showing the reply bar. Uses UIKit to add/remove the reply view; logic is framework-agnostic.
- **Convert to SwiftUI:** **Easy.** Same state and logic; SwiftUI view shows reply bar based on state.

---

### `Revolt/Pages/Channel/Messagable/MessageSkeletonView.swift`

- **What it does (simple):** **Loading skeleton** for the message list (gray placeholder lines while messages load). Can be implemented as SwiftUI or UIKit; currently uses both for embedding.
- **Convert to SwiftUI:** **Easy.** Redraw as SwiftUI skeleton view.

---

### `Revolt/Pages/Channel/Messagable/NSFWOverlayView.swift`  
*(There is also a UIKit-only `Views/NSFWOverlayView.swift`; this one is the SwiftUI+UIKit version used in the channel flow.)*

- Same idea as Part 1: **NSFW gate** with confirm button. May conform to SwiftUI or be used from SwiftUI.
- **Convert to SwiftUI:** **Easy.**

---

### `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift`

- **What it does (simple):** **Handles actions** from the message input: send, paste, attach, mention selection. Coordinates with the view model and possibly UIKit text view.
- **Convert to SwiftUI:** **Easy.** Same logic; SwiftUI text field and buttons call into this or a SwiftUI equivalent.

---

### `Revolt/Components/1Loading/SkeletonHostingController.swift`

- **What it does (simple):** **Hosts a SwiftUI skeleton view** inside a UIKit view controller so it can be shown in the UIKit chat screen while loading.
- **Convert to SwiftUI:** **N/A** when chat is SwiftUI; skeleton can be a pure SwiftUI view.

---

### `Revolt/Components/Contents.swift`

- **What it does (simple):** **Renders the body of a message** (text, mentions, links, custom emoji) with rich formatting. Uses a third-party UIKit text view (SubviewAttachingTextView) and Highlightr for syntax. Used in both SwiftUI and UIKit message rendering.
- **What it does (UI):** The block of formatted text (and inline mentions/emoji) inside a message bubble.
- **Can we do this in SwiftUI?** Partially. SwiftUI `Text` with markdown/attributed string covers a lot; complex inline attachments or custom emoji might need a custom view or a wrapped UIKit view.
- **Convert to SwiftUI:** **Hard.** Rich text and attachments are the trickiest part; could be done incrementally (simple messages in SwiftUI, complex in a wrapper).

---

### `Revolt/Components/Markdown.swift`

- **What it does (simple):** **Markdown rendering** for message content (bold, code, links, etc.). Uses both SwiftUI and UIKit (e.g. `UITextView` or attributed string for some paths).
- **Convert to SwiftUI:** **Medium.** Prefer SwiftUI `Text` + markdown and `AttributedString` where possible; reduce UIKit usage step by step.

---

# Summary table – convert to SwiftUI

| Category                     | Easiest (mostly drop-in or small changes) | Medium (reimplement view, keep logic) | Hard (large or complex UI) |
|-----------------------------|-------------------------------------------|---------------------------------------|----------------------------|
| Toasts, typing, NSFW, reply bar, system cell | ✓ Most of these | - | - |
| Message list (data source, table setup) | ✓ | - | - |
| Message cell (one row)      | - | ✓ Layout + extensions | - |
| Main chat screen (VC)       | - | - | ✓ |
| Input view, mention picker  | - | ✓ | - |
| Link/attachment previews    | ✓ Attachment previews | ✓ Link preview | - |
| Full-screen image, audio/video players | - | ✓ | - |
| Scroll preservation, scroll manager | - | ✓ | - |
| User sheet, ViewModel, handlers, managers | ✓ | - | - |
| Contents / Markdown (rich text) | - | ✓ Markdown | ✓ Contents (rich inline) |

---

*Document generated for the pepchat-ios codebase. Last updated to include all files that import UIKit (purely UIKit and SwiftUI+UIKit).*
