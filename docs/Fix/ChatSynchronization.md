# Chat Synchronization Fix (Background -> Foreground Delay)

## Issue Summary

Observed behavior:

- User A and User B are in the same DM/chat on separate devices.
- User A sends app to background (not terminated).
- User B sends a new message while User A is backgrounded.
- When User A returns to the app on the same open chat, new messages do not appear immediately.
- Messages appear only after a long delay, after User A sends a message, or after navigating back and re-entering chat.

Expected behavior:

- On foreground resume, chat should quickly reconcile websocket state and show missed messages without requiring manual navigation.

## Root Causes

### 1) Foreground websocket health check was too narrow

In `Revolt/Api/Websocket.swift`, foreground handling only reconnected when `currentState == .disconnected`.

This missed cases where socket transport became stale after backgrounding while app state still believed connection was active.

### 2) New-message handler had conflicting loading-state guards

In `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`, `handleNewMessages(_:)` returned early on `.loading`, then later had another `.loading` block meant to sync/reload.

Because of the first early return, the sync/reload path during loading was unreachable.

### 3) No explicit foreground catch-up trigger in channel controller

Even with websocket reconnect, foreground resume did not always force a channel-level catch-up fetch for missed messages in the active chat.

## Code Changes Implemented

## 1) Websocket foreground reconnection on app resume

File: `Revolt/Api/Websocket.swift`

### Exact code changed in `setupAppStateObservers()` foreground observer

```swift
let foregroundObserver = NotificationCenter.default.addObserver(
    forName: UIApplication.willEnterForegroundNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    guard let self = self else { return }

    // Starscream in this project does not expose `isConnected`.
    // Use a deterministic resume strategy: always reconnect to avoid stale socket state.
    self.forceConnect()
}
```

Why this helps:

- Prevents stale socket sessions from lingering after app returns to foreground.
- Reduces delayed message delivery caused by waiting for eventual timeout/recovery.

## 2) Fixed `handleNewMessages(_:)` logic to allow loading-time sync

File: `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`

### Exact final code for `handleNewMessages(_:)`

```swift
@objc internal func handleNewMessages(_ notification: Notification) {
    let notifChannel = notification.userInfo?["channelId"] as? String

    // If notification includes channelId, only refresh when the new message is for this channel (e.g. message from another device).
    if let notifChannel = notifChannel, notifChannel != viewModel.channel.id {
        return
    }

    if messageLoadingState == .loading {
        // Sync table from ViewState so messages from other devices (WebSocket) appear immediately.
        syncLocalMessagesWithViewState()
        if let localDataSource = dataSource as? LocalMessagesDataSource {
            localDataSource.updateMessages(localMessages)
        }
        tableView.reloadData()
        updateTableViewBouncing()
        return
    }

    if targetMessageProtectionActive {
        return
    }

    let currentMessageCount = viewModel.messages.count
    let storedMessageCount = UserDefaults.standard.integer(
        forKey: "LastMessageCount_\(viewModel.channel.id)")

    guard currentMessageCount > storedMessageCount else {
        return
    }

    UserDefaults.standard.set(
        currentMessageCount, forKey: "LastMessageCount_\(viewModel.channel.id)")

    // Check if user has manually scrolled up recently
    let hasManuallyScrolledUp =
        lastManualScrollUpTime != nil
        && Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0

    // Only auto-scroll if user is already near bottom and not actively reading older messages.
    if isUserNearBottom() && !hasManuallyScrolledUp {
        scrollToBottom(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.scrollToBottom(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.scrollToBottom(animated: false)
            }
        }
    }
}
```

Why this helps:

- Incoming websocket messages are reflected in UI even if channel is in transient loading state during foreground resume.

## 3) Added active/reconnected catch-up hooks in channel controller

File: `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

### Exact observer code added in `viewDidLoad()`

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleAppBecameActiveForRealtimeSync),
    name: UIApplication.didBecomeActiveNotification,
    object: nil
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleWebSocketReconnectedForRealtimeSync),
    name: NSNotification.Name("WebSocketReconnected"),
    object: nil
)
```

### Exact methods added in `MessageableChannelViewController`

```swift
@objc private func handleWebSocketReconnectedForRealtimeSync() {
    // Allow websocket auth/ready processing to settle before catch-up.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
        self?.handleAppBecameActiveForRealtimeSync()
    }
}

@objc private func handleAppBecameActiveForRealtimeSync() {
    guard UIApplication.shared.applicationState == .active else { return }
    guard !isViewDisappearing else { return }
    guard messageLoadingState != .loading, !isLoadingMore else { return }

    // Catch up any missed foreground-gap messages using existing "after" pagination path.
    if let lastMessageId = localMessages.last ?? viewModel.messages.last {
        throttledAPICall(for: lastMessageId)
    } else {
        Task { [weak self] in
            await self?.loadInitialMessages()
        }
    }
}
```

Why this helps:

- Ensures missed messages during foreground gap are fetched immediately using existing incremental API path.

## Why Background App Refresh is not required for this fix

This issue is primarily a foreground-resume synchronization gap, not a requirement to keep realtime sockets alive in background indefinitely.

The implemented fix focuses on:

- robust reconnect/health validation on resume,
- deterministic UI refresh during loading,
- immediate catch-up fetch after foreground/reconnect.

## Files Updated

- `Revolt/Api/Websocket.swift`
- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
- `docs/Fix/ChatSynchronization.md` (new)

## Suggested Manual Verification

1. Open DM on Device A and Device B.
2. Move Device A app to background (do not kill).
3. Send 1-3 messages from Device B.
4. Bring Device A app to foreground on same chat.
5. Verify messages appear quickly without manual navigation.
6. Repeat while Device A chat is in loading state (open and quickly background/foreground).
7. Verify no regressions in auto-scroll behavior when user is reading older messages.
