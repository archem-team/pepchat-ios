# Attachment Sharing From iOS Share Sheet

This document describes the implemented approach for **system share sheet attachment sharing** so a user can share photos, videos, documents, and other files from another app into ZekoChat/Peptide Chat, similar to Discord or WhatsApp.

The goal is: from Photos, Files, Safari, etc. -> tap iOS Share -> choose ZekoChat -> see a combined recipient picker -> choose one DM, group DM, or server channel -> send the attachment.

The first implementation adds a Share Extension target, shared app-group recipient index, shared keychain token access, and a compact SwiftUI destination picker. Some provisioning/capability setup still has to be completed manually in Xcode and Apple Developer.

---

## 1. Product Scope

### 1.1 User-facing behavior

- User opens another app, selects one or more attachments, and taps Share.
- ZekoChat appears as a share destination.
- ZekoChat opens a compact share extension UI with:
  - Preview of selected attachment(s).
  - Optional message/caption text field.
  - Search field.
  - Combined destination list:
    - Recent chats.
    - Direct messages.
    - Group DMs.
    - Joined servers with messageable text channels.
- User selects exactly one destination and taps Send.
- Share extension uploads attachments and sends a message to the selected channel.
- On success, extension dismisses and optionally shows a short success state before closing.
- On failure, extension shows a retry/cancel option. If the failure is auth/session related, offer "Open ZekoChat" to re-authenticate.

### 1.2 Out of scope for first version

- Sending to multiple recipients at once.
- Replying/editing context from share sheet.
- Creating a new DM from the share extension.
- Full server/channel management from the extension.
- Offline queue that survives extension termination. Extension runtime is short; failed sends should be explicit.
- Rich per-file editing/cropping before send.

### 1.3 Important iOS constraint

This cannot be implemented only inside the main app UI. iOS share sheet integration needs a new **Share Extension target** (`NSExtension`) with its own UI and lifecycle. The extension runs in a separate process, has limited memory/time, and cannot directly use the live `ViewState` singleton from the main app.

---

## 2. Recommended Architecture

### 2.1 High-level pieces

| Piece | Responsibility |
|------|----------------|
| Share Extension target | Receives `NSExtensionItem`s, previews files, shows recipient picker, sends attachments. |
| Shared App Group storage | Stores a lightweight, session-bound recipient index and temporary copied attachment files. |
| Shared Keychain access group | Allows extension to read the session token securely. |
| Shared networking/sender module | Minimal code path for upload attachments + send message, reused by app and extension where practical. |
| Main app sync writer | After Ready/event changes, writes recipient index for extension use. |

### 2.2 Data flow

1. Main app signs in and processes Ready.
2. Main app builds a compact **ShareRecipientIndex** from `ViewState`:
   - DMs and group DMs.
   - Servers and visible text channels.
   - User/server/channel display names and icons.
   - Permission hints, especially whether upload/send is likely allowed.
3. Main app writes that index to App Group storage, keyed by `userId + baseURL`.
4. User invokes iOS share sheet from another app.
5. Share extension loads:
   - Session token from shared Keychain.
   - `baseURL`, `currentUserId`, and recipient index from App Group storage.
   - Shared attachments from `NSItemProvider`.
6. User selects a destination.
7. Extension uploads files as `.attachment`, then sends the message to `/channels/{channel}/messages`.
8. On success, extension completes. Main app later receives WebSocket/update as normal, or will fetch/cache on next open.

---

## 3. Share Extension Target

### 3.1 Target setup

Add a new target, for example:

- Product type: Share Extension.
- Suggested module name: `ShareExtension` or `ZekoChatShareExtension`.
- Principal UI: SwiftUI hosted in a `UIViewController` or `SLComposeServiceViewController` replacement.

Prefer a custom `UIViewController` + SwiftUI view over `SLComposeServiceViewController`, because the feature needs a Discord-style destination picker, search, nested server/channel rows, previews, and upload progress.

### 3.2 Info.plist activation rules

The extension should support at least:

- Images.
- Movies/videos.
- Files/documents.
- URLs/text can be optional. If supported, URLs can be sent as caption text or as an attachment depending on provider type.

