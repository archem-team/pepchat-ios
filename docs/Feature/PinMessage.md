# Pin Message Feature

This document describes the **current implementation** and the **remaining plan** for the Pin Message feature on iOS: who can pin, pin/unpin API and UI, and what is still to do (pinned list, tap-to-scroll).

---

## 1. Current Implementation: What Exists Today

### 1.1 Models and API

**Message model (`Types/Message.swift`)**

- **`Message`** includes:
  - **`pinned: Bool?`** – Decoded from the API message payload (`"pinned": null` or boolean). Used to show “Pin Message” vs “Unpin Message” in the long-press sheet and to update local state after pin/unpin.
- **`MessagePinnedSystemContent`** with `id`, `by`, `by_username` (pinned message ID and who pinned it).
- **`SystemMessageContent`** cases `.message_pinned(MessagePinnedSystemContent)` and `.message_unpinned(MessagePinnedSystemContent)` with full Codable support.

**API (`Revolt/Api/Http.swift`)**

- **`pinMessage(channel:message:)`** – `POST /channels/:channel/messages/:message/pin`, returns `Result<EmptyResponse, RevoltError>`.
- **`unpinMessage(channel:message:)`** – `DELETE /channels/:channel/messages/:message/pin`, returns `Result<EmptyResponse, RevoltError>`.

Chat “fetches which messages are pinned” by decoding the **`pinned`** field from normal message payloads (history, single message, WebSocket, etc.). No separate pinned-list endpoint is used yet.

### 1.2 System message rendering (display only)

- **`SystemMessageCell`** (`Revolt/Pages/Channel/Messagable/Views/SystemMessageCell.swift`) shows “Message pinned by X” / “Message unpinned by X” (no tap handling; `MessagePinnedSystemContent.id` is not used for navigation).
- **`SystemMessageView`** (`Revolt/Components/MessageRenderer/SystemMessageView.swift`) renders the same in SwiftUI (display only, no tap).

### 1.3 Long-press sheet: Pin / Unpin option

**Trigger and parameters**

- Long-press is handled in **`MessageCell+ContextMenu.swift`** → `handleLongPress`.
- **`MessageOptionViewController`** is created with:
  - `message`, `isMessageAuthor`, `canDeleteMessage()`, `canReply`,
  - **`canPinMessage()`** (from `MessageCell`),
  - **`isMessagePinned: message.pinned == true`**.

**Sheet UI (`MessageOptionViewController`)**

- **`canPinMessage`** and **`isMessagePinned`** are stored and used in **`setupOptions()`**.
- When **`canPinMessage`** is true, a single row is shown:
  - If **`isMessagePinned`** is true: title **“Unpin Message”**, icon **“pin.slash”**, action **`.unpin`** then dismiss.
  - Otherwise: title **“Pin Message”**, icon **“pin”**, action **`.pin`** then dismiss.
- Icons are SF Symbols via **`mapToSFSymbol(_:)`** and `UIImage(systemName:)` (no asset-catalog images for these options).

### 1.4 Permission: who can see Pin/Unpin

**`MessageCell.canPinMessage()`** (in `MessageCell.swift`) controls whether the Pin/Unpin row appears:

- **Missing data:** Fallback `isCurrentUserAuthor()`.
- **Message author:** Returns `true` (author can always see Pin/Unpin in current implementation).
- **DM channel:** Returns `true` (everyone can pin).
- **Group DM channel:** Returns `true` (everyone can pin).
- **Server channel (non-author):** Returns `true` only if resolved channel permissions contain **`.manageMessages`**.

So: in DMs and group DMs everyone can pin/unpin; in server channels the author can always pin/unpin, and non-authors can only if they have `manageMessages`.

> **Desired product rule (not implemented):** In a server channel, only the channel admin can pin (not the author). That would require removing the author shortcut and relying only on an admin permission (e.g. `manageMessages` or `manageChannel`) in **`canPinMessage()`**.

### 1.5 Handling .pin and .unpin (`RepliesManager`)

**`MessageCell.MessageAction`** includes **`.pin`** and **`.unpin`**. They are invoked from the sheet and handled in **`RepliesManager.handleMessageAction`**:

**`.pin`**

- In a `Task`: get `channelId` and `viewState`, then `await viewState.http.pinMessage(channel:message:)`.
- On **success** (inside `MainActor.run`):
  - If `viewState.messages[message.id]` exists, set **`updatedMessage.pinned = true`** and write back to `viewState.messages[message.id]`.
  - Show “Message pinned” alert (e.g. `showAlert(message: "Message pinned", icon: .peptidePin)`).
  - Call **`viewController.refreshMessages()`**.
