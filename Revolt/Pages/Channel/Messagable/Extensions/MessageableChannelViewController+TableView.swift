//
//  MessageableChannelViewController+TableView.swift
//  Revolt
//
//

import UIKit
import Types

// MARK: - UITableViewDelegate
extension MessageableChannelViewController: UITableViewDelegate {
    // Note: UITableViewDataSource methods are now handled by LocalMessagesDataSource class
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            isLoadingMore = true
        }

        // Safety check for localMessages count
        guard !localMessages.isEmpty, indexPath.row < localMessages.count else {
            return
        }

        if indexPath.row == localMessages.count - 1 {
            markLastMessageAsSeen()
        }

        if let currentCell = cell as? MessageCell {
            let currentMessageId = localMessages[indexPath.row]
            let currentMessage = viewModel.viewState.messages[currentMessageId]
            let currentHasReply = !(currentMessage?.replies?.isEmpty ?? true)
            let nextHasReply: Bool = {
                let nextIndex = indexPath.row + 1
                guard nextIndex < localMessages.count else { return false }
                let nextMessageId = localMessages[nextIndex]
                let nextMessage = viewModel.viewState.messages[nextMessageId]
                return !(nextMessage?.replies?.isEmpty ?? true)
            }()
            
            if indexPath.row < localMessages.count - 1 {
                let nextMessageId = localMessages[indexPath.row + 1]
                let currentMessageId = localMessages[indexPath.row]

                if let nextMessage = viewModel.viewState.messages[nextMessageId],
                   let currentMessage = viewModel.viewState.messages[currentMessageId] {
                    if nextMessage.author != currentMessage.author {
                        currentCell.contentView.layoutMargins.bottom = 16
                    } else {
                        currentCell.contentView.layoutMargins.bottom = 4
                    }
                }
            }
            // Link preview overlap fix: finish layout before first draw (docs/Fix/LinkPreviewImage.md)
            currentCell.contentView.setNeedsLayout()
            currentCell.contentView.layoutIfNeeded()
            var finalHeight = currentCell.bounds.height
            let textWidth = max(1, currentCell.contentLabel.bounds.width)
            let fittedTextHeight = currentCell.contentLabel.sizeThatFits(
                CGSize(width: textWidth, height: .greatestFiniteMagnitude)
            ).height
            
            
            // Runtime-proven fix: textView can render with stale (too small) visible height on reused cells.
            // If fitted text height is larger, force min-height to fitted size and re-layout the row.
            let enforcement = currentCell.enforceVisibleTextHeightIfNeeded()
            if enforcement.updated {
                currentCell.contentView.setNeedsLayout()
                currentCell.contentView.layoutIfNeeded()
                let measuredHeight = currentCell.contentView.systemLayoutSizeFitting(
                    CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
                finalHeight = max(currentCell.bounds.height, measuredHeight)
                
                // Invalidate stale cached height for this message and reload row.
                // This prevents keeping a too-small cached cell height after text expansion.
                invalidateHeightForMessage(currentMessageId)
            }

            // PERF: Only run second layout pass for cells with complex content
            // (embeds, image/file attachments) where attributed text may need
            // multiple passes to settle. Plain text cells are correct after one pass.
            let hasComplexContent =
                (currentCell.imageAttachmentsContainer != nil && !currentCell.imageAttachmentsContainer!.isHidden) ||
                (currentCell.fileAttachmentsContainer != nil && !currentCell.fileAttachmentsContainer!.isHidden) ||
                currentCell.contentView.viewWithTag(2000) != nil

            if hasComplexContent {
                let firstHeight = finalHeight
                currentCell.contentView.setNeedsLayout()
                currentCell.contentView.layoutIfNeeded()
                finalHeight = currentCell.bounds.height

                // If height changed between passes, first pass was premature — trigger re-query
                if abs(finalHeight - firstHeight) > 1.0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.tableView.beginUpdates()
                        self?.tableView.endUpdates()
                    }
                }
            }

            // PERF Issue #9: Cache the measured height after layout
            let messageId = localMessages[indexPath.row]
            let isContinuation = shouldGroupWithPreviousMessage(at: indexPath)
            let key = CellHeightCacheKey(
                messageId: messageId,
                isContinuation: isContinuation,
                tableWidth: Int(tableView.bounds.width)
            )
            cellHeightCache.store(height: finalHeight, for: key)
        }

        loadMoreMessagesIfNeeded(for: indexPath)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // PERF Issue #9: Return cached height if available, otherwise let Auto Layout resolve
        guard indexPath.row < localMessages.count else {
            return UITableView.automaticDimension
        }
        let messageId = localMessages[indexPath.row]
        let isContinuation = shouldGroupWithPreviousMessage(at: indexPath)
        let key = CellHeightCacheKey(
            messageId: messageId,
            isContinuation: isContinuation,
            tableWidth: Int(tableView.bounds.width)
        )
        let cachedHeight = cellHeightCache.height(for: key)
        
        return cachedHeight ?? UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // PERF Issue #9: Return exact cached height when available (best estimate),
        // otherwise fall back to the static 120pt. Smaller heuristics can cause UIKit
        // to underestimate contentSize, making scrollToRow undershoot the bottom.
        guard indexPath.row < localMessages.count else { return 120 }

        let messageId = localMessages[indexPath.row]
        let isContinuation = shouldGroupWithPreviousMessage(at: indexPath)
        let key = CellHeightCacheKey(
            messageId: messageId,
            isContinuation: isContinuation,
            tableWidth: Int(tableView.bounds.width)
        )

        return cellHeightCache.height(for: key) ?? 120
    }
    

    
    // MARK: - Helper Methods
    
    func refreshMessagesWithoutScrolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Don't refresh if target message protection is active
            if self.targetMessageProtectionActive {
                // print("🔄 BLOCKED: refreshMessagesWithoutScrolling blocked - target message protection active")
                return
            }
            
            // Just reload the data without scrolling
            self.tableView.reloadData()
            
            // Update empty state visibility
            self.updateEmptyStateVisibility()
        }
    }
    
    func updateEmptyStateVisibility() {
        // CRITICAL FIX: Don't show empty state during target message loading
        if targetMessageProtectionActive || messageLoadingState == .loading {
            // print("🚫 EMPTY_STATE: Blocked showing empty state - target message loading in progress")
            hideEmptyStateView()
            return
        }
        
        if localMessages.isEmpty {
            showEmptyStateView()
        } else {
            hideEmptyStateView()
        }
    }
}

