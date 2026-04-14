# Message Reaction Cache vs Live Reconcile Fix

## Summary

This document captures an intermittent reaction rendering bug that occurred when a chat opened from cached messages and then reconciled with live server/websocket state.

The issue did not happen during normal live chatting. It appeared during cache -> live transition after re-entering a chat.

## Issues Observed

### Scenario 1: Reaction removed on another device while chat is closed

- Steps:
  - Message + reaction are already cached on main device.
  - User leaves chat.
  - On another device, reaction is removed.
  - User re-opens same chat on main device.
- Behavior:
  - Cached reaction is shown briefly.
  - UI updates and reaction is removed.
  - A blank space remains below/around that message row until user navigates back and opens again.

### Scenario 2: Reaction added on another device while chat is closed

- Steps:
  - Message is cached on main device without new reaction state.
  - User leaves chat.
  - On another device, reaction is added.
  - User re-opens same chat on main device.
- Behavior:
  - Cached message loads first.
  - Reconcile adds reaction, but row can appear clipped/misaligned.
  - After leaving and reopening again (with fresh cache), it renders correctly.

## Expected Behavior

- During cache -> live reconciliation:
  - reaction changes should update without clipping or blank spacing;
  - message row heights should re-measure correctly when reaction area changes;
  - no extra navigation should be required for proper layout.

## Root Cause (Runtime-Proven)

The core issue was stale/undersized table row heights being reused while reaction layout changed during reconciliation.

Runtime evidence (Xcode console) consistently showed Auto Layout conflicts such as:

- `UIView-Encapsulated-Layout-Height == 44` or other short heights on message cells
- reaction view constrained to bottom with fixed height
- text/reaction vertical chain requiring more space than cached row height

This created:

- clipped reaction rows when reactions appeared
- leftover vertical gaps when reactions disappeared

Additionally, cache/live reconcile often had same message IDs but changed content (reactions), so an ID-based fast path could skip the full geometry recalculation needed for updated row heights.

## Fixes Implemented

## Fix A: Persist reaction updates to cache during websocket events

Files:
- `Revolt/1Storage/MessageCacheWriter.swift`
- `Revolt/1Storage/MessageCacheManager.swift`
- `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`

What changed:

- Added cache writer API:
  - `enqueueUpdateMessageReactions(id:reactions:channelId:userId:baseURL:)`
- Added cache manager APIs:
  - `updateCachedMessageReactions(...)`
  - `_updateCachedMessageReactions(...)`
- Wired both websocket events to persist reactions:
  - `.message_react`
  - `.message_unreact`

Why:

- Prevent stale reaction flash from disk cache when reopening chat.

## Fix B: Make reaction/no-reaction constraint transitions deterministic in `MessageCell`

Files:
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Reactions.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift`

What changed:

- Always clear reaction constraints before deciding has/no reactions.
- Ensure content bottom constraints are cleared when reactions become bottom-most.
- Remove any conflicting `contentLabel.bottom -> contentView.bottom` constraints in reaction path.
- Track and reset min-height/bottom constraints safely on reuse/configure.

Why:

- Prevent blank space and clipping when state flips between reaction/no-reaction.

## Fix C (Final runtime-proven fix): Invalidate row-height cache during cache->API reconcile when content changed

File:
- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`

What changed:

- Added reaction signature diffing between pre-API and post-API message states for same message IDs.
- In reconcile flow:
  - when IDs are unchanged but reaction content changed:
    - invalidate `cellHeightCache`
    - clear `continuationCache`
    - `reloadData()`
    - run non-animated `beginUpdates()/endUpdates()` for fresh sizing
  - before full reconcile reload:
    - invalidate `cellHeightCache`
    - clear `continuationCache`
    - force non-animated update pass after reload

Why:

- Fix stale `UITableView` row height reuse during cache->live content changes.
- This was the change that resolved the remaining intermittent spacing/clipping issue.

## Why this fix set is correct

- Cache persistence (Fix A) prevents stale reaction state on reopen.
- Cell-level constraint hygiene (Fix B) stabilizes reaction/no-reaction layout transitions.
- Reconcile-time row-height invalidation (Fix C) ensures table geometry is recalculated when same IDs carry changed reaction content.

Together these cover both reported scenarios:

- reaction removed from another device while chat is closed
- reaction added from another device while chat is closed

## Files Changed

- `Revolt/1Storage/MessageCacheWriter.swift`
- `Revolt/1Storage/MessageCacheManager.swift`
- `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Reactions.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift`
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift`

## Manual Regression Checklist

1. Open chat with cached messages; remove a reaction from another device; reopen chat.
2. Verify reaction removal does not leave blank spacing.
3. Open chat with cached messages; add a reaction from another device; reopen chat.
4. Verify reaction appears without clipping/misalignment.
5. Repeat by navigating back and reopening multiple times.
6. Verify behavior remains correct on real iPhone device.