- On **failure:** Log and show “Failed to pin message” (e.g. `showErrorAlert`).

**`.unpin`**

- In a `Task`: get `channelId` and `viewState`, then `await viewState.http.unpinMessage(channel:message:)`.
- On **success** (inside `MainActor.run`):
  - If `viewState.messages[message.id]` exists, set **`updatedMessage.pinned = false`** and write back.
  - Show “Message unpinned” alert.
  - Call **`viewController.refreshMessages()`**.
- On **failure:** Log and show “Failed to unpin message”.

Local **`pinned`** is updated so the next time the sheet opens it shows the correct “Pin” or “Unpin” without an extra fetch.

### 1.6 Backend error: NotPinned (400)

If the server returns **HTTP 400** with a body like **`{"type":"NotPinned", ...}`**, it means the message is **not** pinned on the server (e.g. already unpinned, or pin never applied). The app can treat this as “sync local state”: set **`viewState.messages[message.id]?.pinned = false`** and optionally show a short message like “Message is not pinned” or dismiss without a hard error so the UI shows “Pin” next time.

---

## 2. Planned Permission Model (Future)

- **Server channels:** Only channel admins (e.g. `manageMessages` / `manageChannel`) can pin; authors should not see Pin unless they have that permission.
- **DM / Group DM:** Keep “everyone can pin” (already implemented).
- **Implementation:** Adjust **`canPinMessage()`** to remove the author shortcut for server channels and rely only on the chosen admin permission.

---

## 3. Pin / Unpin – Implemented vs Remaining

**Implemented**

- **API:** `pinMessage(channel:message:)` and `unpinMessage(channel:message:)` in `Revolt/Api/Http.swift`.
- **Message model:** `pinned: Bool?` in `Types/Message.swift` (init and CodingKeys).
- **Actions:** `MessageCell.MessageAction` has `.pin` and `.unpin`.
- **Sheet:** When `canPinMessage` is true, one row: “Pin Message” or “Unpin Message” based on `isMessagePinned` (`message.pinned == true`), calling `.pin` or `.unpin` and dismissing.
- **Context menu:** Passes `canPinMessage()` and `isMessagePinned: message.pinned == true` into `MessageOptionViewController`.
- **Handlers:** `RepliesManager.handleMessageAction` implements `.pin` and `.unpin`: API call, then on success update `viewState.messages[message.id].pinned`, show alert, and `refreshMessages()`.

**Remaining (optional)**

- **NotPinned handling:** On 400 with `type: "NotPinned"`, set local `pinned = false` and optionally show “Message is not pinned” or silently sync.
- **Unpin on “already pinned”:** Backend may have its own validation; app already updates local state on success/failure.

---

## 4. Pinned Messages List (Search-Based)

### 4.1 Backend contract

Instead of a dedicated “list pins” endpoint, the app uses the **message search** API:

- **Endpoint:** `POST /channels/{target}/search`
- **Body:** `API.DataMessageSearch` with:
  - `pinned: true` – only pinned messages in the channel.
  - `query: null` – no free‑text query when `pinned` is set (server requirement).
  - `sort: "Latest" | "Oldest" | "Relevance"` – sort order; default is `"Latest"` for pinned view.
  - `limit` / `before` / `after` – pagination (we currently use `limit = 100` and no cursors).
  - `include_users: true` – so the search payload includes user/member objects.
- **Response:** Same structure as normal search (`SearchResponse` – `messages`, `users`, `members?`), and each `Message` includes `attachments`, `embeds`, `pinned`, etc.

On web (`for-web` repo), the pinned sidebar reuses the text search sidebar and calls this endpoint with `query={{ pinned: true, sort: "Latest" }}`. iOS mirrors that approach.

### 4.2 HTTP client + payload

- **Payload:** `ChannelSearchPayload` (`Revolt/Api/Payloads.swift`)
  - **Updated:** `query` is now `String?` and we added `pinned: Bool?`.
  - Other fields: `limit`, `before`, `after`, `sort: MessageSort?`, `include_users: Bool?`.
- **Client:** `HTTPClient` (`Revolt/Api/Http.swift`)
  - Existing: `searchChannel(channel:sort:query:)` for text search (`query` non‑nil, `pinned` nil).
  - **New:** `fetchPinnedMessages(channel:sort:limit:)`:
    - Builds `ChannelSearchPayload(query: nil, pinned: true, limit: limit, before: nil, after: nil, sort: sort, include_users: true)`.
    - `POST /channels/\(channel)/search` with that payload.
    - Returns `Result<SearchResponse, RevoltError>`.

