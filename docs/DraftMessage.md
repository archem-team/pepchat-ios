# Message Drafts – Implementation Plan

This document describes how to implement **message drafts** (composer text saved per channel and restored when returning) in the current codebase. The design avoids any changes to core chatting or message cache functionality.

---

## 1. Scope and Constraints

### 1.1 What “draft messages” means here

- **Draft** = the **composer text** (and only the text) that the user has typed but not sent in a given channel.
- One draft per channel; when the user leaves the channel, the current composer text is saved; when they return, it is restored.
- **Out of scope for this plan:** reply context, thread IDs, attachments, or server-synced drafts. Those can be added later without changing the approach below.

**Text-only drafts and traditional chat behavior:** This plan keeps drafts **text-only** and does **not** restore reply or edit context. In reply/edit scenarios, behavior is therefore **less like traditional chat apps**. Only the composer text is saved and restored. When they return, they see the text but not the reply or edit UI state. Traditional chat apps often restore that context; adding it later (see Optional Later Enhancements) would align with that UX. For this plan, expect plain-text-only.

### 1.2 What must not change

- **Message cache:** No changes to `MessageCacheManager`, `MessageCacheWriter`, or any SQLite message cache. No new tables, no new write paths, no reuse of message cache for drafts.
- **Core send flow:** Sending messages, queued (offline) messages, and API/WebSocket behavior remain unchanged. Drafts are a separate, local-only feature.
- **Message loading:** How messages are loaded (cache, API, ViewState) is unchanged.
- **Existing cleanup and lifecycle:** Logic in `viewWillDisappear` / `viewDidDisappear` (scroll, timers, target message, etc.) stays as-is except for adding **read-before-cleanup** and **optional clear** as described below.

---

## 2. Current Codebase Touchpoints

The following touchpoints are required for the core draft flow. **Step 2b** (termination/background persistence) requires **additional** touchpoints depending on implementation choice—either typing-based autosave or app lifecycle hooks—see step 2b and the Files-to-Touch table (section 5) for those options.

### 2.1 Where composer text lives

| Location | Purpose |
|----------|--------|
| `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift` | Holds `textView`; `textView.text` is the composer text. `setText(_:)` (line ~302) sets it; there is no current persistence. |
| `MessageInputView.cleanup()` (line ~275) | Called when leaving the channel. It does **not** read or save `textView.text`; it only clears references and observers. |

So: **draft save** must happen **before** `messageInputView?.cleanup()` is called, by reading `messageInputView?.textView.text` from the view controller.

### 2.2 When the user leaves the channel

| File | Method | Notes |
|------|--------|--------|
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Lifecycle.swift` | `viewWillDisappear(_:)` | Dismisses keyboard, cancels work items; does **not** currently save draft. Skip draft save when `isReturningFromSearch == true`. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Extensions.swift` | `viewDidDisappear(_:)` | Calls `messageInputView?.cleanup()`. **Save draft here, immediately before** `messageInputView?.cleanup()`, so we can still read `textView.text`. Skip when `isReturningFromSearch` or when “staying in same channel” (target message) as per existing early returns. |

So: **save draft** in `viewDidDisappear` in `MessageableChannelViewController+Extensions.swift`, right before `messageInputView?.cleanup()`, and only when not skipping cleanup (same conditions as the existing early returns).

### 2.3 When the user enters the channel

| File | Method | Notes |
|------|--------|--------|
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` | `viewDidLoad()` | Calls `setupMessageInput()` (~268). After that, `messageInputView` and `viewModel.channel` are valid. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` | `viewWillAppear(_:)` (~375) | Good place to **restore draft**: load draft for `viewModel.channel.id` and, if non-empty, call `messageInputView.setText(draft)`. |

So: **load draft** in `viewWillAppear` (e.g. after existing setup), using `viewModel.channel.id` and a new ViewState (or equivalent) API to get the draft string.