Activation rules should be conservative for v1:

- Limit max item count to the same effective max as the in-app composer.
- Accept common UTTypes first: `public.image`, `public.movie`, `public.file-url`, `public.data`, optionally `public.url`, `public.text`.
- Avoid claiming every type until file handling is hardened.

### 3.3 Attachment ingestion

The extension receives attachments through `NSItemProvider`.

Rules:

- Load file URLs using `loadFileRepresentation` where possible.
- Copy each file into the App Group temporary directory before the provider URL becomes invalid.
- For images where only object/data is provided, write data into a temporary file with a safe generated name.
- Keep original filename when available, but sanitize it.
- Infer MIME/UTType for validation and previews.
- Enforce:
  - Max file count.
  - Max per-file size.
  - Max total payload size.
  - Supported type list.
- Generate lightweight thumbnails for images/videos only after size validation.

Do not keep large files fully resident in memory longer than needed. Extension memory is tighter than the main app.

---

## 4. Recipient Picker Design

### 4.1 Combined sheet structure

The share extension UI should feel like one searchable destination sheet, not separate tabs that make the user think too hard.

Recommended layout:

- Top: attachment preview strip + optional caption input.
- Search field.
- List sections:
  - Recents.
  - Direct Messages.
  - Group DMs.
  - Servers.
- Server rows are expandable; expanded server shows messageable text channels.
- Selection is single-choice.
- Bottom/send affordance:
  - Disabled until a valid destination is selected and attachments are valid.
  - Shows upload/send progress after tap.

### 4.2 Recipient model

Create a small model specifically for sharing, instead of trying to decode all of `ViewState` inside the extension.

Example shape:

```swift
struct ShareRecipientIndex: Codable {
    let schemaVersion: Int
    let userId: String
    let baseURL: String
    let generatedAt: Date
    let recentChannelIds: [String]
    let dms: [ShareDestination]
    let groupDms: [ShareDestination]
    let servers: [ShareServerDestination]
}

struct ShareDestination: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let avatarFileName: String?
    let type: ShareDestinationType
    let canSendMessages: Bool
    let canUploadFiles: Bool
    let lastMessageId: String?
}

struct ShareServerDestination: Codable, Identifiable {
    let id: String
    let title: String
    let iconFileName: String?
    let channels: [ShareDestination]
}
```

`ShareDestination.id` should be the channel ID used for sending.

### 4.3 What to include

- DMs: active DMs and group DMs from `ViewState.dms`.
- Contacts/friends without an open DM:
  - Include friends from `ViewState.users` where relationship is `Friend`.
  - If no DM channel exists yet, the share extension resolves it through `/users/{user}/dm` before sending.
- Servers:
  - Include only joined servers from `ViewState.servers`.
  - Include only text channels, not voice channels.
  - Include only channels visible in `allEventChannels`/loaded server data.
  - Prefer channels where permission calculation says send and upload are allowed.

### 4.4 Permissions

Recipient index should include permission hints from the main app where available:

- `canSendMessages`
- `canUploadFiles`

The extension should still handle server rejection gracefully because permissions may change after the cached index was written.

If `canUploadFiles == false`, disable that row for attachment sharing and show a simple reason such as "Cannot upload files here."

---

## 5. Session and Security

### 5.1 Session token access

The current app stores `sessionToken` in Keychain via `KeychainAccess` service `chat.peptide.app`. A share extension cannot automatically read the app's private Keychain item unless Keychain Sharing is configured.

Recommended:

- Add a Keychain Access Group shared by app and extension.
- Store/read the session token through that access group.
- Keep `baseURL` and `currentUserId` in App Group UserDefaults or a small App Group JSON file.
- Do not store session token in UserDefaults or plaintext files.

### 5.2 App Group storage

The repo already references the App Group identifier:

- `group.pepchat.shared.data`

The share extension can reuse this group if the entitlement is already valid for both targets, or use a new clearly named group if product naming requires it. Keep one source of truth and document it in entitlements.

Use App Group storage for:

