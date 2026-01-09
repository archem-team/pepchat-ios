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
            
            // MEMORY OPTIMIZATION: Start loading images when cell becomes visible
            let messageId = indexPath.row < localMessages.count ? localMessages[indexPath.row] : "unknown"
            print("👁️ [MEMORY] Cell became visible: row \(indexPath.row), message: \(messageId)")
            currentCell.startImageLoadsIfNeeded()
        }
        
        loadMoreMessagesIfNeeded(for: indexPath)
    }
    
    // MEMORY OPTIMIZATION: Cancel image loads when cells scroll off-screen
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let messageCell = cell as? MessageCell {
            let messageId = indexPath.row < localMessages.count ? localMessages[indexPath.row] : "unknown"
            print("👁️ [MEMORY] Cell scrolled off-screen: row \(indexPath.row), message: \(messageId)")
            // Cancel all image downloads for this cell
            // This is handled in prepareForReuse, but we can also cancel here
            // to be more aggressive about memory management
            messageCell.cancelImageLoads()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Always use automatic dimension to let constraints determine the height
        // This prevents overlapping issues and ensures proper cell sizing
        return UITableView.automaticDimension
    }
    

    
    // MARK: - Helper Methods
    
    func refreshMessagesWithoutScrolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Don't refresh if target message protection is active
            if self.targetMessageProtectionActive {
                print("🔄 BLOCKED: refreshMessagesWithoutScrolling blocked - target message protection active")
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
            print("🚫 EMPTY_STATE: Blocked showing empty state - target message loading in progress")
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
