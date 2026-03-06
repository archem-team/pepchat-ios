# App Features

This document summarizes the major product features visible in the current codebase. It reflects what is implemented in `Revolt/Pages/`, `Revolt/Components/`, `Revolt/ViewState+Extensions/`, `Revolt/1Storage/`, and related modules. For project structure, architecture, state management, and development guidelines, see **AGENTS.md**.

---

## Onboarding & Account

- Intro/first-run experience (`Revolt/Pages/Features/Intro/`).
- Account creation, login, email verification, and password reset flows (`Revolt/Pages/Login/`).
- MFA support (OTP/recovery codes) and email resend flows (`Revolt/Pages/Login/Mfa/`, `Revolt/Pages/Login/ResendEmail.swift`).

---

## Core Messaging

- Text channels and direct messages with message timelines (`Revolt/Pages/Channel/`, `Revolt/Pages/Channels/`). Channel message list is UIKit (`MessageableChannelViewController` + `LocalMessagesDataSource` in `Revolt/Pages/Channel/Messagable/DataSources/`).
- Message composer, attachments, and link previews (`Revolt/Pages/Channel/Messagable/Views/`). Pending attachments managed before send via `PendingAttachmentsManager` (`Revolt/Pages/Channel/Messagable/Managers/`).
- **Draft messages**: Per-channel composer text only; session-bound. Saved on leave and via debounced typing; cleared at commit-to-send (offline and online) and on sign-out. Restored when re-opening channel if a draft exists (`ViewState+Drafts.swift`; see `docs/DraftMessage.md`).
- Message replies, reaction sheets, and swipe-to-reply (`Revolt/Components/MessageRenderer/`). Replies and local message delete flow through `RepliesManager`; on successful delete the table refreshes via `refreshMessagesAfterLocalDelete()`.
- Typing indicators and system messages (`Revolt/Pages/Channel/Messagable/Views/TypingIndicatorView.swift`, `SystemMessageCell.swift`).
- Mentions input and channel search (`Revolt/Pages/Channel/Messagable/Mention/`, `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelSearch.swift`).
- Message grouping: consecutive messages from the same author are visually grouped (`Revolt/Pages/Channel/Messagable/Managers/MessageGroupingManager.swift`).
- Scroll position preservation during message updates (`Revolt/Pages/Channel/Messagable/Managers/ScrollPositionManager.swift`).
- Target message navigation: jump to specific messages via links or notifications with highlighting (`MessageableChannelViewController+TargetMessage`).
- Skeleton loading states for message loading (`Revolt/Components/1Loading/MessageSkeletonView.swift`; also `Revolt/Pages/Channel/Messagable/MessageSkeletonView.swift` where used).
- **Realtime sync**: New messages from another device arrive via WebSocket; ViewState posts `NewMessagesReceived` and the current channel’s table refreshes so messages appear without leaving. Local deletes update ViewState and refresh the table (including `MessageDeletedLocally` from `MessageContentsView`).
- Instant message loading from SQLite cache: messages and users are read from `MessageCacheManager`; all cache writes go through a single session-scoped path (`MessageCacheWriter`) used by ViewModel, WebSocket, MessageInputHandler, RepliesManager, and MessageContentsView. Session is bound when connected; sign-out flushes pending writes with a bounded timeout before clearing caches (`Revolt/1Storage/MessageCacheManager.swift`, `MessageCacheWriter.swift`). First API page after opening a channel reconciles deletes (e.g. messages deleted while app was closed) so UI and cache stay in sync.
- Channel preloading: frequently accessed channels are preloaded in the background for faster access.

---

## Media & Attachments

- Attachment previews and full-screen image viewer (`Revolt/Pages/Channel/Messagable/Views/AttachmentPreviewView.swift`, `Revolt/Pages/Channel/Messagable/Controllers/FullScreenImageViewController.swift`).
- Audio/video playback components (`Revolt/Components/AudioPlayer/`).

---

## Servers, Channels, and Community

- **Discover servers**: CSV-backed server list for peptide.chat with membership cache for instant UI on launch; join/leave state synced across devices via WebSocket (`Revolt/Components/Home/Discover/` — `DiscoverScrollView`, `DiscoverItem`, `DiscoverItemView`; membership cache in `Revolt/ViewState+Extensions/ViewState+MembershipCache.swift`).
- Server channel list cache: per-server text/voice channels persisted for restore; cleared on sign-out (`Revolt/ViewState+Extensions/ViewState+ChannelCache.swift`).
- Server/channel navigation, discovery, and invites (`Revolt/Pages/Home/ViewInvite.swift` and related).
- Server settings: overview, categories, roles/permissions, emoji, members, bans, system messages (`Revolt/Pages/Channel/Settings/Server/`).
- Channel settings and permissions (`Revolt/Pages/Channel/Settings/Channel/`).
- Add/manage members and channel info sheets (`Revolt/Pages/Channel/Messagable/ChannelInfo/`).

---

## Social & Safety

- Friends list, friend requests, add friend, and group creation (`Revolt/Pages/Home/`).
- User sheets, mutual connections, and reporting (`Revolt/Components/Sheets/`, `Revolt/Pages/Home/ReportView.swift`).
- Block/remove friend flows (`Revolt/Components/AccountManagement/`).
- Content reporting: report messages, users, and servers with multiple report reasons (illegal content, harassment, spam, etc.) (`Revolt/Api/Payloads.swift`).
- NSFW content protection: age verification and confirmation sheets for mature content channels (`Revolt/Pages/Channel/Messagable/NSFWConfirmationSheet.swift`, `Revolt/Pages/Channel/Messagable/Views/NSFWOverlayView.swift`).

---

## Settings & Preferences

- User profile, status/presence, appearance, notifications, language, sessions, and security settings (`Revolt/Pages/Settings/`).
- Bot settings and developer/experiments sections (`Revolt/Pages/Settings/BotSettings/`, `ExperimentsSettings.swift`, `DeveloperSettings.swift`).

---

## Notifications & Links

- Notification service extension for enriched push handling (`notificationservice/`).
- Universal link handling for channels, servers, and invites (`Revolt/RevoltApp.swift`).
- Deep linking to specific messages with automatic scroll and highlighting.

---

## Performance & Caching

- **Message cache**: SQLite-based message cache for instant channel loading (`Revolt/1Storage/MessageCacheManager.swift`). Writes are serialized and session-scoped via `MessageCacheWriter` (used by ViewModel, WebSocket, composer, replies, and message content UI); session is bound when connected and invalidated on sign-out with a bounded flush so pending edits/deletes are persisted before caches are cleared. Multi-tenant schema (per user/base URL) with soft deletes (tombstones).
- **Draft storage**: Per-channel composer text in UserDefaults (`ViewState+Drafts.swift`); session-bound, cleared on sign-out and at the start of cache destroy. Not part of the message cache.
- **Discover membership cache**: Server join/leave state persisted to disk for instant Discover UI; updated on local or WebSocket join/leave events (`Revolt/ViewState+Extensions/ViewState+MembershipCache.swift`).
- **Server channel cache**: Per-server text/voice channel list persisted for restore; cleared on sign-out/destroyCache (`Revolt/ViewState+Extensions/ViewState+ChannelCache.swift`).
- Automatic cache cleanup of old messages to manage storage size.
- Background message preloading for frequently accessed channels.
- Memory management: automatic cleanup of old messages/users to prevent memory issues (ViewState; see AGENTS.md).
- Debounced saves for large data structures to prevent UI blocking.