### 4.3 UI: Pinned Messages sheet

- **Entry point:** Pin icon in the channel header.
  - File: `MessageableChannelViewController+Setup.swift`.
  - Added `pinnedMessageButton` next to the search icon:
    - Right side layout: `[... channel name] [pin button] [search]`.
    - Tap handler `pinnedButtonTapped()` pushes a new navigation destination.
- **Navigation destination:** `NavigationDestination.channel_pinned_messages(String)` (channel ID) in `ViewState+Types.swift`.
  - Wired in `RevoltApp.swift`:
    - Case `.channel_pinned_messages(let id)` builds a `Binding<Channel>` and presents `PinnedMessagesView(channel: channelBinding)`.

### 4.4 `PinnedMessagesView` implementation

File: `Revolt/Pages/Channel/Messagable/ChannelInfo/PinnedMessagesView.swift`

- **View model inputs:**
  - `@EnvironmentObject var viewState: ViewState`
  - `@Binding var channel: Channel`
  - Local state: `pinnedMessages: [Types.Message]`, `isLoading`, `isNavigatingToMessage`.
- **Server binding:** Matches other Channel Info views:
  - `let server: Binding<Server?> = channel.server.map { id in Binding(get: { viewState.servers[id] }, set: { viewState.servers[id] = $0 }) } ?? Binding.constant(nil)`
- **Loading:**
  - `.task` on the root `VStack` calls `loadPinnedMessages()` once.
  - `loadPinnedMessages()`:
    - Calls `viewState.http.fetchPinnedMessages(channel: channel.id, sort: .latest, limit: 100)`.
    - On success:
      - Merges `response.users` into `viewState.users`.
      - Merges `response.members` (if any) into `viewState.members[serverId][userId]`.
      - Stores `response.messages` in `pinnedMessages`.
    - On failure: logs `PinnedMessagesView: Failed to load pinned messages: \(error)` (no hard UI error; sheet simply shows empty state).
- **Layout & UX:**
  - Header row:
    - Close icon (same behavior as Channel Search): posts `ChannelSearchClosing` with `["channelId": channel.id, "isReturning": true]` and pops from `viewState.path`.
    - Title: “Pinned Messages”.
  - Empty state (when `!isLoading && pinnedMessages.isEmpty`):
    - SF Symbol `pin.slash`, title “No Pinned Messages”, helper text “Pin important messages to find them here.”
    - Full height gray background using `UnevenRoundedRectangle` over the whole sheet, not just the content area.
  - List state:
    - `ScrollView` + `LazyVStack`, matching the search screen’s layout.
    - For each `message`:
      - Resolves `author` from `viewState.users[message.author]` or falls back to a minimal `User` stub (`Unknown User`).
      - Renders a standard `MessageView`:
        - `MessageContentsView` inside honors attachments, embeds, and reactions.
        - `channelScrollPosition: .empty` (no in‑sheet scrolling to specific messages).
      - Tapping a row calls `navigateToMessage(message)` (see below).

### 4.5 Attachments-only pinned messages

Issue discovered during testing:

- Pinned messages that had **only media attachments** (image/video/audio/file) and **no text** appeared as **blank cells** in the pinned sheet.
- Root cause:
  - In `MessageContentsView` (`Revolt/Components/MessageRenderer/MessageContentsView.swift`), the media layout only handled `mediaAttachments.count == 2/3/4/5`. When there was exactly **1** media attachment, the code fell into the empty `else` branch and rendered nothing.
  - `MessageView` still drew author + timestamp, but the content area had no attachments, so the cell looked empty.

Fix:

- Added an explicit case:
  - If `mediaAttachments.count == 1`:
    - Render `MessageAttachment(attachment: mediaAttachments[0], height: 295)` with top padding.
  - Other counts (2–5) retain their existing grid layouts.
  - `otherAttachments` (non-media files) continue to render below the media grid.

Result:

- Pinned messages with:
  - **Text only** – show content as before.
  - **Attachment only (one image/video/audio file)** – now show the media tile.
  - **Mixed content** – show both text and attachments.

### 4.6 Navigation from pinned list to channel

