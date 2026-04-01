# Link Preview Image Overlap Fix

## Original issue

When a user sent or viewed a message containing a **link preview** (rich embed with site icon, title, description, and image), the link preview card—especially its **large image**—would sometimes **overlap** other content:

1. **Overlap with the previous message:** The link preview image could draw on top of the message above it in the chat, as if it were in a higher z-order or not constrained to its cell.
2. **Overlap within the same message:** When opening a channel, for a **split second** during initial render, the link preview could overlap the same message’s header (avatar, username, timestamp) and message text, then snap into place.

Visually, it looked like the embed was “loaded in a ZStack” or with a wrong z-index: the preview card or its image extended outside its message cell and covered adjacent or same-cell content.

---

## Earlier behaviour

- **Before the fix:**
  - The table view uses `UITableView.automaticDimension` and `estimatedRowHeight = 80`. Cells with link previews are much taller.
  - The cell’s `contentView` did **not** clip subviews (`clipsToBounds` was false by default). When the embed’s image loaded asynchronously (e.g. via Kingfisher) or when layout hadn’t run yet, the embed could draw outside the cell bounds.
  - Layout sometimes completed **after** the first frame was drawn. So for one frame the embed container could have a wrong or zero frame, or the row height could be wrong, causing the preview to overlap the message above or the same cell’s header/text.
  - The embed container was added last to the cell’s `contentView`, so it was drawn on top. If its frame was wrong, it would cover the same cell’s content (name, timestamp, body).

---

## What was updated

### 1. Clipping so content stays inside bounds

- **MessageCell (`MessageCell.swift`)**  
  - Set `contentView.clipsToBounds = true` in `init(style:reuseIdentifier:)` after setting `contentView.layoutMargins`.  
  - Ensures nothing inside the cell (including the link preview) can draw outside the cell’s content rect, so it cannot overlap the previous row.

- **LinkPreviewView (`LinkPreviewView.swift`)**  
  - Set `clipsToBounds = true` on the root view in `setupUI()` (after `backgroundColor = .clear`).  
  - Keeps the embed card and its image inside the link preview view even during async image load.

- **Embed container (`MessageCell+Attachments.swift`)**  
  - Set `embedContainer.clipsToBounds = true` in `loadEmbeds(embeds:viewState:)` when creating the embed stack view (after setting `tag = 2000`).  
  - Ensures the stack of embeds is clipped and never overflows.

### 2. Layout and z-order to prevent the “split second” overlap

- **Force layout before first draw (`MessageableChannelViewController+TableView.swift`)**  
  - In `tableView(_:willDisplay:forRowAt:)`, for `MessageCell`, call `currentCell.contentView.setNeedsLayout()` and `currentCell.contentView.layoutIfNeeded()` after adjusting layout margins.  
  - Ensures the cell (and the embed) have their final frames **before** the cell is first drawn, so the brief overlap when opening the channel is avoided.

- **Layout and z-order in `loadEmbeds` (`MessageCell+Attachments.swift`)**  
  - After activating the embed container constraints:  
    - Call `contentView.setNeedsLayout()` and `contentView.layoutIfNeeded()` so the cell’s height and the embed’s frame are computed immediately.  
    - Set `embedContainer.layer.zPosition = -1` so the embed is drawn **behind** the same cell’s message header and content.  
  - Even if layout were wrong for a frame, the embed would not draw on top of the same message’s name/text.

---

## Files changed (summary)

| File | Change |
|------|--------|
| `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift` | `contentView.clipsToBounds = true` in init. |
| `Revolt/Pages/Channel/Messagable/Views/LinkPreviewView.swift` | `clipsToBounds = true` on root view in `setupUI()`. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Attachments.swift` | `embedContainer.clipsToBounds = true`; after adding embed, `contentView.setNeedsLayout()` + `layoutIfNeeded()` and `embedContainer.layer.zPosition = -1`. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableView.swift` | In `willDisplay`, for `MessageCell`: `contentView.setNeedsLayout()` and `contentView.layoutIfNeeded()`. |

---

## Related code locations (with acknowledgment comments)

The same fixes are marked in the codebase with short comments that reference this document:

- **MessageCell.swift** — comment above `contentView.clipsToBounds = true`
- **LinkPreviewView.swift** — comment above `clipsToBounds = true` on the root view
- **MessageCell+Attachments.swift** — comments above `embedContainer.clipsToBounds = true` and above the layout/zPosition block
- **MessageableChannelViewController+TableView.swift** — comment above the `setNeedsLayout`/`layoutIfNeeded()` block in `willDisplay`

See those comments for exact line references. For full context and future changes to link preview or message cell layout, refer to this document.

---

## Regression fix (latest)