- Recipient index JSON.
- Small icon/avatar cache for picker rows.
- Temporary copied attachment files while extension is active.
- Optional pending handoff payload if the extension must open the main app.

### 5.3 Account/session binding

Every stored recipient index must be bound to:

- `userId`
- `baseURL`
- `schemaVersion`
- `generatedAt`

On sign-out/destroy cache:

- Clear recipient index for the current account.
- Clear shared avatar/icon files for that account if practical.
- Clear temporary share payloads.

If identity is missing, clear all share indexes in the App Group to avoid cross-account leakage.

---

## 6. Networking and Send Path

### 6.1 Preferred v1: send directly from extension

The best Discord/WhatsApp-like UX is direct send inside the share extension:

- User chooses destination.
- Extension uploads attachments.
- Extension sends message.
- Extension dismisses.

This avoids forcing the user into the main app.

The existing app flow already has the right conceptual sequence in `HTTPClient.sendMessage(channel:replies:content:attachments:nonce:progressCallback:)`:

1. Upload each attachment with category `.attachment`.
2. Collect attachment IDs.
3. `POST /channels/{channel}/messages` with `content`, `attachments`, `nonce`, and no replies.

For the extension, create a lightweight shared sender instead of pulling in all of `ViewState`:

- `ShareHTTPClient`
- `ShareAttachmentSender`
- `ShareSendRequest`

This shared sender should use the same backend endpoints and payload shape as the main app, but avoid UI/ViewState dependencies.

### 6.2 Fallback: handoff to main app

If direct extension sending is blocked by auth, package size, dependency complexity, or extension runtime limits, use a fallback handoff:

1. Extension copies attachments to App Group temp.
2. Extension writes a `PendingSharePayload` JSON with file paths and optional caption.
3. Extension opens the main app with a custom URL/deep link, e.g. `zeko.chat://share/<payloadId>`.
4. Main app loads payload, shows the same combined destination picker or opens a share compose sheet.
5. Main app sends using existing `MessageInputHandler`/`HTTPClient`.

This fallback is more reliable for very large uploads and stale sessions, but less seamless.

### 6.3 Recommendation

Implement direct extension sending for v1, with handoff only for:

- Missing/expired token.
- Recipient index missing or too stale.
- Attachment too large for extension memory/runtime.
- Send fails with auth/session error.

---

## 7. Main App Responsibilities

### 7.1 Write recipient index after Ready

After `ViewState+ReadyEvent.processReadyData` has authoritative user/server/channel state, build and save the share recipient index.

Good insertion points:

- End of `processReadyData`, after servers/channels/DMs are reconciled.
- After important topology changes:
  - DM created/removed.
  - Group DM updated.
  - Server joined/left.
  - Channel created/deleted/updated.
  - Permission-relevant server/channel updates.

Keep writes debounced and session-guarded, similar in spirit to existing cache patterns.

### 7.2 Do not expose full ViewState

Do not serialize full `ViewState` to the App Group. It is too large, too unstable, and risks leaking unrelated user data.

Only write the compact share index needed by the extension.

### 7.3 Share recents

Maintain recent share targets separately or derive them from recent chat activity.

Possible v1:

- Use current `dms` order and recent `channelMessages`/`last_message_id`.
- Store a small `[channelId]` recents list after each successful share.

---

## 8. UI/UX Details

### 8.1 Destination rows

DM row:

- Avatar.
- Username or group name.
- Small subtitle like "Direct Message" or member count for group DM.

Server row:

- Server icon/name.
- Expand/collapse indicator.

Channel row:

- `# channel-name`.
- Optional disabled state if upload/send is not allowed.

### 8.2 Search

Search should match:

- Usernames.
- Group names.
- Server names.

When search is active:

- Flatten results into destinations.
- For server channels, display context like `#general - Server Name`.

### 8.3 Attachments preview

Show:

- Image thumbnails.
- Video thumbnail + duration if available.
- Generic document icon + filename for files.
- Count and total size if multiple.

Keep preview practical; do not build a full composer clone inside the extension.

### 8.4 Sending state

After Send:

