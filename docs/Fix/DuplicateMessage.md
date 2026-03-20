# Duplicate Message Fixes

This document describes the fixes applied to prevent rare duplicate messages when a user sends a message (e.g. double-tap, flaky network, or WebSocket matching ambiguity).

## Root causes addressed

1. **Nonce was never sent to the server** – The client generated a nonce for each message but did not include it in the POST body, so the backend could not deduplicate by nonce.
2. **No guard against double submission** – A second tap or send trigger could start another send before the first completed, resulting in two requests with two different nonces.
3. **WebSocket matching was by content/author/channel only** – When the server echoed a message, the client matched it to a queued (optimistic) message by content, author, and channel. Sending the same text twice could match the wrong queued message; matching by nonce (when the server echoes it) is more reliable.

---

## Fix 1: Send nonce to the server

### Changes

- **Revolt/Api/Payloads.swift**  
  - Added `var nonce: String` to the `SendMessage` struct so the request body includes a unique id for server-side deduplication.

- **Revolt/Api/Http.swift**  
  - Updated the `req(...)` call in `sendMessage` to pass `nonce: nonce` into `SendMessage(replies:replies, content:content, attachments:attachmentIds, nonce:nonce)` so the nonce is sent in the JSON body of `POST /channels/{channel}/messages`.

### Note

Backend must accept and use the `nonce` field for idempotency (e.g. reject or merge duplicate requests with the same nonce). If the API does not yet support it, server-side changes are required for full deduplication.

---

## Fix 2: Guard against double submission in the UI

### Changes

- **Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift**
  - **Property:** `private var isSendingMessage = false` (already present; used for the guard).
  - **sendMessage(_:):**
    - At the start: `guard !isSendingMessage else { return }` so a second call while a send is in flight returns immediately.
    - After the offline branch, before creating the queued message: `isSendingMessage = true`.
    - On success: inside the existing `DispatchQueue.main.async` after posting `MessagesDidChange`, added `self.isSendingMessage = false`.
    - On failure: inside the existing `DispatchQueue.main.async` in the `catch` block (after `removeFailedMessageFromQueue` and alerts), added `self.isSendingMessage = false`.
    - When `currentUser` is nil (early exit): `isSendingMessage = false`.
  - **sendMessageWithAttachments(_:attachments:):**
    - At the start: `guard !isSendingMessage else { return }`.
    - Before creating the queued message: `isSendingMessage = true`.
    - On success: inside the existing `DispatchQueue.main.async` (after `onAttachmentsUploadComplete`), added `self.isSendingMessage = false`.
    - On failure: inside the existing `DispatchQueue.main.async` in the `catch` block, added `self.isSendingMessage = false`.
    - When `currentUser` is nil: `isSendingMessage = false`.

This ensures only one send (text or with attachments) is in progress at a time per handler instance; rapid double-tap or multiple triggers result in a single request.

---

## Fix 3: WebSocket matching by nonce when available

### Changes

- **Types/Message.swift**
  - Added optional `public var nonce: String?` to decode the nonce when the server echoes it in the message payload.
  - Extended `init(...)` with parameter `nonce: String? = nil` and set `self.nonce = nonce`.
  - Added `nonce` to `CodingKeys` so it is decoded from JSON.

- **Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift**
  - When processing an incoming message event, matching to a queued (optimistic) message now:
    1. Prefer **nonce match**: if `m.nonce` is non-nil, look up a queued message with `queued.nonce == m.nonce`.
    2. **Fallback**: if no nonce or no nonce match, use the existing content/author/channel match.
  - Introduced a `matchedQueuedMessage` flag so that when no queued message matches (by nonce or content/author/channel), the message is appended to `channelMessages` as a new message; when a match is found, the existing cleanup logic (replace nonce with real ID, remove from queue) runs and the message is not appended again.

Result: If the server includes nonce in the message event, the client matches by nonce and correctly replaces the single optimistic message. If the server does not send nonce, behavior is unchanged (content/author/channel fallback).

---

## Files modified (summary)

| Fix | File | Change |
|-----|------|--------|
| 1 | Revolt/Api/Payloads.swift | Add `nonce: String` to `SendMessage`. |
| 1 | Revolt/Api/Http.swift | Pass `nonce` into `SendMessage(...)` in `sendMessage`. |
| 2 | Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift | `isSendingMessage` guard, set on start and clear on success/failure in `sendMessage` and `sendMessageWithAttachments`. |
| 3 | Types/Message.swift | Add optional `nonce`, init parameter, and `CodingKeys` entry. |
| 3 | Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift | Match by nonce first, then content/author/channel; use `matchedQueuedMessage` to control append. |

---

## Testing suggestions

1. **Nonce in payload:** Inspect the outgoing request (proxy or backend log) and confirm `nonce` is present in the JSON body for `POST .../messages`.
2. **Double submission:** Rapidly double-tap send (or trigger send twice); only one message should be sent and one optimistic bubble replaced.
3. **WebSocket matching:** Send a message and confirm the optimistic message is replaced by the real ID when the event arrives. If the backend echoes nonce, send two identical messages in a row and confirm each is matched correctly (no duplicates, no wrong replacement).
