# New Messages Pointer

## Goal

Implement Discord-style unread resume behavior in the UIKit chat screen.

When a user opens a channel with unread messages, the chat should resume at the first unread message instead of jumping to the latest message. A red `NEW MESSAGES` divider is shown above the first unread message.

This follows the Revite web model: capture the unread anchor locally first, then acknowledge the channel as read. For server-origin unread state, the UI keeps rendering from the captured anchor until the user completes the normal read flow. A manual Mark Unread action remains unread for the rest of the current chat session and is consumed when the channel is opened again.

## API Contract

The backend already supports the required read state.

- `GET /sync/unreads`
  - Implemented by `Http.fetchUnreads()`.
  - Returns `Unread` records keyed by channel/user.
  - `Unread.last_id` is treated as the last acknowledged/read message id.
  - `Unread.mentions` contains unread mention message ids.

- `PUT /channels/{channel}/ack/{message}`
  - Implemented by `Http.ackMessage(channel:message:)`.
  - Marks the channel as read up to the supplied message id.

Important semantic rule:

- `last_id` must remain the last-read marker.
- New incoming messages must not overwrite `last_id` with the new message id.
- If incoming websocket messages update `last_id` directly, unread state is effectively marked read immediately and the pointer will not show.

## Behavior Rules

### Open Chat

1. Load messages from cache or API.
2. Read current channel unread state from `viewState.unreads[channelId]`.
3. Store `Unread.last_id` in `unreadAnchorLastReadMessageId`.
4. Find the first loaded message id greater than `Unread.last_id` and store it in `unreadSeparatorMessageId`.
5. Reload the table so the cell for that message renders the `NEW MESSAGES` separator.
6. Scroll to that row with `.top`.
7. Acknowledge `channel.last_message_id` immediately, matching web behavior.
8. Block automatic bottom scrolls while `unreadSeparatorMessageId != nil`.

If `channel.last_message_id` is unavailable/stale, fall back to `localMessages.last`. This matters for first-open/no-cache cases where channel metadata may arrive after messages.

### Load Messages Below Pointer

After positioning at the unread separator, fetch context after the last-read id:

```swift
fetchHistory(
    channel: channelId,
    limit: 100,
    after: lastReadId,
    sort: "Oldest"
)
```

Merge those ids into `localMessages`, update `ViewState.channelMessages`, reload without animation, and re-position at the unread separator. This lets unread messages below the divider appear without snapping to the bottom.

### Dynamic Row Rendering

Message rows can change height after initial render because of:

- reply previews
- link previews
- embeds
- attachment sizing
- reaction layout

While the unread separator is active:

- `scrollToBottom(animated:)` should return early.
- Reply/link preview refreshes should not treat the current position as "near bottom".
- Table reloads should preserve the unread separator row rather than re-bottoming.

### Scroll To Latest Control

The Liquid Glass down-arrow button has one navigation meaning: move to the latest message at the bottom of the chat.

The button:

- always scrolls to the final message, even while `unreadSeparatorMessageId` is active
- does not navigate back to the `NEW MESSAGES` divider
- preserves a manually marked unread divider and its server read state
- remembers the user's latest-position request so an in-flight history reload cannot snap back to the divider

### Clear Read State

For normal incoming unread state, clear the divider/counter and ack latest message when:

- user scrolls to the latest message
- user taps the scroll-to-latest button
- user sends a message
- user exits the chat screen normally back to home/server/DM list

For a manual Mark Unread action, scrolling to latest or leaving the current chat must not acknowledge latest or remove the divider state. The down-arrow only changes scroll position. The manual unread state is consumed on the next channel opening session.

Do not clear unread state when navigating to:

- pinned messages
- search messages

Those screens are considered temporary chat subflows, not a "read complete" event.

### Live Chat Messages

While the user is already at the bottom of the open chat, incoming messages should append and stay anchored to latest without showing the unread pointer.

Only show the unread pointer for live messages when:

- the message is from another user, and
- the user was not near bottom before the new message was inserted, or they had manually scrolled upward.

Messages sent by the current user must never create the unread pointer.

## Fixes

### Pointer cleared after opening from terminated state

Issue:

- When the app opened from a terminated/cold state with unread messages, the pointer could appear correctly and then disappear after a short reload.
- The table reload/global fix path could reposition the table as if the user had read through to latest, even though the user never left the screen or scrolled to the bottom.
- `willDisplay` for the last row could call `markLastMessageAsSeen()` during layout/reload, which cleared the marker just because UIKit displayed the last cell.

Fix:

- Keep `unreadAnchorLastReadMessageId` as the local source of truth after acknowledging latest, matching Revite's local `lastId`.
- Do not let `willDisplay` clear read state while `unreadSeparatorMessageId != nil`.
- Do not run `applyGlobalFix()` while an unread anchor/separator is active.
- Clear the pointer only when the user actually reaches latest by scrolling, taps scroll-to-latest, sends a message, or leaves the chat normally.

### Pointer shown during live bottom chat

Issue:

- Live incoming messages could show the `NEW MESSAGES` pointer even when the user was already at the bottom of the open chat.
- The code checked `isUserNearBottom()` after inserting/reloading the new message. Because content height had already grown, the user could look "not near bottom" after the reload.