**Lifecycle guarantee for restore:** When restoring in `viewWillAppear`, **if** there is a stored draft for this channel, call `messageInputView.setText(draft)`. **If there is no stored draft (nil or empty), do not clear the composer**—leave `messageInputView` unchanged. Reason: `viewDidDisappear` intentionally skips save (and cleanup) when `isReturningFromSearch` or same-channel target-message (early return). On those paths the user returns to the same channel without a new save; the composer may still hold valid in-memory text. Unconditional `setText("")` when loadDraft returns nil would wipe that text and break expected same-channel-return and return-from-search behavior. For a *different* channel we typically have a new VC instance with a fresh composer; for the same channel we preserve in-memory state when there is no stored draft.

### 2.4 When the user commits to send (clear draft at commit time)

Draft must be cleared **when the user commits to send**, not only after API success. Otherwise:
- **Offline/queued path:** User taps send while offline; message is queued. If we only clear on API success, the draft is never cleared and reappears when they re-open the channel.
- **Crash window:** App crashes after tap but before API response; sent text remains in draft store and duplicates when they return.

So: **clear draft for the channel as soon as we have committed the message** (to the UI queue and/or to the API).

| File | Method | Notes |
|------|--------|--------|
| `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift` | `sendMessage(_:)` | **Clear draft at commit:** (1) In the **offline** branch, right after `queueMessage(convertedText)` and before `return`, call `viewModel.viewState.clearDraft(channelId: viewModel.channel.id)`. (2) In the **online** branch, call `clearDraft(channelId:)` once when we have committed (e.g. right after we add the message to `queuedMessages` / `channelMessages` and before or alongside firing the `Task` that calls the API). Do **not** rely only on clearing after successful `http.sendMessage(...)`. |
| Same file | `sendMessageWithAttachments(_:attachments:)` | Same rule: clear draft for the channel at commit time (when we add to queued messages and start the send/upload flow), not only after upload/send success. |

The composer text is already cleared in `MessageInputView.sendButtonTapped()`. Clearing the **stored** draft at commit time (not only after API success) ensures the draft store never holds text the user has already sent—covering online send, offline/queued send, and crash-after-tap.

### 2.5 Sign-out and account-session binding

- **Account-session binding:** Draft storage must be tied to **session availability**, not used with a stale or cleared identity. Use the same binding point as the message cache: **Ready event.** When `ViewState+ReadyEvent.processReadyData` runs, `currentUser` and `baseURL` are set and `MessageCacheWriter.shared.setSession(userId:baseURL:)` is called. **Draft storage must bind at the same time:** in `processReadyData`, after `MessageCacheWriter.shared.setSession(...)`, load drafts from UserDefaults for that `(userId, baseURL)` into the in-memory draft structure. All draft read/write must use this bound session; if there is no valid session (e.g. not yet Ready, or after sign-out), do not read/write drafts.
- **Sign-out cleanup order (critical):** `destroyCache()` is called from `RevoltApp.swift` (Welcome.onAppear when `state == .signedOut && sessionToken != nil`). If that UI path is skipped or interrupted (e.g. app killed before Welcome appears, or navigation never shows Welcome), destroyCache() may never run and drafts would survive after sign-out. **Therefore use two clear points:** (1) **In `signOut()`** (ViewState+Auth): before or as `state = .signedOut` is set, `currentUser` and `baseURL` are still valid; call the draft-clear API (e.g. `clearAllDraftsForCurrentAccount()`) there so drafts are removed as soon as the user signs out, regardless of whether destroyCache() runs. (2) **At the very start of `destroyCache()`**: also clear drafts using `currentUser?.id` and `baseURL` before they are cleared—safety net when destroyCache() does run (e.g. when Welcome.onAppear fires). Never clear drafts only in one place; clearing in both signOut() and at the start of destroyCache() makes the guarantee lifecycle-robust.
- **Multi-account:** Drafts are keyed by account (`userId` + `baseURL`). Clear using that key in signOut() (while identity is still set) and again at the start of destroyCache() when it runs.

---

## 3. Storage Design

### 3.1 Where to store

- **UserDefaults only.** No SQLite, no message cache, no new files in `Revolt/1Storage/` for message cache.
- One key per account, e.g. `"channelDrafts_\(userId)_\(baseURL)"`, so:
  - Each account has its own drafts.
  - Sign-out can remove the key for that account (or clear the in-memory structure and not re-persist).