- Disable picker and caption field.
- Show per-file progress if available.
- Show current phase:
  - Preparing
  - Uploading
  - Sending
  - Sent
  - Failed

On failure:

- Retry uses the same selected destination and copied temp files.
- Cancel cleans temp files and dismisses.

---

## 9. Files and Targets to Touch

| Area | File/Target | Change |
|------|-------------|--------|
| Xcode target | New Share Extension target | Add iOS share extension with SwiftUI/custom UIKit host. |
| Entitlements | Main app + extension entitlements | Add App Group and Keychain Sharing access group. |
| Shared models | New shared Swift files, possibly under `Sources/` or a new shared group | `ShareRecipientIndex`, `ShareDestination`, `PendingSharePayload`, sender request/response models. |
| Main app state export | `Revolt/ViewState+Extensions/` new `ViewState+ShareIndex.swift` | Build and save compact recipient index after Ready and topology changes. |
| Ready event | `Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift` | Trigger debounced share index save after state is authoritative. |
| Auth cleanup | `Revolt/ViewState+Extensions/ViewState+Auth.swift` | Clear share index/temp payloads on sign-out/destroy cache. |
| Networking | Shared sender or `Revolt/Api` extraction | Reuse upload + send endpoint behavior without depending on `ViewState`. |
| Share UI | New extension files | Attachment preview, caption input, destination picker, progress/error state. |
| App routing fallback | `Revolt/RevoltApp.swift` or URL handling path | Handle `zeko.chat://share/<payloadId>` if extension hands off to app. |

---

## 10. Edge Cases and Risks

### 10.1 Stale recipient index

Issue: User leaves a server or loses channel permission, but extension still has cached row.

Mitigation:

- Include `generatedAt`.
- Refresh index whenever main app receives Ready/topology changes.
- Extension handles HTTP permission errors and tells user the destination is no longer available.

### 10.2 Missing session

Issue: User is signed out, token expired, or extension cannot read Keychain.

Mitigation:

- Extension shows logged-out state.
- Button: "Open ZekoChat".
- Do not show stale recipients without a valid session.

### 10.3 Large files and extension limits

Issue: Share extensions can be killed if they use too much memory/time.

Mitigation:

- Copy files to temp, stream/read only when uploading if possible.
- Validate sizes before thumbnail generation.
- For large videos/files, hand off to main app.

### 10.4 Multi-account leakage

Issue: Recipient list from previous account appears in extension.

Mitigation:

- Key every share index by `userId + baseURL`.
- Clear on sign-out and destroy cache.
- If extension sees token user/session mismatch with index metadata, refuse to load it.

### 10.5 Multiple attachments

Issue: Backend or UI may reject too many attachments.

Mitigation:

- Use the same max attachment count and size policy as the in-app composer.
- If current in-app limits are only enforced in `PendingAttachmentsManager`, extract constants to shared code.

### 10.6 Cache/update mismatch after sending

Issue: Extension sends successfully, but main app memory/cache is not updated until opened.

Mitigation:

- Accept this for v1; WebSocket/Ready/message load will reconcile.
- Optional later: extension writes a small "recent share sent" marker so main app can update recents or refresh target channel on foreground.

---

## 11. Implementation Checklist

1. Add Share Extension target and entitlements.
2. Configure App Group and Keychain Sharing for app + extension.
3. Create compact share recipient models.
4. Add main-app writer that exports recipient index after Ready.
5. Clear share index/temp files on sign-out and destroy cache.
6. Build extension attachment loader:
   - Read `NSExtensionItem`.
   - Copy files to App Group temp.
   - Validate type/count/size.
   - Generate previews.
7. Build extension recipient picker:
   - Recents.
   - DMs.
   - Group DMs.
   - Servers with text channels.
   - Search.
8. Build shared sender:
   - Read token/baseURL.
   - Upload attachments as `.attachment`.
   - Send message with `nonce`.
   - Report progress.
9. Add fallback handoff to main app for auth/stale/large-file cases.
10. Add cleanup for temp files after success, cancel, and extension expiration.
11. Add tests/manual test cases.

---

## 12. Test Scenarios

### 12.1 Happy path

