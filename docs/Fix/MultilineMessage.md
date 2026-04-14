# Multiline Message Rendering Fix

## Issue

When sending a multiline message in a channel, the last part of the message could appear visually cut in the immediate post-send state. After leaving and re-entering the channel, the same message rendered fully.

## Runtime Debugging Summary

- Added targeted runtime instrumentation around:
  - optimistic message insertion,
  - table row height lookup/store,
  - local data source cache reads,
  - post-send scroll/keyboard state.
- Reproduced the issue and reviewed runtime logs to isolate behavior under real UI timing conditions.
- Verified that message content persisted correctly and the visual state stabilized after the table view/layout cycle completed.

## Code Changes Made

- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableView.swift`
  - Temporarily instrumented `heightForRowAt` and `willDisplay` to trace:
    - cached row heights (`cellHeightCache` hits/misses),
    - stored row heights at display time,
    - last-row visibility snapshots while keyboard was open.
  - Instrumentation was removed after validation.
- `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift`
  - Temporarily instrumented `handleNewMessageSent()` to trace immediate and delayed post-send scroll/layout state.
  - Temporarily instrumented nested `LocalMessagesDataSource.cellForRowAt` to trace message-cache vs viewState reads.
  - Instrumentation was removed after validation.
- `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift`
  - Temporarily instrumented `sendMessage` at optimistic insert point (nonce, line count, content length).
  - Instrumentation was removed after validation.
- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
  - Temporarily instrumented `configure` for text layout snapshots (`contentSize`, bounds, line count).
  - Instrumentation was removed after validation.
- `docs/Fix/MultilineMessage.md`
  - Added this incident log and implementation notes.

## Exact Code (Current)

### 1) Optimistic message insert on send

```swift
// MessageInputHandler.swift
viewModel.viewState.channelMessages[viewModel.channel.id]?.append(messageNonce)
viewModel.viewState.messages[messageNonce] = queuedMessage.toTemporaryMessage()
viewModel.viewState.clearDraft(channelId: viewModel.channel.id)
viewController.handleNewMessageSent()
```

### 2) Post-send scroll and layout coordination

```swift
// MessageableChannelViewController.swift
func handleNewMessageSent() {
    clearTargetMessageProtection(reason: "user sent new message")
    lastManualScrollUpTime = nil

    self.view.layoutIfNeeded()
    self.tableView.layoutIfNeeded()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.view.layoutIfNeeded()
        self.tableView.layoutIfNeeded()

        if self.isKeyboardVisible && !self.localMessages.isEmpty {
            let lastIndex = self.localMessages.count - 1
            if lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) {
                let indexPath = IndexPath(row: lastIndex, section: 0)
                self.safeScrollToRow(at: indexPath, at: .bottom, animated: false, reason: "new message sent - first scroll")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.safeScrollToRow(at: indexPath, at: .bottom, animated: true, reason: "new message sent - second scroll")
                }
            }
        } else {
            self.scrollToBottom(animated: true)
        }
    }
}
```

### 3) Row-height caching path used by message table

```swift
// MessageableChannelViewController+TableView.swift
let key = CellHeightCacheKey(
    messageId: messageId,
    isContinuation: isContinuation,
    tableWidth: Int(tableView.bounds.width)
)
cellHeightCache.store(height: currentCell.bounds.height, for: key)
...
return cellHeightCache.height(for: key) ?? UITableView.automaticDimension
```

## Final Resolution

- Confirmed as fixed after runtime verification on-device.
- Removed all temporary debug instrumentation once the user confirmed the issue no longer reproduced.

## Regression After Merge (Apr 2026)

### Why it came back

- The post-send scroll/layout fix (`handleNewMessageSent`) was still present.
- A later performance optimization in row-height caching limited the "second layout pass" to only complex cells (embeds/attachments).
- Plain multiline text cells could still be measured one pass too early, and that short height was cached, so the message looked clipped until a later full layout cycle (e.g., leave/re-enter channel).

### What was changed now

- Expanded second-pass measurement in `willDisplay` to include multiline text cells.
- Invalidated height cache for the just-sent message ID before post-send scroll.
- Added a lightweight `beginUpdates/endUpdates` reconciliation in delayed post-send block so UIKit re-queries final height before final scroll.

### Exact Code (Current, Regression Fix)

#### 1) Height stabilization for multiline text in row display pass

```swift
// MessageableChannelViewController+TableView.swift
let textLineHeight = currentCell.textViewContent.font?.lineHeight ?? 0
let textContentHeight = currentCell.textViewContent.contentSize.height
let isLikelyMultilineText = textLineHeight > 0 && textContentHeight > (textLineHeight * 1.5)
let hasComplexContent =
    (currentCell.imageAttachmentsContainer != nil && !currentCell.imageAttachmentsContainer!.isHidden) ||
    (currentCell.fileAttachmentsContainer != nil && !currentCell.fileAttachmentsContainer!.isHidden) ||
    currentCell.contentView.viewWithTag(2000) != nil