### 3.2 Shape of data

- **In-memory:** `[String: String]` = channelId → draft text (plain string, what the user sees in the composer).
- **Persisted:** Same structure encoded (e.g. JSON) under the account-specific UserDefaults key.
- **Size:** Cap draft length (e.g. 2000 characters to match message limit) before saving; truncate or ignore if over.

### 3.3 Who owns the API

- **ViewState** is the single source of truth for app state and already uses UserDefaults (and debounced saves where needed). Add:
  - **Draft storage in ViewState:** e.g. `channelDrafts: [String: String]` (or a dedicated small type) keyed by channel ID, with persistence keyed by `userId` and `baseURL`.
  - **Methods:** e.g. `saveDraft(channelId: String, text: String?)`, `loadDraft(channelId: String) -> String?`, `clearDraft(channelId: String)`, and `clearAllDraftsForCurrentAccount()` for sign-out.
- Alternatively, a small **DraftStore** (e.g. in ViewState+Extensions) that uses ViewState’s `currentUser` and `baseURL` to read/write UserDefaults, and is called from the view controller and MessageInputHandler. Either way, **no** logic in MessageCacheManager/MessageCacheWriter.

### 3.4 When to persist

- **Save:** (1) **Primary:** When leaving the channel (in `viewDidDisappear`, before `messageInputView?.cleanup()`). (2) **Required for termination/background:** Save-only-on-viewDidDisappear is weak against app termination or backgrounding (user types, app is killed or suspended before they leave the channel). So the plan **must** include at least one of: (a) debounced save while typing (e.g. every 1–2 seconds) so the draft is persisted without waiting for viewDidDisappear, or (b) save on `applicationWillTerminate` / `applicationDidEnterBackground` (e.g. from the active channel VC or AppDelegate) for the currently visible channel. Prefer (a) for smoother behavior; (b) is a minimum to avoid losing drafts on kill/background.
- **Load:** When entering the channel in `viewWillAppear`: if there is a stored draft for this channel, set the composer to it; if there is no stored draft (nil or empty), do not change the composer (see lifecycle guarantee in 2.3).
- **Clear:** At commit-to-send in `MessageInputHandler` for that channel (see 2.4). On sign-out, in **both** `signOut()` and at the start of `destroyCache()` for the current account (see 2.5).

---

## 4. Implementation Steps (Checklist)

1. **Add draft storage and API (ViewState or ViewState+Extensions)**
   - Add in-memory structure keyed by channel ID (e.g. `channelDrafts: [String: String]` or similar).
   - Persist/load using UserDefaults key `"channelDrafts_\(userId)_\(baseURL)"` (only when `userId` and `baseURL` are available).
   - Implement:
     - `saveDraft(channelId: String, text: String?)` — if `text` is nil or empty, remove draft for that channel; otherwise store (and optionally cap length), then persist.
     - `loadDraft(channelId: String) -> String?`
     - `clearDraft(channelId: String)`
     - `clearAllDraftsForCurrentAccount()` — call in both `signOut()` (before state = .signedOut) and at the very start of `destroyCache()` (see step 5).
   - **Session binding:** Do **not** load drafts in ViewState init (identity may not be set yet). Load drafts from UserDefaults in `ViewState+ReadyEvent.processReadyData`, after `MessageCacheWriter.shared.setSession(userId:baseURL:)`, for that (userId, baseURL) into the in-memory structure. All read/write uses this bound session.

2. **Save draft when leaving channel**
   - In `MessageableChannelViewController+Extensions.swift`, in `viewDidDisappear(_:)`, **before** the existing `messageInputView?.cleanup()` call:
     - If the method would return early (e.g. `isReturningFromSearch`, or “staying in same channel” for target message), do **not** save draft (same as not cleaning up).
     - Otherwise, read `messageInputView?.textView.text`, trim/validate length, then call `viewModel.viewState.saveDraft(channelId: viewModel.channel.id, text: ...)`.
   - Do not change any other cleanup logic or message cache.