1. Open Photos.
2. Select one photo.
3. Tap Share -> ZekoChat.
4. Search for a DM.
5. Select DM and send.
6. Open ZekoChat and confirm the photo appears in that DM.

### 12.2 Server channel

1. Share a file from Files.
2. Expand a server in the ZekoChat share extension.
3. Pick a text channel where upload is allowed.
4. Send.
5. Confirm message appears in the selected channel.

### 12.3 Permission denied

1. Try selecting a channel where upload is not allowed.
2. Row should be disabled before send if permission hint is known.
3. If server rejects anyway, extension should show a clear failure and not silently dismiss.

### 12.4 Signed out

1. Sign out of the app.
2. Try sharing from Photos.
3. Extension should not show previous account recipients.
4. Extension should offer opening the main app.

### 12.5 Large video

1. Share a large video from Photos.
2. Extension should either reject early with size messaging or hand off to the main app.
3. It should not crash or hang.

### 12.6 Multiple attachments

1. Select several images.
2. Share to a group DM.
3. Confirm count validation, preview, upload progress, and final sent message.

### 12.7 Stale server membership

1. Open app and generate index.
2. Leave a server from another device.
3. Before reopening main app, try sharing to that server channel.
4. Extension should handle send failure cleanly.
5. After main app receives Ready/update, extension index should no longer show that server.

---

## 13. Open Decisions

1. **Product name in extension:** Confirm whether share sheet label should be "ZekoChat", "Peptide", or another app display name.
2. **Direct send vs main-app handoff for v1:** Recommendation is direct send with handoff fallback.
3. **Friend contacts without active DMs:** Implemented by listing `Friend` users in the share index and resolving `/users/{user}/dm` before send.
4. **Max attachment policy:** Confirm current backend/app limits and extract them into shared constants.
5. **Icon/avatar cache:** Decide whether extension should show cached icons in v1 or use initials/placeholders first.

---

## 14. Summary Recommendation

Build this as a native iOS Share Extension with a compact cached recipient index written by the main app. The extension should send directly using a lightweight shared upload/send client, while falling back to opening the main app when auth is missing, the recipient index is stale, or attachments are too large.

This gives the user the Discord-like flow they expect: Share -> ZekoChat -> pick DM/server channel -> Send, while respecting iOS extension limits and avoiding full `ViewState` leakage into shared storage.

---

## 15. Fixes

### 15.1 ZekoChat not showing in Photos share sheet

**Symptom:** When sharing an image from the iOS Photos app, ZekoChat did not appear in the list of apps.

**Root cause:** The Share Extension target was configured with the same bundle identifier as the containing app:

- Containing app: `chat.zeko.app`
- Share extension before fix: same as containing app or a profile that did not match the chosen share extension App ID

iOS extensions are installed as separate bundles inside the containing app and must have their own bundle identifier, normally nested under the app bundle id. If the extension bundle id is the same as the app bundle id, iOS cannot register it as a separate share service, so Photos has no valid `com.apple.share-services` extension to display.

**Fix:** Changed the Share Extension bundle identifier in both Debug and Release build settings to:

```text
chat.zeko.app.share
```

This keeps the extension under the app bundle namespace while making it a distinct extension bundle that iOS can register for the share sheet.

**Second issue found during the same investigation:** The app's `Embed Foundation Extensions` copy phase was marked as post-processing-only:

```text
buildActionMask = 8
runOnlyForDeploymentPostprocessing = 1
```

That setting can prevent the extension appex from being embedded during normal development builds. Even if the extension target builds, the installed app may not contain the extension bundle, so iOS still has nothing to show in Photos.

**Fix:** Changed the embed phase to run during normal builds:

```text
buildActionMask = 2147483647
runOnlyForDeploymentPostprocessing = 0
```

**Related auth fix:** The shared keychain access group in code must match the active Apple Developer Team ID:

```text
3W4H6VC6AG.chat.zeko.app.shared
```

The current individual account signing team is:

```text
R8387T64JW
```

So the code now uses:

```text
R8387T64JW.chat.zeko.app.shared
```

