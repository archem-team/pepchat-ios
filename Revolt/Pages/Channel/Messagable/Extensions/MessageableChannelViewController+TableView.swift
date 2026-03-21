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

            // PERF Issue #9: Cache the measured height after layout
            let messageId = localMessages[indexPath.row]
            let isContinuation = shouldGroupWithPreviousMessage(at: indexPath)
            let key = CellHeightCacheKey(
                messageId: messageId,
                isContinuation: isContinuation,
                tableWidth: Int(tableView.bounds.width)
            )
            cellHeightCache.store(height: currentCell.bounds.height, for: key)
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
        return cellHeightCache.height(for: key) ?? UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // PERF Issue #9: Context-aware height estimates reduce scroll bar jitter
        guard indexPath.row < localMessages.count else { return 120 }

        let messageId = localMessages[indexPath.row]
        let isContinuation = shouldGroupWithPreviousMessage(at: indexPath)
        let key = CellHeightCacheKey(
            messageId: messageId,
            isContinuation: isContinuation,
            tableWidth: Int(tableView.bounds.width)
        )

        // Best estimate: a previously measured height
        if let cached = cellHeightCache.height(for: key) {
            return cached
        }

        // Heuristic estimate based on message content
        guard let message = viewModel.viewState.messages[messageId] else { return 120 }

        var estimate: CGFloat = isContinuation ? 44 : 68
        if let attachments = message.attachments, !attachments.isEmpty {
            let hasImages = attachments.contains {
                if case .image = $0.metadata { return true }
                return false
            }
            estimate += hasImages ? 200 : 60
        }
        if let embeds = message.embeds, !embeds.isEmpty { estimate += 120 }
        if let reactions = message.reactions, !reactions.isEmpty { estimate += 36 }
        if let replies = message.replies, !replies.isEmpty { estimate += 28 }
        return estimate
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

