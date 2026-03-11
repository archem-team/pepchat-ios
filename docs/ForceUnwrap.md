# Force Unwrap Audit

This document catalogs force unwraps (`!`), force casts (`as!`), and `try!` in the codebase. Force unwraps crash the app when the value is `nil`. Items are organized by crash risk and by location (following `AGENTS.md` project structure).

---

## Risk Levels

| Level | Description |
|-------|-------------|
| **High** | Runtime/user/network data; nil likely under edge conditions |
| **Medium** | Init, file load, or data that *should* exist but could fail |
| **Low** | Bundle resources, preview-only code, or tightly controlled paths |
| **IUO** | Implicitly unwrapped optional (declaration); can crash if used before assignment |

---

## High Risk — Likely to Crash in Production

### Notification Service Extension  
`notificationservice/NotificationService.swift`

| Line | Code | Risk |
|------|------|------|
| 49 | `info["authorAvatar"] as! String` + `URL(string: ...)!` | Push payload may omit `authorAvatar` or contain invalid URL |
| 82 | `[displayedAttachment!]` | `displayedAttachment` may be nil |

---

### App Delegate  
`Revolt/Delegates/AppDelegate.swift`

| Line | Code | Risk |
|------|------|------|
| 387 | `response as! UNTextInputNotificationResponse` | Response type may differ for other notification actions |

---

### ViewState (Core State)  
`Revolt/ViewState.swift`

| Line | Code | Risk |
|------|------|------|
| 941 | `this.currentUser!` | Current user may be nil before login completes |
| 1011 | `this.channels["2"]!`, `this.channels["3"]!` | System DM channels may not exist |
| 1041 | `notificationsGranted!` | May be nil |
| 1053–1065 | `apiInfo!.features.autumn.url` (multiple) | `apiInfo` may be nil before API info loaded |
| 1096 | `apiInfo!.ws` | Same as above |
| 1800 | `try! await http.joinServer(...).get()` | Network/join can fail |
| 2048 | `URL(string: "...")!` | URL construction could fail |
| 2310 | `serverIdForChannel!` | Channel may not have server |
| 2400 | `return value!` | Generic unwrap in utility |

---

### ViewState Extensions

**`Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`**

| Line | Code | Risk |
|------|------|------|
| 153 | `unreads[m.channel]!.mentions = ...` | Unread entry may not exist for channel |

**`Revolt/ViewState+Extensions/ViewState+Unreads.swift`**

| Line | Code | Risk |
|------|------|------|
| 124, 127 | `unread.mentions!.count` | `mentions` may be nil |
| 239–240, 321–322 | `serverIdForChannel!` | Channel may not have server ID |

**`Revolt/ViewState+Extensions/ViewState+UsersAndDms.swift`**

| Line | Code | Risk |
|------|------|------|
| 474–475 | `sortedBatches.first!`, `sortedBatches.last!` | Empty array would crash |

**`Revolt/ViewState+Extensions/ViewState+Auth.swift`**

| Line | Code | Risk |
|------|------|------|
| 60 | `response.response!.statusCode` | `response` may be nil |

---

### User Settings Store  
`Revolt/Api/UserSettingsStore.swift`

| Line | Code | Risk |
|------|------|------|
| 244, 254, 427, 587, 622, 642 | `Bundle.main.bundleIdentifier!` | Bundle ID should exist but could theoretically be nil |
| 309, 325, 434, 629, 680, 687 | `UserSettingsData.cacheFile!`, `storeFile!` | Static file path may not be set |
| 317, 333 | `fileContents!`, `storefileContents!` | File read could fail |
| 341, 343 | `cache!`, `store!` | Decode could fail |
| 372 | `viewState!` | ViewState reference may be nil |

---

### HTTP Client  
`Revolt/Api/Http.swift`

| Line | Code | Risk |
|------|------|------|
| 102, 403 | `token!` | Session token may be nil |
| 358 | `URLComponents(string: "...")!` | URL format could be invalid |
| 445, 459 | `apiInfo!.features.autumn.url` | API info may not be loaded |

---

### Websocket  
`Revolt/Api/Websocket.swift`

| Line | Code | Risk |
|------|------|------|
| 644 | `try! WebSocketStream.sharedEncoder.encode(payload)` | Encode can throw |

---