2b. **Save draft on termination/background (required)**
   - Save-only-on-viewDidDisappear is weak when the app is killed or backgrounded before the user leaves the channel. Implement at least one of:
     - **Debounced save while typing:** On `textView` change (e.g. in the existing textViewDidChange path), debounce (e.g. 1–2 s) and call `saveDraft(channelId:text:)` for the current channel so the draft is persisted without waiting for viewDidDisappear; or
     - **Save on app lifecycle:** On `applicationWillTerminate` / `applicationDidEnterBackground`, if the active screen is a messageable channel, read the composer text and call `saveDraft(channelId:text:)` for that channel.
   - Use the same storage API; no message cache changes.

3. **Restore draft when entering channel**
   - In `MessageableChannelViewController`, in `viewWillAppear(_:)`, after existing setup:
     - Call `viewModel.viewState.loadDraft(channelId: viewModel.channel.id)`.
     - If the result is non-empty, call `messageInputView.setText(draft)` so the composer shows the draft.
     - **If the result is nil or empty, do not change the composer** (do not call setText("") or clearTextInput()). Leaving it unchanged preserves valid in-memory text when the user is returning from search or same-channel target-message, where viewDidDisappear skipped save. Do not change how the rest of the view or message list is loaded.

4. **Clear draft at commit-to-send (all paths)**
   - In `MessageInputHandler.sendMessage(_:)`: (1) In the **offline** branch, right after `queueMessage(convertedText)` and before `return`, call `viewModel.viewState.clearDraft(channelId: viewModel.channel.id)`. (2) In the **online** branch, call `clearDraft(channelId:)` once when we have committed the message (e.g. right after adding to `queuedMessages` / `channelMessages`, before or alongside firing the API `Task`). Do **not** rely only on clearing after successful `http.sendMessage(...)`.
   - In `MessageInputHandler.sendMessageWithAttachments(_:attachments:)`, call `clearDraft(channelId:)` at commit time (when we add to queued messages and start the send/upload flow), not only after success.
   - Do not change send logic, queued messages, or cache writes.

5. **Clear drafts on sign-out (two clear points for lifecycle robustness)**
   - **First clear — in `signOut()`:** In `ViewState+Auth.signOut()`, before setting `state = .signedOut`, `currentUser` and `baseURL` are still set. Call the draft-clear API (e.g. `clearAllDraftsForCurrentAccount()`) there. That way drafts are removed as soon as the user signs out even if `destroyCache()` is never invoked (e.g. Welcome.onAppear is skipped or interrupted).
   - **Second clear — at the start of `destroyCache()`:** At the very start of `ViewState.destroyCache()`, before any line that clears `currentUser` or other identity, read `currentUser?.id` and `baseURL` and call the draft-clear API again. This is a safety net when destroyCache() does run (it is invoked from Welcome.onAppear when `state == .signedOut && sessionToken != nil`). Relying only on destroyCache() is lifecycle-fragile because that UI path may not run.

6. **Edge cases**
   - **Return from search:** Already skipped in `viewDidDisappear`; do not save draft in that case.
   - **Same-channel target message:** Already skipped in `viewDidDisappear`; do not save draft in that case.
   - **Empty or whitespace-only text:** Treat as “no draft”; save `nil` or empty and remove that channel’s draft.
   - **Character limit:** When saving, cap draft length (e.g. 2000) to avoid storing huge strings.
   - **Reply/edit state:** Not persisted. Only composer text is saved; reply-to and editing-message state are not. Restored draft is plain text only (see known behavior gap in 1.1).

7. **Lifecycle guarantees (summary)**
   - **Restore:** On every `viewWillAppear`, if there is a stored draft for this channel, set the composer to it. If there is no stored draft, do not clear the composer (preserve in-memory text for same-channel return and return-from-search).
   - **Save:** Persist draft when leaving (viewDidDisappear, before cleanup) and additionally via debounced typing and/or on app termination/background so drafts survive kill/background.
   - **Clear draft:** At commit-to-send (offline and online paths), not only after API success. On sign-out, clear in both `signOut()` (while identity is set) and at the start of `destroyCache()` when it runs, so drafts are gone even if Welcome.onAppear never runs.
   - **Session binding:** Load and use drafts only when the session is bound (e.g. after Ready). Clear drafts for the current account in both `signOut()` and at the start of `destroyCache()` for lifecycle robustness.