- For each pinned row tap:
  - `navigateToMessage(_:)` builds a deep link similar to the Channel Search screen:
    - Uses `generateMessageLink(serverId: channel.server, channelId: message.channel, messageId: message.id, viewState: viewState)` to produce a web URL (e.g. `https://peptide.chat/server/{server}/channel/{channel}/{message}` or `/channel/{channel}/{message}` for DMs).
  - `handleMessageURL(_:)` mirrors `ChannelSearch`’s logic:
    - Validates server/channel existence and that the current user has access.
    - Sets `viewState.currentTargetMessageId = messageId`.
    - Clears `viewState.path` and appends `.maybeChannelView` so the main channel VC loads and `scrollToTargetMessage()` takes the user to the pinned message in context.
 
---

## 5. “XYZ Pinned a Message” → Scroll to That Message

**Current state**

- System messages “Message pinned by X” / “Message unpinned by X” are display-only (no tap).
- **`MessagePinnedSystemContent.id`** (pinned message ID) is not used for navigation.

**Planned**

- **UIKit:** In **`SystemMessageCell`**, add tap for `.message_pinned` / `.message_unpinned`: set target message ID (e.g. `viewController.targetMessageId = content.id` or `viewState.currentTargetMessageId`) and call **`scrollToTargetMessage()`**.
- **SwiftUI:** In **`SystemMessageView`**, add tap that sets **`viewState.currentTargetMessageId = content.id`** and triggers the same scroll flow.

---

## 6. Codebase Reference

### Types / Models

| Location | Relevant content |
|----------|------------------|
| `Types/Message.swift` | **`Message.pinned: Bool?`** (init, CodingKeys); `MessagePinnedSystemContent`; `SystemMessageContent.message_pinned` / `message_unpinned` |
| `Types/Channel.swift` | Channel types – no `pinned_ids` yet |
| `Types/Permissions.swift` | `manageMessages`, `manageChannel` |

### API

| Location | Relevant content |
|----------|------------------|
| `Revolt/Api/Http.swift` | **`pinMessage(channel:message:)`** (POST), **`unpinMessage(channel:message:)`** (DELETE) |

### UI and sheet

| Location | Relevant content |
|----------|------------------|
| `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift` | **`canPinMessage()`**; **`MessageAction.pin`** / **`.unpin`** |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+ContextMenu.swift` | Builds **`MessageOptionViewController`** with **`canPinMessage()`**, **`isMessagePinned: message.pinned == true`** |
| `Revolt/Pages/Channel/Messagable/Views/MessageOptionViewController.swift` | **`canPinMessage`**, **`isMessagePinned`**; Pin/Unpin row (title, icon, `.pin`/`.unpin` action) |
| `Revolt/Pages/Channel/Messagable/Views/SystemMessageCell.swift` | “Message pinned/unpinned by X” (display only) |
| `Revolt/Components/MessageRenderer/SystemMessageView.swift` | Same in SwiftUI (display only) |

### Handlers

| Location | Relevant content |
|----------|------------------|
| `Revolt/Pages/Channel/Messagable/Managers/RepliesManager.swift` | **`handleMessageAction`**: **`.pin`** (API + set `pinned = true` + alert + refresh), **`.unpin`** (API + set `pinned = false` + alert + refresh) |

### Data source / table

| Location | Relevant content |
|----------|------------------|
| `Revolt/Pages/Channel/Messagable/DataSources/MessageTableViewDataSource.swift` | Uses `SystemMessageCell`; sets `cell.onMessageAction` → `viewController?.handleMessageAction` |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Setup.swift` | Registers `SystemMessageCell` |

### Target message / scroll (for future tap-to-message)

| Location | Relevant content |
|----------|------------------|
| `Revolt/ViewState.swift` | `currentTargetMessageId` |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TargetMessage.swift` | `scrollToTargetMessage()`, `loadMessagesNearby(messageId:)` |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Lifecycle.swift` | Picks up `currentTargetMessageId`, triggers scroll |

### Channel Info

