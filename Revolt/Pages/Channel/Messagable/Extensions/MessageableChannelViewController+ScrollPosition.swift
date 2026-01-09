//
//  MessageableChannelViewController+ScrollPosition.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//  Phase 3: Medium-Risk Extensions - Scroll Position Preservation

import UIKit

// MARK: - Scroll Position Preservation
extension MessageableChannelViewController {
    
    /// Reloads the table view while maintaining the user's scroll position using message IDs as anchors
    private func reloadTableViewMaintainingScrollPosition(messagesForDataSource: [String]) {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            // No visible rows, just reload normally
            tableView.reloadData()
            return
        }
        
        // Find an anchor message ID from visible rows (prefer middle visible row for stability)
        var anchorMessageId: String?
        var anchorDistanceFromTop: CGFloat = 0
        
        // Try to find a good anchor from the middle of visible rows
        let middleIndex = visibleIndexPaths.count / 2
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            // Prefer rows that are not at the very edges
            if index >= middleIndex && indexPath.row < messagesForDataSource.count {
                anchorMessageId = messagesForDataSource[indexPath.row]
                let cellFrame = tableView.rectForRow(at: indexPath)
                anchorDistanceFromTop = cellFrame.origin.y - tableView.contentOffset.y
                // print("🔍 SCROLL_PRESERVE: Selected anchor message \(anchorMessageId!) at index \(indexPath.row), distance from top: \(anchorDistanceFromTop)")
                break
            }
        }
        
        // Fallback to first visible row if no middle row found
        if anchorMessageId == nil, let firstVisible = visibleIndexPaths.first, firstVisible.row < messagesForDataSource.count {
            anchorMessageId = messagesForDataSource[firstVisible.row]
            let cellFrame = tableView.rectForRow(at: firstVisible)
            anchorDistanceFromTop = cellFrame.origin.y - tableView.contentOffset.y
            // print("🔍 SCROLL_PRESERVE: Using fallback anchor message \(anchorMessageId!) at index \(firstVisible.row)")
        }
        
        // Perform the reload
        tableView.reloadData()
        tableView.layoutIfNeeded()
        
        // Restore position to the anchor message
        if let anchorId = anchorMessageId {
            // Find the anchor message in the new data
            if let newIndex = messagesForDataSource.firstIndex(of: anchorId) {
                let newIndexPath = IndexPath(row: newIndex, section: 0)
                let newCellFrame = tableView.rectForRow(at: newIndexPath)
                let newContentOffsetY = newCellFrame.origin.y - anchorDistanceFromTop
                
                // Ensure the offset is within valid bounds
                let maxOffset = max(0, tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom)
                let clampedOffset = max(0, min(newContentOffsetY, maxOffset))
                
                tableView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: false)
                // print("📍 SCROLL_PRESERVE: Restored position to anchor message at new index \(newIndex), offset: \(clampedOffset)")
            } else {
                // print("⚠️ SCROLL_PRESERVE: Could not find anchor message \(anchorId) in new data")
            }
        }
    }
}
