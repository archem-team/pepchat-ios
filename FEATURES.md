# App Features

This document summarizes the major product features visible in the current codebase. It reflects what is implemented in `Revolt/Pages/`, `Revolt/Components/`, and related modules.

## Onboarding & Account
- Intro/first-run experience (`Revolt/Pages/Features/Intro/`).
- Account creation, login, email verification, and password reset flows (`Revolt/Pages/Login/`).
- MFA support (OTP/recovery codes) and email resend flows (`Revolt/Pages/Login/Mfa/`, `Revolt/Pages/Login/ResendEmail.swift`).

## Core Messaging
- Text channels and direct messages with message timelines (`Revolt/Pages/Channel/`, `Revolt/Pages/Channels/`).
- Message composer, attachments, and link previews (`Revolt/Pages/Channel/Messagable/Views/`).
- Message replies, reaction sheets, and swipe-to-reply (`Revolt/Components/MessageRenderer/`).
- Typing indicators and system messages (`Revolt/Pages/Channel/Messagable/Views/TypingIndicatorView.swift`, `SystemMessageCell.swift`).
- Mentions input and channel search (`Revolt/Pages/Channel/Messagable/Mention/`, `ChannelSearch.swift`).

## Media & Attachments
- Attachment previews and full-screen image viewer (`AttachmentPreviewView.swift`, `FullScreenImageViewController.swift`).
- Audio/video playback components (`Revolt/Components/AudioPlayer/`).

## Servers, Channels, and Community
- Server/channel navigation, discovery, and invites (`Revolt/Pages/Home/Discovery.swift`, `ViewInvite.swift`).
- Server settings: overview, categories, roles/permissions, emoji, members, bans, system messages (`Revolt/Pages/Channel/Settings/Server/`).
- Channel settings and permissions (`Revolt/Pages/Channel/Settings/Channel/`).
- Add/manage members and channel info sheets (`Revolt/Pages/Channel/Messagable/ChannelInfo/`).

## Social & Safety
- Friends list, friend requests, add friend, and group creation (`Revolt/Pages/Home/`).
- User sheets, mutual connections, and reporting (`Revolt/Components/Sheets/`, `Revolt/Pages/Home/ReportView.swift`).
- Block/remove friend flows (`Revolt/Components/AccountManagement/`).

## Settings & Preferences
- User profile, status/presence, appearance, notifications, language, sessions, and security settings (`Revolt/Pages/Settings/`).
- Bot settings and developer/experiments sections (`Revolt/Pages/Settings/BotSettings/`, `ExperimentsSettings.swift`, `DeveloperSettings.swift`).

## Notifications & Links
- Notification service extension for enriched push handling (`notificationservice/`).
- Universal link handling for channels, servers, and invites (`Revolt/RevoltApp.swift`).
