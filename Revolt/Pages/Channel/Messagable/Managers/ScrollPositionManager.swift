//
//  ScrollPositionManager.swift
//  Revolt
//
//

import UIKit

class ScrollPositionManager {
    weak var viewController: MessageableChannelViewController?
    
    // Scroll tracking properties
    private var scrollToBottomWorkItem: DispatchWorkItem?
    private var lastManualScrollTime: Date?
    private var lastManualScrollUpTime: Date?
    private var lastScrollToBottomTime: Date?
    private var scrollProtectionTimer: Timer?
    
    init(viewController: MessageableChannelViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Scroll Position Tracking
    
    func updateManualScrollTime() {
        lastManualScrollTime = Date()
    }
    
    func updateManualScrollUpTime() {
        lastManualScrollUpTime = Date()
        lastManualScrollTime = Date()
    }
    
    func resetManualScrollUpTime() {
        lastManualScrollUpTime = nil
    }
    
    var hasManuallyScrolledUpRecently: Bool {
        guard let lastScrollUpTime = lastManualScrollUpTime else { return false }
        return Date().timeIntervalSince(lastScrollUpTime) < 10.0
    }
    
    var hasManuallyScrolledRecently: Bool {
        guard let lastScrollTime = lastManualScrollTime else { return false }
        return Date().timeIntervalSince(lastScrollTime) < 10.0
    }
    
    // MARK: - Scroll to Bottom
    
    func scrollToBottom(animated: Bool) {
        guard let viewController = viewController else { return }
        guard !viewController.localMessages.isEmpty else { return }
        
        // IMPROVED: Check full target message protection instead of just highlight time
        if viewController.targetMessageProtectionActive {
            print("🎯 ScrollPositionManager: Target message protection active, skipping auto-scroll")
            return
        }
        
        // Use Constants for debounce interval
        let now = Date()
        if let lastTime = lastScrollToBottomTime,
           now.timeIntervalSince(lastTime) < MessageableChannelConstants.scrollDebounceInterval {
            // print("📊 SCROLL_DEBOUNCE: Too soon since last scroll, skipping")
            return
        }
        lastScrollToBottomTime = now
        
        // Cancel any existing work item
        scrollToBottomWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let viewController = self.viewController else { return }
            
            let lastIndex = viewController.localMessages.count - 1
            let indexPath = IndexPath(row: lastIndex, section: 0)
            
            guard viewController.tableView.dataSource != nil, lastIndex < viewController.tableView.numberOfRows(inSection: 0) else { return }
            // Check if the index path is valid
            guard lastIndex >= 0 && lastIndex < viewController.tableView.numberOfRows(inSection: 0) else {
                // print("📊 SCROLL_TO_BOTTOM: Invalid index path \(indexPath)")
                return
            }
            
            if animated {
                viewController.tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            } else {
                viewController.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            }
        }
        
        scrollToBottomWorkItem = workItem
        
        // Execute immediately or with delay based on animation
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    func cancelScrollToBottom() {
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
    }
    
    // MARK: - Scroll Protection
    
    func startScrollProtection() {
        // Cancel existing timer
        scrollProtectionTimer?.invalidate()
        
        // Start a timer that monitors for unwanted auto-scroll for 3 seconds
        scrollProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, let viewController = self.viewController else {
                timer.invalidate()
                return
            }
            
            // If user is still dragging or decelerating, keep protecting
            if viewController.tableView.isDragging || viewController.tableView.isDecelerating {
                // Cancel any auto-scroll operations
                self.scrollToBottomWorkItem?.cancel()
                self.scrollToBottomWorkItem = nil
            } else {
                // User finished scrolling, stop protection after a short delay
                timer.invalidate()
                self.scrollProtectionTimer = nil
            }
        }
    }
    
    func stopScrollProtection() {
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil
    }
    
    // MARK: - Position Checking
    
