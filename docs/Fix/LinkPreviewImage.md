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