This keychain mismatch would not stop ZekoChat from appearing in Photos, but it would make the extension unable to read the session token after opening, causing send/auth failures. The entitlements already use `$(AppIdentifierPrefix)chat.zeko.app.shared`, so the Swift constant now matches the active project team.

**Manual follow-up after this fix:**

1. Clean build and reinstall the app so iOS re-registers the extension.
2. If the old app is already installed, delete it from the device/simulator before reinstalling to clear stale extension registration.
3. In Photos -> Share, scroll the app row and tap `More` if ZekoChat is not immediately visible; iOS may place newly installed share extensions behind the More sheet the first time.
4. Make sure the Apple Developer capabilities/provisioning profile include the Share Extension bundle id `chat.zeko.app.share`, the Notification Service Extension bundle id `chat.zeko.app.notifications`, App Group `group.pepchat.shared.data`, and Keychain Sharing group `$(AppIdentifierPrefix)chat.zeko.app.shared`. If Xcode reports that an embedded binary’s bundle id is not prefixed with the parent app’s, see section 15.2.

### 15.2 "Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier"

**Symptom:** Xcode archive/validate or `embeddedBinaryBundleIdentifierNotPrefixed` style errors when building or uploading the app. The message refers to **any** embedded `.appex` (Share Extension, Notification Service Extension, widgets, etc.), not only the share target.

**Apple's rule:** Each embedded extension’s `PRODUCT_BUNDLE_IDENTIFIER` must be exactly the containing app’s bundle id **plus** a dot and a suffix. In other words, the extension id must start with the full host app bundle id as a string prefix, for example:

- Host app: `chat.zeko.app`
- Valid extension: `chat.zeko.app.share`
- Valid notification extension: `chat.zeko.app.notifications`
- Invalid extension example: `chat.zeko.share` because it does **not** begin with `chat.zeko.app.`

A Notification Service Extension is often added earlier with its own parallel id. That satisfies “unique bundle id” but fails the **prefix** rule if it does not start with the full containing app bundle id.

**Fix applied in this repo:** Keep embedded extension bundle identifiers nested under the main Revolt target (`chat.zeko.app`): `chat.zeko.app.share` for Share Extension and `chat.zeko.app.notifications` for Notification Service Extension.

**Manual follow-up:**

