# App Features

This document summarizes the major product features visible in the current codebase. It reflects what is implemented in `Revolt/Pages/`, `Revolt/Components/`, and related modules. For project structure, architecture, and development guidelines, see `AGENTS.md`.

## Onboarding & Account
- Intro/first-run experience (`Revolt/Pages/Features/Intro/`).
- Account creation, login, email verification, and password reset flows (`Revolt/Pages/Login/`).
- MFA support (OTP/recovery codes) and email resend flows (`Revolt/Pages/Login/Mfa/`, `Revolt/Pages/Login/ResendEmail.swift`).

## Core Messaging
- Text channels and direct messages with message timelines (`Revolt/Pages/Channel/`, `Revolt/Pages/Channels/`).
- Message composer, attachments, and link previews (`Revolt/Pages/Channel/Messagable/Views/`). Pending attachments managed before send via `PendingAttachmentsManager` (`Revolt/Pages/Channel/Messagable/Managers/1PendingAttachmentsManager.swift`).
- Message replies, reaction sheets, and swipe-to-reply (`Revolt/Components/MessageRenderer/`).
- Typing indicators and system messages (`Revolt/Pages/Channel/Messagable/Views/TypingIndicatorView.swift`, `SystemMessageCell.swift`).
- Mentions input and channel search (`Revolt/Pages/Channel/Messagable/Mention/`, `ChannelSearch.swift`).
- Message grouping: consecutive messages from the same author are visually grouped (`Revolt/Pages/Channel/Messagable/Managers/MessageGroupingManager.swift`).
- Scroll position preservation: maintains user's scroll position during message updates (`Revolt/Pages/Channel/Messagable/Managers/ScrollPositionManager.swift`).
- Target message navigation: jump to specific messages via links or notifications with highlighting.
- Skeleton loading states for smooth message loading experience (`Revolt/Components/1Loading/MessageSkeletonView.swift`).
- Instant message loading via SQLite cache (`Revolt/1Storage/MessageCacheManager.swift`).
- Channel preloading: frequently accessed channels are preloaded in the background for faster access.

## Media & Attachments
- Attachment previews and full-screen image viewer (`AttachmentPreviewView.swift`, `FullScreenImageViewController.swift`).
- Audio/video playback components (`Revolt/Components/AudioPlayer/`).

## Servers, Channels, and Community
- Discover servers: CSV-backed server list for peptide.chat with membership cache for instant UI on launch; join/leave state synced across devices via WebSocket (`Revolt/Components/Home/Discover/` — `DiscoverScrollView`, `DiscoverItem`, `DiscoverItemView`, `ServerChatDataFetcher`; `ViewState+MembershipCache.swift`).
- Server/channel navigation, discovery, and invites (`Revolt/Pages/Home/Discovery.swift`, `ViewInvite.swift`).
- Server settings: overview, categories, roles/permissions, emoji, members, bans, system messages (`Revolt/Pages/Channel/Settings/Server/`).
- Channel settings and permissions (`Revolt/Pages/Channel/Settings/Channel/`).
- Add/manage members and channel info sheets (`Revolt/Pages/Channel/Messagable/ChannelInfo/`).

## Social & Safety
- Friends list, friend requests, add friend, and group creation (`Revolt/Pages/Home/`).
- User sheets, mutual connections, and reporting (`Revolt/Components/Sheets/`, `Revolt/Pages/Home/ReportView.swift`).
- Block/remove friend flows (`Revolt/Components/AccountManagement/`).
- Content reporting: report messages, users, and servers with multiple report reasons (illegal content, harassment, spam, etc.) (`Revolt/Api/Payloads.swift`).
- NSFW content protection: age verification and confirmation sheets for mature content channels (`Revolt/Pages/Channel/Messagable/NSFWConfirmationSheet.swift`, `Revolt/Pages/Channel/Messagable/Views/NSFWOverlayView.swift`).

## Settings & Preferences
- User profile, status/presence, appearance, notifications, language, sessions, and security settings (`Revolt/Pages/Settings/`).
- Bot settings and developer/experiments sections (`Revolt/Pages/Settings/BotSettings/`, `ExperimentsSettings.swift`, `DeveloperSettings.swift`).

## Notifications & Links
- Notification service extension for enriched push handling (`notificationservice/`).
- Universal link handling for channels, servers, and invites (`Revolt/RevoltApp.swift`).
- Deep linking to specific messages with automatic scroll and highlighting.

## Performance & Caching
- SQLite-based message caching for instant channel loading (`Revolt/1Storage/MessageCacheManager.swift`).
- Discover membership cache: server join/leave state persisted to disk for instant Discover UI; updated on local or WebSocket join/leave events (`ViewState+MembershipCache.swift`).
- Automatic cache cleanup of old messages to manage storage size.
- Background message preloading for frequently accessed channels.
- Memory management: automatic cleanup of old messages/users to prevent memory issues.
- Debounced saves for large data structures to prevent UI blocking.