Fix:

- Capture `wasNearBottom` before syncing/reloading new message ids.
- If the user was near bottom and has not manually scrolled upward, append and scroll/stay anchored to latest without creating a pointer.
- Only create the pointer for another user's live message when the user was already away from bottom or recently scrolled upward.

### Current user's messages created pointers or skipped

Issue:

- Optimistic/current-user messages could trigger the new-message pointer.
- A stale `UserDefaults` message-count gate could prevent new local message ids from syncing, making some sent messages appear skipped.

Fix:

- Detect newly inserted message ids by comparing `localMessages` before/after sync rather than trusting stored message counts.
- Ignore current-user messages for unread pointer creation.
- For current-user sends, clear any existing marker and scroll to latest instead of treating the optimistic message as unread.

### Scroll-to-latest jumped to a manually marked unread divider

Issue:

- The down-arrow button treated an active `unreadSeparatorMessageId` as a request to jump to the divider.
- Delayed unread-context loading could re-position at the divider after the user had requested the bottom.

Fix:

- Route the down-arrow action directly to `scrollToLatestMessageFromButton()`.
- Track `didRequestLatestPositionFromButton` independently from unread marker state.
- Suppress automatic unread-separator positioning after that request and restore the bottom position after an in-flight history reload completes.
- Keep the red divider and manual unread server state intact.

## UIKit Implementation

### State

Stored on `MessageableChannelViewController`:

- `unreadAnchorLastReadMessageId: String?`
- `unreadSeparatorMessageId: String?`
- `didPositionAtUnreadSeparator: Bool`
- `didRequestUnreadContextLoad: Bool`
- `didRequestUnreadStateRefresh: Bool`
- `shouldPreserveUnreadStateOnDisappear: Bool`
- `didRequestLatestPositionFromButton: Bool`

### Separator Rendering

The separator is rendered inside `MessageCell`, above the message content.

Why not insert a fake row:

- Existing table state is message-id based.
- Pagination, height caching, grouping, context menus, and reply logic assume each row maps to a real message id.
- A fake row would require a larger data-source model migration.

Current approach:

- `MessageCell` owns `unreadSeparatorView`.
- Data source calls:

```swift
messageCell.setUnreadSeparatorVisible(
    viewControllerRef?.shouldShowUnreadSeparator(for: messageId) ?? false
)
```

Cell height cache includes `hasUnreadSeparator` in `CellHeightCacheKey` so a normal-height cached row does not clip the divider.

### Read/Ack Flow

The initial unread capture path acknowledges latest immediately but does not clear the local marker. This mirrors Revite, where `lastId` is held in React state while `markRead` clears the backend unread.

`clearUnreadMarkerAndAcknowledgeLatest(messageId:)`:

- clears `unreadAnchorLastReadMessageId`
- clears `unreadSeparatorMessageId`
- hides the scroll-to-latest/new-message button
- updates local `viewState.unreads[channelId].last_id`
- clears local mention ids
- sends `ackMessage(channel:message:)`
- updates app badge count

When sending a message, use the latest real message id before appending the optimistic UUID. Do not ack the temporary queued-message UUID.

### Pin/Search Preservation

Before navigating to pin/search:

```swift
shouldPreserveUnreadStateOnDisappear = true
```

In `viewWillDisappear`:

- if preservation flag is set, do not ack
- otherwise clear marker and ack latest

## Files

- `Revolt/Api/Http.swift`
  - `fetchUnreads()`
  - `ackMessage(channel:message:)`

- `Revolt/Api/Responses.swift`
  - `Unread`

- `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`
  - preserves `Unread.last_id` as last-read marker on incoming messages
  - appends mention ids for unread mentions

- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
  - unread marker state
  - pin/search preservation flag
  - scroll-to-latest button action and accessibility state

- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MarkUnread.swift`
  - unread marker calculation
  - one-shot unread state refresh
  - unread context loading after last-read id
  - ack/clear helpers
  - suppresses separator repositioning after an explicit latest-position request

- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableBouncing.swift`
  - positions table at unread separator before falling back to bottom

- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+ScrollView.swift`
  - blocks automatic bottom scroll while unread marker is active
  - performs explicit scroll-to-latest button navigation

- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Setup.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift`
  - separator UI and layout offset handling

- `Revolt/Pages/Channel/Messagable/Managers/CellHeightCache.swift`
  - height cache includes unread separator state

## Edge Cases

- First open with no cache:
  - messages may render before unread state arrives
  - chat VC performs a one-shot `/sync/unreads` refresh if local unread state is missing

- Cached messages:
  - marker calculation uses loaded ids and does not require fresh channel metadata

- Link preview/reply preview height changes:
  - automatic bottom scroll is blocked while marker exists

- Incoming websocket message:
  - create unread entry using previous channel `last_message_id` as `last_id`
  - do not set `last_id` to the new message id

- User sends a message:
  - clear marker/counter
  - ack latest real message id before optimistic queued message insertion

## Known Limitations

- Exact unread count is not directly supplied by `/sync/unreads`.
- The client can compute count only from loaded messages after `last_id`.
- If more than the fetched unread page exists, more pagination is needed for an exact large count.