### Message Channel & Related

**`Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`**

| Line | Code | Risk |
|------|------|------|
| 1845 | `try await group.next()!` | Task group may return nil |

**`Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TargetMessage.swift`**

| Line | Code | Risk |
|------|------|------|
| 332 | `viewState.messages[targetId]!` | Message may not be loaded yet (relates to Sentry NSRangeException) |
| 653 | `try await group.next()!` | Same as above |

**`Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelSearch.swift`**

| Line | Code | Risk |
|------|------|------|
| 231 | `URL(string: messageLink)!` | User-provided link could be invalid |

---

### Message Cell & Attachments  
`Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`

| Line | Code | Risk |
|------|------|------|
| 437, 458, 492, 499 | `Range(match.range, in: result)!` | Regex match range may not map to string |
| 1906–1917 | `imageAttachmentsContainer!`, `fileAttachmentsContainer!` | Containers may be nil before setup |

**`Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Attachments.swift`**

| Line | Code | Risk |
|------|------|------|
| 42–43, 53, 69, 97, 111, 124–126, 158, 182–183, 187, 253 | `imageAttachmentsContainer!` | Same as above |
| 278–279, 293, 298, 310, 312, 319–321, 397, 401–403, 414, 420 | `fileAttachmentsContainer!` | Same as above |

---

### Message Contents & Links  
`Revolt/Components/MessageRenderer/MessageContentsView.swift`

| Line | Code | Risk |
|------|------|------|
| 131, 134 | `viewState.currentUser!` | User may not be logged in |
| 468, 585, 587 | `URL(string: ...)!` | Link could be malformed |

---

### MessageBox  
`Revolt/Components/MessageBox.swift`

| Line | Code | Risk |
|------|------|------|
| 42 | `viewState.users[reply.message.author]!` | User may not be loaded |
| 265, 268, 271 | `viewState.users[$0]!`, `viewState.members[server!.id]!.values` | Same; server may be nil |
| 976–977 | `viewState.channels["0"]!`, `viewState.servers["0"]!` | IDs may not exist |

---

### System Message View  
`Revolt/Components/MessageRenderer/SystemMessageView.swift`

| Line | Code | Risk |
|------|------|------|
| 23, 50, 76, 101, 131, 160–161, 194–195, 227–228 | `viewState.users[content.by]!`, etc. | User IDs from system messages may not be in `viewState.users` |
| 409–410 | `viewState.users["0"]!` | User "0" may not exist |

---

### Channel Info & Server Data  
`Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelInfo.swift`

| Line | Code | Risk |
|------|------|------|
| 238, 252 | `viewState.servers[channel.server!]!` | Server/channel may be nil |
| 255 | `server.roles![a]!.rank` | Role may not exist |
| 295, 298 | `viewState.users[$0]!` | User may not be loaded |
| 347, 761, 886, 1022 | Various dict lookups | Same pattern |

**`Revolt/Pages/Channel/Messagable/ChannelInfo/AddMembersToChannelView.swift`**

| Line | Code | Risk |
|------|------|------|
| 62, 65, 68 | `viewState.users[$0]!`, `viewState.members[channel.server!]!` | Same as above |

---

### Message Reactions  
`Revolt/Components/MessageRenderer/MessageReactionsSheet.swift`

| Line | Code | Risk |
|------|------|------|
| 56, 69 | `message.reactions![emoji]!`, `message.reactions![selection]!` | Reaction/emoji may not exist |

---

### User Sheet  
`Revolt/Components/Sheets/UserSheet.swift`

| Line | Code | Risk |
|------|------|------|
| 544 | `server.roles![roleId]!` | Role may not exist |

---

### Friends List  
`Revolt/Pages/Home/FriendsList.swift`

| Line | Code | Risk |
|------|------|------|
| 384, 401, 418 | `viewState.users[user.id]!.relationship = ...` | User may have been removed from cache |

---

### Discover  
`Revolt/Components/Home/Discover/DiscoverScrollView.swift`

| Line | Code | Risk |
|------|------|------|
| 323 | `membershipCache[cachedServerId!]` | `cachedServerId` may be nil |

---

### API Responses  
`Revolt/Api/Responses.swift`

| Line | Code | Risk |
|------|------|------|
| 209–210 | `list[0].value as! A`, `list[1].value as! B` | Response structure could change |

