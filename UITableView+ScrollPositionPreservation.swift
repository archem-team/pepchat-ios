//
//  UITableView+ScrollPositionPreservation.swift
//  
//  A reusable extension for maintaining scroll position when inserting cells at the top of a UITableView.
//  Perfect for chat applications where older messages are loaded dynamically.
//

import UIKit

extension UITableView {
    
    /// Information about an anchor cell used for scroll position preservation
    struct AnchorCellInfo {
        let indexPath: IndexPath
        let distanceFromTop: CGFloat
        let cellFrame: CGRect
    }
    
    /// Maintains the user's visual scroll position when inserting rows at the top of the table view.
    /// This ensures the user continues looking at the same content after new rows are added above.
    ///
    /// Usage example:
    /// ```swift
    /// tableView.maintainScrollPositionWhileInsertingRows(at: 0, count: newMessages.count, animated: false)
    /// ```
    ///
    /// - Parameters:
    ///   - insertionIndex: The index where new rows will be inserted (typically 0 for top insertion)
    ///   - count: The number of rows being inserted
    ///   - animated: Whether to animate the insertion
    func maintainScrollPositionWhileInsertingRows(at insertionIndex: Int, count: Int, animated: Bool = false) {
        guard count > 0 else { return }
        
        // Step 1: Find an anchor cell before insertion
        let anchorInfo = findAnchorCellBeforeInsertion()
        
        // Step 2: Create index paths for new rows
        let indexPaths = (0..<count).map { IndexPath(row: insertionIndex + $0, section: 0) }
        
        if animated {
            performBatchUpdates({
                self.insertRows(at: indexPaths, with: .none)
            }) { _ in
                // Step 3: Restore position after insertion completes
                if let anchor = anchorInfo {
                    self.restoreScrollPositionToAnchor(anchor, insertedCount: count)
                }
            }
        } else {
            // For non-animated updates, disable animations to prevent jumps
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            beginUpdates()
            insertRows(at: indexPaths, with: .none)
            endUpdates()
            
            // Immediately restore position
            if let anchor = anchorInfo {
                restoreScrollPositionToAnchor(anchor, insertedCount: count)
            }
            
            CATransaction.commit()
        }
    }
    
    /// Alternative method that performs a full reload while maintaining scroll position.
    /// Useful when you need to reload the entire table but want to keep the user's position.
    ///
    /// - Parameters:
    ///   - identifier: A closure that returns a unique identifier for a cell at a given index path
    ///   - newDataCount: The number of items in the new data source
    func reloadDataMaintainingScrollPosition<T: Equatable>(
        identifier: (IndexPath) -> T?,
        newDataCount: Int
    ) {
        guard let visiblePaths = indexPathsForVisibleRows,
              !visiblePaths.isEmpty else {
            reloadData()
            return
        }
        
        // Find anchor cell and its identifier
        var anchorIdentifier: T?
        var anchorDistanceFromTop: CGFloat = 0
        
        for (index, indexPath) in visiblePaths.enumerated() {
            // Prefer cells that are not at the very top
            if index >= 1 || visiblePaths.count == 1 {
                if let id = identifier(indexPath) {
                    anchorIdentifier = id
                    let cellFrame = rectForRow(at: indexPath)
                    anchorDistanceFromTop = cellFrame.origin.y - contentOffset.y
                    break
                }
            }
        }
        
        // Perform the reload
        reloadData()
        layoutIfNeeded()
        
        // Find the anchor in the new data and restore position
        if let anchorId = anchorIdentifier {
            // Search for the anchor identifier in the new data
            for row in 0..<newDataCount {
                let indexPath = IndexPath(row: row, section: 0)
                if identifier(indexPath) == anchorId {
                    let newCellFrame = rectForRow(at: indexPath)
                    let newContentOffsetY = newCellFrame.origin.y - anchorDistanceFromTop
                    setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)
                    break
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Finds a suitable anchor cell to use for maintaining scroll position
    private func findAnchorCellBeforeInsertion() -> AnchorCellInfo? {
        guard let visibleIndexPaths = indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            return nil
        }
        
        let currentOffset = contentOffset
        let topInset = contentInset.top
        
        // Find the first fully visible cell (not partially clipped)
        for (index, indexPath) in visibleIndexPaths.enumerated() {
            let cellFrame = rectForRow(at: indexPath)
            let cellTop = cellFrame.origin.y
            let cellBottom = cellFrame.origin.y + cellFrame.height
            
            let visibleTop = currentOffset.y + topInset
            let visibleBottom = currentOffset.y + bounds.height - contentInset.bottom
            
            // Check if cell is fully visible
            let isFullyVisible = cellTop >= visibleTop && cellBottom <= visibleBottom
            
            // Use the second or third fully visible cell as anchor (more stable)
            // This prevents using a cell that might be scrolled out of view
            if isFullyVisible && index >= 1 {
                let distanceFromTop = cellTop - currentOffset.y
                
                return AnchorCellInfo(
                    indexPath: indexPath,
                    distanceFromTop: distanceFromTop,
                    cellFrame: cellFrame
                )
            }
        }
        
        // Fallback: use the first visible cell if no fully visible cell found
        if let firstVisible = visibleIndexPaths.first {
            let cellFrame = rectForRow(at: firstVisible)
            let distanceFromTop = cellFrame.origin.y - currentOffset.y
            
            return AnchorCellInfo(
                indexPath: firstVisible,
                distanceFromTop: distanceFromTop,
                cellFrame: cellFrame
            )
        }
        
        return nil
    }
    
    /// Restores the scroll position so the anchor cell appears at the same visual position
    private func restoreScrollPositionToAnchor(_ anchor: AnchorCellInfo, insertedCount: Int) {
        // The anchor cell's index has shifted down by the number of inserted rows
        let newIndexPath = IndexPath(row: anchor.indexPath.row + insertedCount, section: 0)
        
        // Ensure the new index path is valid
        guard newIndexPath.row < numberOfRows(inSection: 0) else {
            return
        }
        
        // Get the new frame of the anchor cell
        let newCellFrame = rectForRow(at: newIndexPath)
        
        // Calculate the new content offset to maintain the same visual position
        let newContentOffsetY = newCellFrame.origin.y - anchor.distanceFromTop
        
        // Apply the new content offset without animation to avoid visual jumps
        setContentOffset(CGPoint(x: 0, y: newContentOffsetY), animated: false)
    }
}

// MARK: - Usage Example
/*
class ChatViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    var messages: [Message] = []
    
    func loadOlderMessages() {
        // Fetch older messages from API
        apiClient.fetchMessages(before: messages.first?.id) { [weak self] newMessages in
            guard let self = self, !newMessages.isEmpty else { return }
            
            // Insert new messages at the beginning of the array
            self.messages.insert(contentsOf: newMessages, at: 0)
            
            // Update table view while maintaining scroll position
            self.tableView.maintainScrollPositionWhileInsertingRows(
                at: 0,
                count: newMessages.count,
                animated: false
            )
        }
    }
    
    // Alternative approach using full reload
    func reloadMessagesKeepingPosition() {
        tableView.reloadDataMaintainingScrollPosition(
            identifier: { indexPath in
                return self.messages[safe: indexPath.row]?.id
            },
            newDataCount: messages.count
        )
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
*/ 