8. **Test scenarios**
   - **Search return:** From a channel with draft text, navigate to search and back. Draft should still be present (no save on viewDidDisappear when returning from search); composer should show the same draft. No duplicate or lost draft.
   - **Target-message same channel:** Navigate to the same channel with a target message (e.g. reply deep link). viewDidDisappear should not save (early return); no spurious overwrite of draft. When staying in same channel, behavior should remain correct.
   - **Sign-out:** With draft text in one or more channels, sign out. After sign-out and (if applicable) sign-in as another account, no drafts from the previous account should appear. Verify draft UserDefaults key for the old account is removed and that no cross-account draft leak occurs.
   - **Offline send:** Type draft, tap send while offline. Message is queued. Re-open channel: composer should be empty and stored draft for that channel should be cleared (cleared at commit, not at API success).
   - **Crash after send:** (Manual or instrumented.) Tap send (online); clear draft at commit. If the app crashes before API response, re-open channel: composer should be empty and no duplicate of the sent text as draft.
   - **Reply/edit context not restored (known gap):** Type text while replying to a message or while editing a message; leave the channel so the draft is saved. Return to the channel: the composer should show the saved text but **not** the reply or edit UI state. This is expected; the plan does not persist reply/edit context.

---

## 5. Files to Touch (Summary)

| File | Change |
|------|--------|
| `Revolt/ViewState.swift` or new `Revolt/ViewState+Extensions/ViewState+Drafts.swift` | Add draft storage (session-bound: load in processReadyData after setSession). UserDefaults key by userId/baseURL. Methods: saveDraft, loadDraft, clearDraft, clearAllDraftsForCurrentAccount. |
| `Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift` | In `processReadyData`, after `MessageCacheWriter.shared.setSession(...)`, load drafts from UserDefaults for that (userId, baseURL) into the in-memory draft structure (bind draft storage to session). |
| `Revolt/ViewState+Extensions/ViewState+Auth.swift` | **Two clear points:** (1) In `signOut()`, before `state = .signedOut`, call draft-clear API (currentUser/baseURL still valid) so drafts are gone even if destroyCache() never runs. (2) At the **very start** of `destroyCache()`, call draft-clear API again before clearing `currentUser`/identity. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Extensions.swift` | In `viewDidDisappear`, before `messageInputView?.cleanup()`, read composer text and call ViewState saveDraft (when not in early-return cases). |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` | In `viewWillAppear`, load draft for `viewModel.channel.id`; if non-empty set on messageInputView. **If nil/empty, do not clear the composer** (preserve same-channel return / return-from-search behavior). |
| `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift` | **Clear draft at commit:** In `sendMessage`, clear draft in offline branch (after queueMessage) and in online branch (when adding to queuedMessages/channelMessages). In `sendMessageWithAttachments`, clear draft at commit time. |

**Additional touchpoints for step 2b (choose at least one):**
| Option | File(s) | Change |
|--------|----------|--------|
| Debounced save while typing | `MessageableChannelViewController+TextView.swift` and/or `MessageInputView.swift` (where `textViewDidChange` is handled) | On text change, debounce (e.g. 1–2 s) and call ViewState `saveDraft(channelId:text:)` for the current channel. |
| Save on app lifecycle | `RevoltApp.swift` and/or the app/scene delegate (e.g. `applicationWillTerminate` / `sceneDidEnterBackground`) | When app is terminating or entering background, if the top/visible screen is a messageable channel, read its composer text and call ViewState `saveDraft(channelId:text:)` for that channel. |

**No changes:**  
`MessageCacheManager`, `MessageCacheWriter`, message loading, WebSocket/HTTP send logic, `MessageInputView.cleanup()` implementation (only the call site adds a read-before-cleanup).

---

## 6. What Stays Unchanged (Reference)