1. In [Apple Developer](https://developer.apple.com/account/resources/identifiers/list), register extension ids `chat.zeko.app.share` and `chat.zeko.app.notifications` if they do not exist yet, enable App Groups (and any other capabilities those extensions use), and regenerate provisioning profiles for the app and the extensions.
2. Remove old devices/simulator installs if validation cached the previous extension id.
3. Re-check **every** embedded target in Xcode (Build Settings → **Product Bundle Identifier**) the same way: each must start with the host app’s bundle id + `.`.

### 15.3 Attachment-only sends disabled and typed-caption sends dropping attachments

**Symptoms:**

- Sharing a photo/file from Photos or Files opened the ZekoChat share extension, but the user could not send the attachment by itself.
- If the user typed a caption/message and sent, only the typed text appeared in chat; the selected image/file did not appear as a message attachment.

**Root cause:** `ShareExtensionViewModel.loadAttachments()` processed each `NSItemProvider` by trying to load text/URL content first:

```swift
if let text = try? await loadText(from: provider), !text.isEmpty {
    caption = ...
    continue
}
```

That `continue` was the real problem. Some iOS share providers, especially Photos, can expose more than one representation for the same shared item: metadata/text/URL-style representations and file/image representations. Because the extension checked text first and skipped the rest of that provider, the actual image/file representation was never copied into the extension temp directory.

Downstream effects:

- `attachments` stayed empty.
- The send button behaved like there was no file selected, so the user had to type something to make the message valid.
- When the user typed a caption, `ShareAttachmentSender.send(...)` received an empty `files` array, so it posted only the caption.

**First attempted fix:** Changed provider ingestion to prefer shareable file representations before text:

1. If the provider has `UTType.image`, `UTType.movie`, or `UTType.fileURL`, load it as a file and append it to `attachments`.
2. Only treat the provider as text/URL when no file-like representation is available.
3. If the provider is data-only, fall back to `loadDataRepresentation` and write the data into the App Group temp directory as an attachment file.

This matches the product behavior we want:

- Photo/file only -> send as attachment with empty content.
- Photo/file + typed caption -> upload attachment, then send message with both `content` and `attachments`.
- URL/text-only share -> use text as the message body.

**Why the data fallback matters:** `loadFileRepresentation` is preferred because it avoids holding large files in memory, but Photos/File providers do not always vend a temporary file URL for every type. The fallback keeps the extension resilient for image providers that only vend `Data`.

**Validation:** Rebuilt the `ShareExtension` target successfully after the change.

**Retest result:** This was not sufficient. The send button still stayed disabled until text was typed, and captioned shares still delivered only text. That confirmed the extension was still ending with `attachments.isEmpty == true`.

**Second root cause:** The first fix still loaded files by asking `NSItemProvider` for broad/abstract UTTypes such as `public.image`:

```swift
provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier)
```

Photos often advertises concrete registered type identifiers such as `public.jpeg`, `public.heic`, or other provider-specific identifiers. A provider can say it conforms to `public.image`, but fail or return nothing when asked to load the abstract identifier itself. Because the extension swallowed those failures with `try?`, the UI simply had no attachments and the send button stayed disabled until text existed.

**Final fix:** `loadFile(from:)` now uses the provider's actual `registeredTypeIdentifiers` first:

1. Build a prioritized list of concrete registered types that conform to image, movie, audiovisual content, file URL, or data.
2. Try `loadFileRepresentation` for each concrete identifier.
3. Try `loadDataRepresentation` for each concrete identifier.
4. As a last resort for Photos images, call `loadObject(ofClass: UIImage.self)` and write a JPEG into the App Group temp directory.
5. Keep URL/text handling only for providers that are not file-like.

This makes the share sheet state depend on the actual Photos/File payload rather than optional text metadata. The expected behavior after this fix is:

- Image/file selected, no caption -> attachment preview appears and Send enables after destination selection.
- Image/file selected, caption typed -> same file uploads, then message posts with both `content` and `attachments`.
- Text/URL-only share -> Send still depends on the text body because there is no file payload.

**Validation after final fix:** Rebuilt the `ShareExtension` target successfully again.

### 15.4 Multi-image, multi-video, and Files PDF sharing

**Symptoms found during retest:**

- Sharing two images from Photos delivered only one image.
- Sharing more than two videos from Photos left Send disabled until text was typed.
- Sharing more than two videos was unreliable.
- Sharing a PDF from Files sent the file path as message text instead of uploading the PDF.
- General multi-file sharing was not reliable.

**Root cause:** The previous loader handled the common single-image path but still missed several provider shapes used by Photos and Files:

1. **Large videos may be in-place files.** Photos often exposes videos through `loadInPlaceFileRepresentation`, especially for larger or multiple selected videos. The extension only tried `loadFileRepresentation` and `loadDataRepresentation`, so some video providers failed to become attachments.
2. **Files PDFs may arrive as `public.url`.** Files can provide a PDF as a `file://` URL through a URL representation. The extension treated URL providers as message text, which is why the chat received a local file path string instead of an uploaded PDF.
3. **Type priority was too loose.** Some providers expose broad `public.data` plus richer concrete identifiers. Loading the wrong representation first can skip the real media/file path or create incomplete attachment handling.
4. **Movie activation limit was lower than the general file limit.** Images/files allowed up to 10 items, but movies were capped at 4. The extension should use the same 10-item batch limit for videos so multi-video sharing behaves consistently.

**Fix:** Expanded the file loader to treat every provider as a possible file before falling back to text:

1. `shareableTypeIdentifiers` now includes concrete types that conform to file URL, movie/audiovisual content, image, URL, or data.
2. Candidate types are prioritized: file URL -> movie/video -> image -> URL -> data.
3. For each candidate, the extension now tries:
   - `loadItem` for real `file://` URLs.
   - `loadFileRepresentation`.
   - `loadInPlaceFileRepresentation`.
   - `loadDataRepresentation`.
   - `UIImage` fallback for Photos image providers.
4. A `public.url` provider is only copied as an attachment when it resolves to a `file://` URL. Web URLs still become message text.
5. `NSExtensionActivationSupportsMovieWithMaxCount` was raised from `4` to `10` to match image/file batch sharing.

**Expected behavior after this fix:**

- Multiple Photos images should all appear as attachments and upload in one message.
- Three or more selected videos should populate attachments without requiring typed text.
- Files PDFs should upload as files, not send their local file path as content.
- Mixed multi-file selections should iterate every provider and append every successfully loaded attachment.

**Validation:** Rebuilt the `ShareExtension` target successfully after the loader and activation-rule changes.

### 15.5 Multi-contact destination selection

**Request:** The share extension originally allowed selecting only one destination. The desired behavior is selecting multiple contacts/channels and sending the same shared payload to them, capped at 3 destinations.

**Previous behavior:** The extension stored one selected destination:

```swift
@Published var selectedDestination: ShareDestination?
```

The send flow resolved one channel id and posted one message. This matched single-recipient sharing but did not support the Discord/WhatsApp-style multi-recipient workflow.

**Fix:** Replaced single selection with an ordered selected-destination array capped at 3:

```swift
@Published var selectedDestinations: [ShareDestination] = []
```

Selection now toggles a destination on/off. If the user tries to select a fourth destination, the extension keeps the first 3 selections and shows a clear error:

```text
You can share to up to 3 chats at once.
```

**Send approach:** The backend message API sends to one channel per request, so the extension sends sequentially:

1. Resolve each selected destination to a channel id. Friend contacts without an existing DM still use `/users/{user}/dm`.
2. Upload/send the same files and caption to destination 1.
3. Repeat for destination 2 and destination 3.
4. Only dismiss the extension after all selected destinations succeed.

Sequential sends are intentional for v1 because they keep error handling simple and avoid racing multiple upload/message requests from the constrained extension process. The progress bar is aggregated across selected destinations.

**UI behavior after this fix:**

- Rows use checkmarks for every selected destination.
- Recents/DM duplicate rows stay in sync because selected state is keyed by destination id.
- Footer shows selection count, for example `2/3 selected`.
- Send enables when at least one destination is selected and there is either an attachment or message text.

**Validation:** Rebuilt the `ShareExtension` target successfully after converting the picker to capped multi-select.

### 15.6 Error presentation moved from inline banner to alert

**Symptom:** Permission/send failures were rendered as a large inline warning box inside the share sheet. For example, a backend `403 MissingPermission` response appeared as raw JSON in the middle of the recipient picker:

```text
Request failed (403): {"type":"MissingPermission", ...}
```

This made the sheet feel broken and exposed backend/internal error details directly to the user.

**Fix:** Replaced inline error-banner rendering with SwiftUI alerts:

- `ShareExtensionViewModel` now publishes `alert: ShareExtensionAlert?`.
- `ShareExtensionRootView` presents `.alert(item: $viewModel.alert)`.
- Selection-limit, missing-session, stale-recipient-index, attachment-read, and send failures all route through `presentAlert(...)`.
- Permission-looking failures are normalized to a user-facing alert:

```text
Missing Permission
You do not have permission to send messages or upload files in one of the selected chats.
```

**Why this approach:** Share extensions are compact, modal surfaces. Errors should interrupt the current action clearly without permanently taking space in the picker. Alerts also avoid showing raw server JSON while still letting the user dismiss and choose another destination.

**Share sheet UI location:** The share sheet is designed in:

```text
ShareExtension/ShareViewController.swift
```

Key UI types in that file:

- `ShareViewController`: hosts the SwiftUI sheet inside the iOS extension.
- `ShareExtensionRootView`: overall header, attachments, caption field, search, destination list, footer/send button.
- `DestinationSection`: reusable DM/group/recent section.
- `DestinationRow`: selectable destination row with icon/checkmark.
- `ShareColors`: local color palette for the share sheet.

**Validation:** Rebuilt the `ShareExtension` target successfully after replacing inline errors with alerts.