    func isUserNearBottom(threshold: CGFloat? = nil) -> Bool {
        guard let viewController = viewController else { return false }
        
        // If user has manually scrolled up recently, they're definitely not near bottom
        if hasManuallyScrolledUpRecently {
            // print("📊 IS_USER_NEAR_BOTTOM: User scrolled up recently, returning false")
            return false
        }
        
        // If user is actively scrolling, don't consider them at bottom
        if viewController.tableView.isDragging || viewController.tableView.isDecelerating {
            // print("📊 IS_USER_NEAR_BOTTOM: User is actively scrolling, returning false")
            return false
        }
        
        // SPECIAL CASE: For read-only channels with markdown content
        // Be more conservative about considering user "near bottom"
        let isReadOnlyChannel = !viewController.sendMessagePermission
        
        let actualThreshold = threshold ?? MessageableChannelConstants.nearBottomThreshold
        let adjustedThreshold = isReadOnlyChannel ? actualThreshold / 2 : actualThreshold  // More strict for read-only
        
        let offsetY = viewController.tableView.contentOffset.y
        let contentHeight = viewController.tableView.contentSize.height
        let frameHeight = viewController.tableView.frame.height
        
        // Make sure we have valid content dimensions
        guard contentHeight > 0, frameHeight > 0 else {
            // print("📊 IS_USER_NEAR_BOTTOM: Invalid dimensions, returning true")
            return true
        }
        
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        let isNearBottom = distanceFromBottom <= adjustedThreshold
        
        // Add detailed logging to debug the issue
        // print("📊 IS_USER_NEAR_BOTTOM: offsetY=\(offsetY), contentHeight=\(contentHeight), frameHeight=\(frameHeight)")
        // print("📊 IS_USER_NEAR_BOTTOM: distanceFromBottom=\(distanceFromBottom), threshold=\(adjustedThreshold), isReadOnly=\(isReadOnlyChannel), isNearBottom=\(isNearBottom)")
        
        return isNearBottom
    }
    
    func isAtTop() -> Bool {
        guard let viewController = viewController else { return false }
        
        let offsetY = viewController.tableView.contentOffset.y
        let canSeeFirstMessage = viewController.tableView.indexPathsForVisibleRows?.contains(IndexPath(row: 0, section: 0)) == true
        return offsetY <= 0 && canSeeFirstMessage
    }
    
    func isAtBottom() -> Bool {
        guard let viewController = viewController else { return false }
        
        let offsetY = viewController.tableView.contentOffset.y
        let contentHeight = viewController.tableView.contentSize.height
        let frameHeight = viewController.tableView.frame.height
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        return distanceFromBottom < 5
    }
    
    // MARK: - Scroll Position Preservation
    
    func maintainScrollPositionAfterInsertingMessages(at insertionIndex: Int, count: Int, animated: Bool) {
        guard let viewController = viewController else { return }
        
        // If user is near bottom, scroll to bottom after insertion
        if isUserNearBottom() {
            DispatchQueue.main.async {
                self.scrollToBottom(animated: animated)
            }
            return
        }
        
        // Otherwise, maintain current scroll position
        let anchor = createAnchorInfo()
        
        DispatchQueue.main.async {
            self.restoreScrollPositionToAnchor(anchor, insertedCount: count)
        }
    }
    
    private func createAnchorInfo() -> AnchorCellInfo? {
        guard let viewController = viewController else { return nil }
        
        // Find a visible cell to use as anchor
        guard let visibleIndexPaths = viewController.tableView.indexPathsForVisibleRows,
              let firstVisibleIndexPath = visibleIndexPaths.first,
              let cell = viewController.tableView.cellForRow(at: firstVisibleIndexPath) else {
            return nil
        }
        
        let cellFrame = cell.frame
        let tableViewBounds = viewController.tableView.bounds
        let offsetFromTop = cellFrame.minY - tableViewBounds.minY
        
        return AnchorCellInfo(
            indexPath: firstVisibleIndexPath,
            offsetFromTop: offsetFromTop
        )
    }
    
    private func restoreScrollPositionToAnchor(_ anchor: AnchorCellInfo?, insertedCount: Int) {
        guard let viewController = viewController,
              let anchor = anchor else { return }
        
        // Adjust index path for inserted messages
        let newIndexPath = IndexPath(
            row: anchor.indexPath.row + insertedCount,
            section: anchor.indexPath.section
        )
        
        // Scroll to the adjusted position
        if newIndexPath.row < viewController.tableView.numberOfRows(inSection: 0) {
            guard viewController.tableView.dataSource != nil else { return }
            viewController.tableView.scrollToRow(at: newIndexPath, at: .top, animated: false)
            
            // Fine-tune the offset
            let currentOffset = viewController.tableView.contentOffset
            let adjustedOffset = CGPoint(
                x: currentOffset.x,
                y: currentOffset.y + anchor.offsetFromTop
            )
            viewController.tableView.setContentOffset(adjustedOffset, animated: false)
        }
    }
}

// MARK: - Supporting Types

private struct AnchorCellInfo {
    let indexPath: IndexPath
    let offsetFromTop: CGFloat
}