After further usage, a second issue was reproduced:

- link preview image could become fully visible, but
- the preview still overlapped nearby message content for the latest few rows.

Root cause found during runtime debugging:

- Embed image load completion happened after initial cell sizing, but async invalidation callback was sometimes unavailable on reused cells.
- That meant row height cache was not always invalidated for those embed rows.

### Final code changes kept

#### 1) Link preview exposes async layout callback

```swift
// LinkPreviewView.swift
internal var onAsyncLayoutAffectingContentLoaded: (() -> Void)?

private func configureImagePreview(_ image: JanuaryImage) -> Bool {
    guard let url = URL(string: image.url) else { return false }

    previewImageView.isHidden = false
    previewImageView.kf.setImage(with: url) { [weak self] result in
        guard let self = self else { return }
        switch result {
        case .success:
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.onAsyncLayoutAffectingContentLoaded?()
        case .failure:
            break
        }
    }
    contentStackView.addArrangedSubview(previewImageView)
    // ... existing aspect-ratio constraints
    return true
}
```

#### 2) Message cell captures callback/message-id at embed setup and falls back to VC invalidation

```swift
// MessageCell+Attachments.swift (inside loadEmbeds)
let callbackMessageId = currentMessage?.id
let asyncCallback = onAsyncContentLoaded
linkPreview.onAsyncLayoutAffectingContentLoaded = { [weak self] in
    guard let messageId = callbackMessageId else { return }
    if let asyncCallback {
        asyncCallback(messageId)
    } else if let vc = self?.findParentViewController() as? MessageableChannelViewController {
        vc.invalidateHeightForMessage(messageId)
    }
}
```

This removes dependence on mutable cell state at async completion time and ensures embed rows still invalidate their cached height.

#### 3) Data source assigns async callback before configure

```swift
// MessageTableViewDataSource.swift (both data source paths)
cell.onAsyncContentLoaded = { [weak viewController] messageId in
    viewController?.invalidateHeightForMessage(messageId)
}

cell.configure(with: message,
               author: author,
               member: member,
               viewState: viewModel.viewState,
               isContinuation: isContinuation)
```

This ensures cache-hit async paths are wired before embed loading starts.

---

## Regression fix (prefetch inconsistency + duplicate/blank preview area)

After additional real-device testing, another issue appeared even with the overlap fixes:

- some link-preview rows looked duplicated or left a blank preview-sized gap,
- scrolling up/down often made the preview appear correctly again.

### Runtime evidence (critical)

The root cause was confirmed from runtime logs, not code inspection alone:

- `UITableView internal inconsistency: cell already prefetched for IP(...)`
- `prefetchedCells (...) and indexPathsForPrefetchedCells (...) are out of sync`

These errors happened while message rows were being remeasured/relaid out during display, which can desync UITableView’s prefetch bookkeeping and produce visual artifacts that look like duplicate preview cards or empty preview slots.

### Root cause

The issue was the combination of:

1. **UITableView prefetching enabled** for the chat list, and
2. **Aggressive table-wide relayout calls** (`beginUpdates()/endUpdates()`) triggered from display/async height paths.

For complex auto-height rows (text wrapping + attachments + embeds + async image load), this caused unstable row lifecycle behavior in prefetch state.

### Final fix kept

#### 1) Disable row prefetching for this chat table

In `MessageableChannelViewController+Setup.swift`:

- `tableView.prefetchDataSource = nil`
- `tableView.isPrefetchingEnabled = false`

This avoids UIKit prefetch bookkeeping races for highly dynamic message rows.

#### 2) Stop table-wide update bursts from `willDisplay`

In `MessageableChannelViewController+TableView.swift`:

- removed `beginUpdates()/endUpdates()` calls from `willDisplay`-driven height correction paths,
- kept only targeted cache invalidation when measurement changes.

#### 3) Use row-specific async height refresh

In `MessageableChannelViewController.invalidateHeightForMessage(_:)`:

- invalidate the message’s cached height,
- reload only that row (without animation) when it is visible,
- avoid global `beginUpdates()/endUpdates()` for async embed callbacks.

### Why this fixes the symptom

- Prevents prefetch state corruption in UITableView for dynamic embed rows.
- Keeps height invalidation scoped to the affected message instead of re-laying out the whole table.
- Eliminates the duplicate/blank preview effect that self-corrected only after manual scrolling/reuse.

### Files updated for this regression

| File | Change |
|------|--------|
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Setup.swift` | Disabled table prefetching (`prefetchDataSource = nil`, `isPrefetchingEnabled = false`). |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableView.swift` | Removed table-wide update bursts from `willDisplay` height correction paths. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` | Changed async embed height invalidation to row-specific visible reload. |