---

### Settings (Error Handling)

**`Revolt/Pages/Settings/UserSettings.swift`**

| Line | Code | Risk |
|------|------|------|
| 236 | `error as! RevoltError` | Error could be a different type |

**`Revolt/Pages/Settings/RecoveryCodesView.swift`**

| Line | Code | Risk |
|------|------|------|
| 32 | `error as! RevoltError` | Same as above |

**`Revolt/Pages/Settings/NotificationSettings.swift`**

| Line | Code | Risk |
|------|------|------|
| 37 | `error as! RevoltError` | Same as above |

---

### Server Emoji Upload  
`Revolt/Pages/Channel/Settings/Server/ServerEmoji/ServerEmojiSettings.swift`

| Line | Code | Risk |
|------|------|------|
| 125–126 | `selectedImage!.pngData()!`, `try! ... uploadFile(...).get()`, `try! ... uploadEmoji(...).get()` | Image/data or network can fail |

---

### Sessions Settings  
`Revolt/Pages/Settings/SessionsSettings.swift`

| Line | Code | Risk |
|------|------|------|
| 35, 42 | `try! await viewState.http.deleteSession(...).get()` | Network can fail |

---

### Role Settings  
`Revolt/Pages/Channel/Settings/Server/ServerRoles/RoleSettings.swift`

| Line | Code | Risk |
|------|------|------|
| 298 | `try! await viewState.http.setRolePermissions(...).get()` | Network can fail |

---

## Medium Risk — Init, File Load, or Controlled Paths

### ViewState Init  
`Revolt/ViewState.swift`

| Line | Code | Risk |
|------|------|------|
| 38, 51 | `try! JSONEncoder().encode(...)` | Encode should not fail for simple types |
| 2101–2104 | `Bundle.main.url(...)!`, `try! Data(contentsOf:)`, `try! JSONDecoder().decode(...)` | Emoji JSON must exist in bundle |

---

### UserSettingsStore Init  
`Revolt/Api/UserSettingsStore.swift`  
- Multiple `try!` and file path unwraps during init; failure prevents app from starting.

---

### Emoji Picker  
`Revolt/Components/EmojiPicker.swift`

| Line | Code | Risk |
|------|------|------|
| 84, 86 | `try! Data(contentsOf: file)`, `try! JSONDecoder().decode(...)` | Emoji data file must exist |
| 93, 109 | `viewState.servers[id.id]!`, `emojis[parent]!.append(...)` | Server/parent may not exist |

---

### MessageBox  
`Revolt/Components/MessageBox.swift`

| Line | Code | Risk |
|------|------|------|
| 215 | `try! NSRegularExpression(pattern: "...")` | Regex pattern is static; unlikely to fail |

---

### Markdown Processor  
`Revolt/Pages/Channel/Messagable/Utils/MarkdownProcessor.swift`

| Line | Code | Risk |
|------|------|------|
| 157 | `...mutableCopy() as! NSMutableAttributedString` | Copy type assumed |

---

### Contents (Attributed String)  
`Revolt/Components/Contents.swift`

| Line | Code | Risk |
|------|------|------|
| 1624, 1709, 1754, 1832, 1880, 1928, 1972 | `(currentAttrs[.font] ?? contentFont) as! UIFont` | Font attribute may not be UIFont |
| 1367, 1613 | `viewState.members[$0.id]![user.id]` | Member lookup |

---

## Low Risk — Previews, Bundle, Known IDs

### SwiftUI Previews

Many `#Preview` blocks use `viewState.channels["0"]!`, `viewState.servers["0"]!`, `viewState.users["0"]!`, etc. These only run in Xcode previews with mock data. Low risk if preview data is set up correctly.

