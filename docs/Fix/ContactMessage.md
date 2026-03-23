# Contact DM First-Message and Delete Sync Fix

## Summary

This document captures two related issues in new Direct Messages (DMs), their root causes, and the implemented fixes.

## Issues Observed

### Issue 1: First message in a newly opened DM did not appear immediately

- Scenario:
  - User accepts a friend request.
  - User opens DM with that new contact.
  - User sends the first message.
  - Message does not appear until user navigates back and re-opens the chat.

### Issue 2: Deleted message behavior in newly created DM was inconsistent

- Scenario A:
  - User sends first message in new DM.
  - User deletes it.
  - UI sometimes still showed stale state until re-open.
- Scenario B:
  - User deletes the only message in chat (chat becomes empty).
  - User sends a new message.
  - Previously deleted message reappears in the same session.
  - Navigating back and opening again makes it disappear.

## Root Causes

## 1) New-message refresh path was blocked during loading

In `MessageableChannelViewController+Notifications.swift`, `handleNewMessages` had an early return when `messageLoadingState == .loading`.

In a fresh DM, this loading state is common while initial fetch/setup is still happening.  
So optimistic send updated `ViewState`, but UI refresh was skipped at the exact moment the first message arrived.

## 2) Newly opened DM was not always fully hydrated in active channel dictionaries

In `ViewState.openDm(with:)`, after opening/finding DM channel, navigation state changed (`currentSelection/currentChannel`), but the channel was not consistently inserted into all runtime maps used by downstream UI sync paths.

This created edge cases in first-open flows for recently created DMs.

## 3) Local sync logic did not clear stale `localMessages` when channel became empty

`syncLocalMessagesWithViewState()` only copied arrays when source arrays were non-empty:

- it updated `localMessages` from `channelMessages` only when `channelMessages` was not empty
- it updated from `viewModel.messages` only when `viewModel.messages` was not empty

After deleting the only message, both sources were empty, so `localMessages` could remain stale.  
On next send, stale IDs mixed with new state and caused deleted message reappearance until full re-open/reload.

## Fixes Implemented

## Fix A: Immediate table refresh on optimistic send

File: `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift`

Applied in both:
- `sendMessage(_:)`
- `sendMessageWithAttachments(_:attachments:)`

After optimistic insert into:
- `viewState.channelMessages[channelId]`
- `viewState.messages[nonce]`

the controller now immediately calls:

- `viewController.refreshMessagesAfterLocalDelete()`

This forces `localMessages`/dataSource/table reload right away, so the first message appears without navigation.

## Fix B: Allow same-channel refresh even while loading

File: `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`

`handleNewMessages(_:)` was restructured to:

- first filter by notification `channelId`
- during `.loading`, still do:
  - `syncLocalMessagesWithViewState()`
  - data source update
  - `tableView.reloadData()`
  - `updateTableViewBouncing()`
  - and return (no aggressive auto-scroll logic)

This preserves loading safety but removes the blind spot where first message refresh was ignored.

## Fix C: Hydrate DM channel maps on `openDm(with:)`

File: `Revolt/ViewState.swift`

Inside success path of `openDm(with:)`, before setting selection/current channel:

- `channels[safeChannel.id] = safeChannel`
- `allEventChannels[safeChannel.id] = safeChannel`
- initialize `channelMessages[safeChannel.id] = []` when missing

This ensures DM channel data is available immediately for UI and message sync logic.

## Fix D: Clear local message list when channel is truly empty

File: `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

In `syncLocalMessagesWithViewState()`, added explicit empty-state handling:

- if `channelMessages` is empty and `viewModel.messages` is empty:
  - clear `localMessages`
  - keep `viewModel.messages` and `viewState.channelMessages[channelId]` in sync as empty

This prevents stale IDs from surviving the delete-to-empty transition and fixes deleted message reappearance on next send.

## Why these fixes are correct together

- Fix A guarantees immediate optimistic visibility.
- Fix B removes loading-window refresh drops.
- Fix C prevents missing DM channel metadata/state on first open.
- Fix D resolves empty-chat stale list retention after delete.

Together they cover both:
- send-first-message visibility in new DMs
- delete-then-send stale resurrection edge case

## Files changed for this fix set

- `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift`
- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift`
- `Revolt/ViewState.swift`
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

## Regression checks (manual)

1. Accept friend request -> open DM -> send first message -> message appears immediately.
2. Delete that message -> chat becomes empty immediately.
3. Send new message in same DM -> no deleted message reappears.
4. Navigate back/open again -> state remains correct.
5. Repeat on iPhone device (real hardware) and simulator.