- **Message cache:** `Revolt/1Storage/MessageCacheManager.swift`, `Revolt/1Storage/MessageCacheWriter.swift` — no new tables, no draft data, no new write paths.
- **Message send flow:** Existing `sendMessage` / `sendMessageWithAttachments` logic, queued messages, and cache writes after send remain as they are; only add `clearDraft(channelId:)` at **commit time** (offline branch and online branch in sendMessage; commit time in sendMessageWithAttachments). Do **not** add clearDraft only after API success—that would break offline and crash-after-tap guarantees.
- **Channel/message loading:** `MessageableChannelViewController+MessageLoading.swift`, ViewState message/channel state, and cache reads are unchanged.
- **MessageInputView:** No change to `cleanup()` implementation; the view controller will read `textView.text` before calling `cleanup()`.
- **Replies, editing, attachments:** No change to reply or edit flows; draft is only “composer text”. Attachments are not stored as part of the draft in this plan.

---

## 7. Optional Later Enhancements (Not in This Plan)

- Debounced auto-save of draft while typing (same storage API).
- **Restoring reply and edit context with the draft:** Storing and restoring “replying to message X” and “editing message Y” along with the text would make draft behavior **traditional chat app–like**. That would require persisting reply/edit metadata (e.g. message id, channel id) per channel in the draft store and, on restore, calling the same reply/edit UI entry points the app already uses (e.g. setReplyingToMessage / setEditingMessage) before setting the draft text. Out of scope for the current plan.
- Server-synced drafts (would require backend support and different storage).
- Per-thread drafts if the app adds threads.

---

## Implementation (What Was Done in the Codebase)

**This section states what changes have been done according to the implementation plan in the codebase.** Each item below corresponds to a concrete edit; no plan items were skipped.

### 1. Draft storage and API (step 1)

- **`Revolt/ViewState.swift`**
  - Added property: `var channelDrafts: [String: String] = [:]` (after `queuedMessages`). Comment: per-channel draft text; session-bound; loaded in processReadyData, cleared in signOut/destroyCache.
- **New file: `Revolt/ViewState+Extensions/ViewState+Drafts.swift`**
  - `draftStorageKey()` (private): returns `"channelDrafts_\(userId)_\(baseURL)"` when `currentUser?.id` and `baseURL` are non-empty; otherwise nil.
  - `loadDraftsFromUserDefaults(userId:baseURL:)`: decodes `[String: String]` from UserDefaults for that key and assigns to `channelDrafts`; on decode failure sets `channelDrafts = [:]`.
  - `saveDraft(channelId:text:)`: if text is nil or trimmed empty, removes entry for channelId; else stores trimmed text capped at 2000 chars. Persists `channelDrafts` to UserDefaults under `draftStorageKey()`. No-op if key is nil.
  - `loadDraft(channelId:) -> String?`: returns `channelDrafts[channelId]`; returns nil if session not bound.
  - `clearDraft(channelId:)`: removes entry for channelId and persists.
  - `clearAllDraftsForCurrentAccount()`: sets `channelDrafts = [:]` and removes UserDefaults key for current account; no-op if key is nil.

### 2. Session binding (step 1 / 2.5)

- **`Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift`**
  - In `processReadyData`, immediately after `MessageCacheWriter.shared.setSession(userId: uid, baseURL: url)`, added: `loadDraftsFromUserDefaults(userId: uid, baseURL: url)` so draft storage is bound to the same session as the message cache.

### 3. Clear drafts on sign-out (step 5)

- **`Revolt/ViewState+Extensions/ViewState+Auth.swift`**
  - In `signOut()`, before `state = .signedOut`, added: `clearAllDraftsForCurrentAccount()` so drafts are cleared as soon as the user signs out even if `destroyCache()` never runs.
  - At the very start of `destroyCache()`, before any other line, added: `clearAllDraftsForCurrentAccount()` as a safety net when the Welcome.onAppear path does run.

### 4. Save draft when leaving channel (step 2)