**Files:** `ChannelIcon.swift`, `ChannelSearch.swift`, `MessageView.swift`, `MessageableChannel.swift`, `UserSheet.swift`, `ServerIcon.swift`, `BlockUserPopup.swift`, `RemoveFriendShipPopup.swift`, `StatusPreviewSheet.swift`, `ServerInfoSheet.swift`, `DeleteServerSheet.swift`, `DeleteDmGroupSheet.swift`, `DeleteGrouSheet.swift`, `MutualConnectionsSheet.swift`, `ChannelPermissionsSettings.swift`, `ChannelOverviewSettings.swift`, `ServerChannelOverviewSettings.swift`, `ServerCategorySheet.swift`, `ChannelCategoryCreateView.swift`, `ChannelInfo.swift`, `ChannelInfoMoreSheet.swift`, `ServerChannelsView.swift`, `DeleteChannelSheet.swift`, `ChannelUserOptionSheet.swift`, `DeleteCategorySheet.swift`, `RoleSettings.swift`, `ServerMembersView.swift`, `CreateServerRoleView.swift`, `ServerCategoryView.swift`, `ServerSettings.swift`, `AddMembersToChannelView.swift`, `ServerInvitesView.swift`, `IdentitySheet.swift`, `ChannelMemberPermissionView.swift`, `ServerRolesSettings.swift`, `SystemMessageSheet.swift`, `DefaultRoleSettings.swift`, `ChannelOptionsSheet.swift`, `NotificationSettingSheet.swift`, `ServerEmojiSettings.swift`, `FriendOptionsSheet.swift`, `FriendRequestCard.swift`, `IncomingFriendRequestsSheet.swift`, `ReportView.swift`, `ServerBannedUsersView.swift`

### RevoltApp  
`Revolt/RevoltApp.swift`

| Line | Code | Risk |
|------|------|------|
| 606 | `Binding($viewState.servers[serverId])!` | Server may not exist for given ID |

### Presence Indicator  
`Revolt/Components/PresenceIndicator.swift`

| Line | Code | Risk |
|------|------|------|
| 32 | `colours[presence]!` | Presence enum should always have a colour; low risk if exhaustive |

### Audio Player  
`Revolt/Components/AudioPlayer/AudioPlayerManager.swift`

| Line | Code | Risk |
|------|------|------|
| 960 | `durationCache[$0]!` | Cache should contain entry if key exists; race possible |

### User Settings Regex  
`Revolt/Pages/Settings/UserSettings.swift`

| Line | Code | Risk |
|------|------|------|
| 522 | `try! /.../.wholeMatch(in: email)` | Regex parse; email format assumed valid |

---

## Implicitly Unwrapped Optionals (IUOs)

These are declared with `!` and crash if used before assignment. Highest risk when set in `viewDidLoad`/`loadView` but used earlier.

### MessageableChannelViewController  
`Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`

- `tableView: UITableView!`
- `dataSource: UITableViewDataSource!`
- `headerView: UIView!`
- `backButton: UIButton!`, `channelNameLabel: UILabel!`, `channelIconView: UIImageView!`, `searchButton: UIButton!`
- `messageInputView: MessageInputView!`
- `messageInputBottomConstraint: NSLayoutConstraint!`
- `newMessageButton: UIButton!`

### MessageInputView  
`Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`

- `normalTextViewTopConstraint`, `editingTextViewTopConstraint`, `replyTextViewTopConstraint`, `attachmentTextViewTopConstraint`, `textViewHeightConstraint` (all `NSLayoutConstraint!`)

### Setup Extension  
`Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Setup.swift`

- Line 302: `messageInputBottomConstraint!` — used when setting up constraints

---

## Relation to Sentry Reports

1. **NSRangeException (Report 1)** — `ScrollPositionManager` and `MessageableChannelViewController` scroll logic run after teardown. Combined with dictionary force unwraps (e.g. `messages[targetId]!` in TargetMessage), missing data can contribute to invalid state.

2. **EXC_BREAKPOINT (Report 2)** — Often caused by force unwrap of `nil`. High-risk areas above (especially `viewState.users`, `viewState.channels`, `viewState.messages`, and gesture/keyboard-related code) are the best candidates to replace with optional binding or `guard let`.

---

## Mitigation Priorities

1. Replace `viewState.users[id]!`, `viewState.channels[id]!`, `viewState.messages[id]!` with optional binding or early return.
2. Add nil checks before scroll operations in `MessageableChannelViewController` and `ScrollPositionManager`.
3. Replace `as! RevoltError` with `as? RevoltError` and handle non-Revolt errors.
4. Use `guard let` for `apiInfo`, `currentUser`, and `token` in hot paths.
5. Use `URL(string:) ?? fallback` or validate before force unwrapping URLs.
6. Replace `try!` with `do { try ... } catch` where failure is possible (network, file I/O).