if hasComplexContent || isLikelyMultilineText {
    let firstHeight = finalHeight
    currentCell.contentView.setNeedsLayout()
    currentCell.contentView.layoutIfNeeded()
    finalHeight = currentCell.bounds.height

    if abs(finalHeight - firstHeight) > 1.0 {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.beginUpdates()
            self?.tableView.endUpdates()
        }
    }
}
```

#### 2) Post-send cache invalidation + height reconciliation

```swift
// MessageableChannelViewController.swift
if let lastMessageId = localMessages.last {
    cellHeightCache.invalidate(messageId: lastMessageId)
    continuationCache.removeValue(forKey: lastMessageId)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    self.view.layoutIfNeeded()
    self.tableView.layoutIfNeeded()
    self.tableView.beginUpdates()
    self.tableView.endUpdates()
    // existing scroll logic continues...
}
```

## Notes

- This document records the multiline rendering incident and its debug/verification workflow.
- Keep row-height caching and post-send scroll interactions under observation when changing message cell layout behavior in the future.

## Final Runtime-Proven Fix (Apr 2026)

### Root Cause (final)

- The issue was not only row-height caching. A race also existed where `UITextView` in a reused message cell could keep a stale one-line visible frame (`~18pt`) even when:
  - content was long soft-wrap text (no explicit `\n`),
  - cell height had already been corrected upward.
- This produced clipped text inside the cell.
- The cache then amplified the issue if height was stored before final text-frame enforcement.

### Runtime evidence that confirmed root cause

- Problematic rows repeatedly showed:
  - large `fitsH` (expected multiline height),
  - `labelFrameH` stuck near one line,
  - `isPotentiallyClipped=true`.
- After enforcing text height and storing cache at the end of `willDisplay`, logs showed:
  - `labelFrameH ~= fitsH`,
  - `isPotentiallyClipped=false`,
  - stored cache height matching final rendered state.

### What we kept in code (current behavior)

1) **Soft-wrap row-height correction in `willDisplay`**

- For long text without explicit newlines, compute `sizeThatFits` and adjust row height when `contentSize` is lagging.

2) **Text-view visible-height enforcement for stale one-line frames**

- In `MessageCell`, enforce minimum visible text height using fitted height when the label frame is clearly smaller than required.
- This is done via `enforceVisibleTextHeightIfNeeded()`.

3) **Critical ordering fix: cache after enforcement**

- Store `cellHeightCache` only after soft-wrap/text-frame enforcement logic runs.
- This prevents stale pre-enforcement heights from being reused.

4) **Keep immediate relayout trigger when enforcement updates**

- If text-frame enforcement changes layout, trigger a lightweight `beginUpdates/endUpdates` to reconcile table sizing.

### Exact code (current, simplified)

```swift
// MessageableChannelViewController+TableView.swift (inside willDisplay)
let textContentHeight = currentCell.textViewContent.contentSize.height
let textWidth = max(1, currentCell.textViewContent.bounds.width)
let fittedTextHeight = currentCell.textViewContent.sizeThatFits(
    CGSize(width: textWidth, height: .greatestFiniteMagnitude)
).height

if isSoftWrapCandidate && (fittedTextHeight - textContentHeight) > 8 {
    let chromeHeight = max(0, finalHeight - textContentHeight)
    finalHeight = max(finalHeight, fittedTextHeight + chromeHeight)
}

let visibleDelta = fittedTextHeight - currentCell.textViewContent.frame.height
if isSoftWrapCandidate && visibleDelta > 6 {
    let enforceResult = currentCell.enforceVisibleTextHeightIfNeeded()
    if enforceResult.updated {
        finalHeight = max(finalHeight, currentCell.bounds.height)
        DispatchQueue.main.async { [weak self] in
            self?.tableView.beginUpdates()
            self?.tableView.endUpdates()
        }
    }
}

// Important: cache write happens at the very end, after enforcement.
cellHeightCache.store(height: finalHeight, for: key)
```

```swift
// MessageCell.swift
internal func enforceVisibleTextHeightIfNeeded() -> (old: CGFloat, fitted: CGFloat, after: CGFloat, updated: Bool) {
    let width = max(1, contentLabel.bounds.width)
    let fitted = contentLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    let old = contentLabel.bounds.height

    if fitted - old > 6 {
        contentLabelMinHeightConstraint?.constant = ceil(fitted)
        contentLabel.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        contentLabel.isScrollEnabled = true
        contentLabel.isScrollEnabled = false
        contentLabel.setNeedsLayout()
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        return (old, fitted, contentLabel.bounds.height, true)
    }

    return (old, fitted, old, false)
}
```

### Practical guidance if this regresses again

- Re-check these three values on the failing row:
  - `contentLabel.frame.height`,
  - `contentLabel.contentSize.height`,
  - `contentLabel.sizeThatFits(...).height`.
- If frame is small while fitted is large, the issue is text-frame staleness, not payload corruption.
- Verify cache write still occurs after enforcement.