- **`Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Extensions.swift`**
  - In `viewDidDisappear(_:)`, after the early returns (isReturningFromSearch, same-channel target message) and after invalidating the scroll timer, **before** `messageInputView?.cleanup()`, added: read `messageInputView?.textView.text` and call `viewModel.viewState.saveDraft(channelId: viewModel.channel.id, text: text)`. No other cleanup or message-cache logic was changed.

### 5. Restore draft when entering channel (step 3)

- **`Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`**
  - In `viewWillAppear(_:)`, after `updateTableViewBouncing()`, added: if `viewModel.viewState.loadDraft(channelId: viewModel.channel.id)` returns a non-empty string, call `messageInputView.setText(draft)`. If nil or empty, the composer is **not** cleared (preserves same-channel return and return-from-search behavior).

### 6. Clear draft at commit-to-send (step 4)

- **`Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift`**
  - In `sendMessage(_:)`, **offline** branch: immediately after `queueMessage(convertedText)` and before the alert/return, added: `viewModel.viewState.clearDraft(channelId: viewModel.channel.id)`.
  - In `sendMessage(_:)`, **online** branch: immediately after adding the temporary message to `viewModel.viewState.messages[messageNonce]` (and after appending to `queuedMessages` / `channelMessages`), added: `viewModel.viewState.clearDraft(channelId: viewModel.channel.id)` (commit-time clear, not after API success).
  - In `sendMessageWithAttachments(_:attachments:)`, at the same commit point (after adding the message to `messages` / `queuedMessages` / `channelMessages`), added: `viewModel.viewState.clearDraft(channelId: viewModel.channel.id)`.

### 7. Debounced save while typing (step 2b)

- **`Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`**
  - Added property: `var draftSaveWorkItem: DispatchWorkItem?` (next to `scrollToBottomWorkItem`) to hold the debounced save work item.
- **`Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TextView.swift`**
  - In `textViewDidChange(_:)`, when `textView == messageInputView.textView`, after forwarding to `messageInputView.textViewDidChange(textView)`: cancel `draftSaveWorkItem`, capture `channelId` and current `text`, create a `DispatchWorkItem` that calls `viewModel.viewState.saveDraft(channelId: channelId, text: text)`, store it in `draftSaveWorkItem`, and schedule it on `DispatchQueue.main` with a 1.5 s delay.
- **`Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Lifecycle.swift`**
  - In `viewWillDisappear(_:)`, in the block that cancels pending operations, added: `draftSaveWorkItem?.cancel()` and `draftSaveWorkItem = nil` so the debounced save does not run after the user has left the channel.

### 8. What was not changed

- **Message cache:** `MessageCacheManager`, `MessageCacheWriter` — no new tables, no draft data, no new write paths.
- **Send flow:** No change to HTTP/WebSocket send logic, queued message handling, or cache writes; only `clearDraft(channelId:)` calls at commit time were added.
- **Message loading:** Unchanged.
- **`MessageInputView.cleanup()`:** Implementation unchanged; the view controller saves the draft by reading `textView.text` before calling `cleanup()`.
- **Reply/edit flows:** Unchanged; draft is text-only (reply/edit context not persisted).

---

## Fixes

This section documents issues found after implementation and the changes made to fix them.

### Fix 1: Send button disabled after restoring draft

- **Issue:** After typing a draft, navigating back, and returning to the same channel, the draft text was restored in the composer but the send button remained disabled as if there were no message to send. The button only became enabled after the user started editing the text again.
- **Cause:** When the draft is restored, the view controller calls `messageInputView.setText(draft)`. In `MessageInputView`, `setText(_:)` sets `textView.text` and posts `textDidChangeNotification` but did **not** call `updateSendButtonState()`. The send button’s enabled state is updated in `updateSendButtonState()` (which checks `textView.text` and attachments); that was only invoked on user-driven text changes (e.g. `textViewDidChange`), not when text was set programmatically.
- **Fix:** In `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`, inside `setText(_:)`, call `updateSendButtonState()` after setting `textView.text` and `updateTextViewHeight()`. The send button now reflects content whenever text is set programmatically, including when a draft is restored.

### Fix 2: Invalid redeclaration of `text` in draft debounce