| Location | Relevant content |
|----------|------------------|
| `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelInfo.swift` | Channel information sheet; navigation entry for pinned messages (via header pin icon + navigation path) |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/PinnedMessagesView.swift` | Pinned messages list powered by `fetchPinnedMessages` and `MessageView` |

---

## 7. Suggested Order of Work (Remaining)

1. **(Optional)** **NotPinned handling:** On unpin 400 with `type: "NotPinned"`, set `viewState.messages[message.id]?.pinned = false` and show a short message or sync silently.
2. **(Optional)** **Stricter server-channel permission:** Change **`canPinMessage()`** so only users with `manageMessages` (or `manageChannel`) can pin in server channels (remove author shortcut).
3. **Tap “Message pinned by X”:** Add tap on **SystemMessageCell** / **SystemMessageView** → set target message ID and call **`scrollToTargetMessage()`**.
4. **Pinned list enhancements:** Add pagination (before/after), error/empty‑state refinements, and optional filters (e.g. “Pins by me”) on top of the current search‑backed implementation.

---

## 8. Bug Log & Implementation Notes (iOS)

This section documents the main issues discovered while implementing the pin feature and how they were fixed, to help future maintainers.

### 8.1 Wrong action for Pin vs Unpin

**Symptom**

- Long‑press a message and choose “Pin Message”:
  - Network error logs show **“Failed to unpin message”**.
  - Server returns `400` with `{"type":"NotPinned", ...}` even when the message was never pinned.
- Similarly, pin → unpin → pin again could still show “Failed to unpin message”.

**Root cause**

- In `MessageOptionViewController.setupOptions()` the handler for the Pin row used:
  - `if ((self?.isMessagePinned) != nil) { ... .unpin ... } else { ... .pin ... }`
  - `isMessagePinned` is a **Bool**, so `self?.isMessagePinned` is `Bool?` and is **non‑nil** for both `true` and `false`.
  - As a result, the branch always took the `.unpin` path, so the app tried to unpin even when the UI label said “Pin Message”.

**Fix**

- Compare the actual value instead of nil‑ness:
  - `if self?.isMessagePinned == true { onOptionSelected(.unpin) } else { onOptionSelected(.pin) }`

**Takeaway**

- Be careful when using optionality checks on boolean state in UIKit code; `Bool?` being non‑nil does not mean “true”.

### 8.2 Pinned sheet background only partially filled

**Symptom**

- In the pinned messages sheet, when there were **no pinned messages**, only the top portion around the empty state was in the gray background; the area below was black.

**Root cause**

- The `UnevenRoundedRectangle` gray background was applied only to the **inner** VStack (header + content), while a `Spacer` lived in the outer VStack with no background.

**Fix**

- Moved the background modifier to the **outer** VStack (the one that includes the `Spacer`), so the sheet uses a uniform gray background for the full height.

### 8.3 Header pin button layout and long channel names

**Issues**

1. **Initial pin button position**
   - When the pin icon was first added to the header it had no Auto Layout constraints and defaulted to `(0,0)` in `headerView`, overlapping the status bar.
   - Fixed by pinning it to the right side, to the left of the search button, aligned vertically with the back button.

2. **Long channel name overlapping icons**
   - The channel name label’s trailing constraint pointed at the **search button**, not the pin button, and the label didn’t truncate.
   - On long channel names the text overlapped under the pin icon.

**Fix**

- Channel name label:
  - `numberOfLines = 1`, `lineBreakMode = .byTruncatingTail` so it shows an ellipsis when it doesn’t fit.
  - Trailing constraint changed to:
    - `channelNameLabel.trailingAnchor <= pinnedMessageButton.leadingAnchor - 10`
  - This constrains the label strictly between the channel icon and the pin button.

**Result**

- Stable header layout:
  - Back chevron + channel icon + truncated channel name + pin + search.
  - Pin and search buttons stay tappable even on very long names.

### 8.4 Attachments not visible for pinned messages (single media)

Covered in **§4.5**, but in short:

- The pinned sheet reused `MessageView`, which ultimately uses `MessageContentsView` for attachments.
- `MessageContentsView` handled 2–5 media attachments but not the **1‑attachment** case, so attachment‑only messages with a single image/video/audio looked blank.
- Fix: add an explicit `mediaAttachments.count == 1` branch that renders a full‑width `MessageAttachment`.

### 8.5 “NotPinned” backend error semantics

**Behavior**

- When unpinning a message that is already unpinned (e.g. another device unpinned it first), the backend responds with:
  - HTTP 400, body `{"type":"NotPinned","location":".../message_unpin.rs:.."}`.
- Current iOS behavior (still acceptable, but could be refined):
  - Logs `Failed to unpin message: HTTPError(Optional("{\"type\":\"NotPinned\",...}"), 400)`.
  - Shows a generic “Failed to unpin message” alert.

**Recommended future improvement**

- Treat `400 + type == "NotPinned"` as a **sync** case, not an error:
  - Set `viewState.messages[message.id]?.pinned = false`.
  - Optionally show a softer message (“Message is not pinned”) or no alert.
  - Avoid scaring the user with “Failed to unpin” when the message is already in the desired state.