- **Issue:** Compiler error at `MessageableChannelViewController+TextView.swift:37` — “Invalid redeclaration of 'text'”.
- **Cause:** In `textViewDidChange(_:)`, inside the `if textView == messageInputView.textView` block, `let text = textView.text ?? ""` was declared twice: once for mention handling (line ~22) and again for the draft debounce (line ~37), in the same scope.
- **Fix:** Removed the second declaration and reused the existing `text` variable for the debounced `saveDraft(channelId:text:)` work item. The closure still captures the same `text` correctly.

### Fix 3: Send button enabled for whitespace-only input

- **Issue:** Entering only spaces (e.g. "      ") in the composer enabled the send button and allowed sending, even though there is no real character content. The send button should only enable when at least one non-whitespace character has been entered (or there are attachments).
- **Cause:** In `MessageInputView`, `updateSendButtonState()` used `hasText = !(textView.text?.isEmpty ?? true)`, so any non-empty string—including whitespace-only—counted as having text. Similarly, `sendButtonTapped()` used `guard !text.isEmpty || hasAttachments`, so sending was allowed for whitespace-only content.
- **Fix:** In `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`: (1) In `updateSendButtonState()`, compute `hasText` from trimmed text: `let trimmed = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""` and `let hasText = !trimmed.isEmpty`, so the send button enables only when there is at least one non-whitespace character or there are attachments. (2) In `sendButtonTapped()`, change the guard to `guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments else { return }` so a tap does nothing when the composer contains only whitespace and no attachments.

### Fix 4: Restored long draft shows as single line until user edits (TC-06)

- **Issue:** When a long draft (>2000 chars or any multi-line content) is restored (e.g. open channel A, type a long message so the composer shows multiple lines, navigate back, then return to channel A), the draft text is restored but the composer **displays in a single line**. Only after the user starts editing does the text field expand back to multiline.
- **Cause:** Draft restore happens in `viewWillAppear` via `messageInputView.setText(draft)`, which calls `updateTextViewHeight()`. At that time the text view may not yet be laid out, so `textView.frame.width` is 0. `sizeThatFits(CGSize(width: 0, ...))` then returns a single-line height, so the height constraint stays at the minimum and the content appears as one line until the next layout or user edit.
- **Fix:** In `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`: (1) In `updateTextViewHeight()`, when `textView.frame.width` is 0, use an effective width derived from the container: `bounds.width` minus the horizontal space for the plus button, send button, and padding (10+40+10+10+48+10). This allows a correct multiline height when text is set before layout (e.g. draft restore). (2) In `layoutSubviews()`, when the text view has non-empty text, call `updateTextViewHeight()` again so that once the real width is available after layout, the height is recomputed and the multiline appearance is correct without requiring the user to edit.

### Fix 5: Scrolling disabled for restored or long draft (single line until clear and retype)

- **Issue:** When a long draft is restored (or the user has a long draft and navigates back/return or edits it), scrolling inside the composer is disabled—the user cannot scroll the draft text. Scrolling only works again after clearing the message entirely and typing a long message from scratch.
- **Cause:** (1) When `isScrollEnabled` is false, UITextView does not reliably update its `contentSize` when text is set programmatically. (2) A later layout pass can call `updateTextViewHeight()` with a wrong width, so we set `isScrollEnabled = false` and the long draft stays non-scrollable.
- **Fix:** In `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`: (1) In `setText(_:)`, set `textView.isScrollEnabled = true` before assigning `textView.text`, then call `updateTextViewHeight()` and schedule a second `updateTextViewHeight()` on the main queue so it runs after layout (when the first call may have returned early with zero width). (2) In `updateTextViewHeight()`, if `textViewHeightConstraint.constant >= maxHeight`, always set `textView.isScrollEnabled = true`; otherwise set from `newHeight`. (3) After setting the height constraint and laying out, when `newHeight >= maxHeight`, toggle `isScrollEnabled` off then on to force UITextView to recompute `contentSize` for the new frame. (4) If `contentSize.height > bounds.height + 1`, set `isScrollEnabled = true`.

---

*This plan is scoped so that message drafts are a local, additive feature and core chatting and message cache functionality remain unchanged.*
