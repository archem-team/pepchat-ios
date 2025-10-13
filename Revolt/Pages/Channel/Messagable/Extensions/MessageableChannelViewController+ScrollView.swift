//
//  MessageableChannelViewController+ScrollView.swift
//  Revolt
//
//

import UIKit

// MARK: - UIScrollViewDelegate
extension MessageableChannelViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Cancel any pending auto-scroll operations immediately when user starts dragging
        scrollToBottomWorkItem?.cancel()
        scrollToBottomWorkItem = nil
        // print("👆 USER_DRAG_START: Cancelled all auto-scroll operations")
        
        // Start scroll protection timer
        startScrollProtection()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // Update manual scroll tracking
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
        let isScrollingUp = translation.y > 0
        
        if isScrollingUp {
            lastManualScrollUpTime = Date()
            lastManualScrollTime = Date()
            // print("👆 USER_DRAG_END: Updated manual scroll up time")
        }
        
        // REMOVED: No longer clear protection based on scroll gestures
        // User should be free to scroll anywhere while protection is active
        if targetMessageProtectionActive {
            print("🛡️ DRAG_END: Protection maintained regardless of scroll gesture - user can scroll freely")
        }
        
        // Check if we've reached near the top and trigger message loading
        let offsetY = scrollView.contentOffset.y
        let triggerThreshold: CGFloat = 100.0 // Same threshold as in scrollViewDidScroll
        
        // If user has dragged near the top, load more messages
        if offsetY <= triggerThreshold && !isLoadingMore && scrollView == tableView {
            // CRITICAL FIX: Check if we recently received an empty response (reached beginning)
            if let lastEmpty = lastEmptyResponseTime,
               Date().timeIntervalSince(lastEmpty) < 60.0 { // Don't retry for 1 minute
                print("⏹️ DRAG_END_BLOCKED: Reached beginning of conversation recently, skipping load")
                return
            }
            
            // Ensure we have messages to work with
            let messages = !viewModel.messages.isEmpty ? viewModel.messages : localMessages
            
            // Only load if we have messages and not already at the top of channel history
            if !messages.isEmpty && !viewModel.viewState.atTopOfChannel.contains(viewModel.channel.id) {
                if let firstMessageId = messages.first {
                    // print("🔄 DRAG_END TRIGGER: User released near top, loading older messages")
                    
                    // Set loading state
                    isLoadingMore = true
                    
                    // Show loading indicator immediately
                    DispatchQueue.main.async {
                        // Add header if not already added
                        if self.tableView.tableHeaderView == nil {
                            self.tableView.tableHeaderView = self.loadingHeaderView
                        }
                        self.loadingHeaderView.isHidden = false
                        // Force layout update to ensure indicator is visible
                        self.view.layoutIfNeeded()
                    }
                    
                    // Load older messages
                    loadMoreMessages(before: firstMessageId)
                }
            }
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // First, check and reset loading state if needed
        resetLoadingStateIfNeeded()
        
        // CRITICAL: Protect against scrolling during data source changes
        guard !isDataSourceUpdating else {
            print("📊 SCROLL_PROTECTION: Ignoring scroll event during data source update")
            return
        }
        
        // Update bouncing behavior on every scroll
        updateTableViewBouncing()
        
        // CRITICAL FIX: Sync viewModel.messages with localMessages if they're inconsistent
        // But only if data source is stable
        if viewModel.messages.isEmpty && !localMessages.isEmpty {
            // print("⚠️ CRITICAL SYNC: viewModel.messages is empty but localMessages has \(localMessages.count) items - syncing")
            viewModel.messages = localMessages
            
            // Also update viewState for consistency
            viewModel.viewState.channelMessages[viewModel.channel.id] = localMessages
        }
        
        // Cancel any pending auto-scroll operations when user manually scrolls
        if scrollView.isDragging {
            scrollToBottomWorkItem?.cancel()
            scrollToBottomWorkItem = nil
            
            // Mark as data source stable when user actively scrolls
            if isDataSourceUpdating {
                print("📊 DATA_SOURCE: User scroll detected, marking data source as stable")
                isDataSourceUpdating = false
            }
        }
        
        // Track when user manually scrolls up  
        if scrollView.isDragging || scrollView.isDecelerating {
            // User is manually scrolling
            lastManualScrollTime = Date()
            
            // REMOVED: No longer clear protection based on scroll distance
            // User should be free to scroll anywhere while protection is active
            // Protection will only be cleared by timer, manual actions, or sending messages
            if targetMessageProtectionActive {
                print("🛡️ TARGET_PROTECTION: Scroll detected but protection maintained - user can scroll freely")
            }
            
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
            let isScrollingUp = translation.y > 0
            
            // Check if user is scrolling up by comparing with lastScrollOffset
            let currentOffsetY = scrollView.contentOffset.y
            if currentOffsetY < lastScrollOffset {
                lastManualScrollUpTime = Date()
                // print("👆 User manually scrolled up")
            }
            
            // IMPROVED: Trigger loading when approaching the top (within 100px), not just at the very top
            let offsetY = scrollView.contentOffset.y
            let triggerThreshold: CGFloat = 100.0 // Load when within 100px of top
            
            // Check if we should load older messages
            if offsetY <= triggerThreshold && !isLoadingMore && scrollView == tableView {
                // CRITICAL FIX: Check if we recently received an empty response (reached beginning)
                if let lastEmpty = lastEmptyResponseTime,
                   Date().timeIntervalSince(lastEmpty) < 60.0 { // Don't retry for 1 minute
                    print("⏹️ SCROLL_BLOCKED: Reached beginning of conversation recently, skipping load")
                    return
                }
                
                // Ensure we have messages to work with
                let messages = !viewModel.messages.isEmpty ? viewModel.messages : localMessages
                
                // Only load if we have messages and not already at the top of channel history
                if !messages.isEmpty && !viewModel.viewState.atTopOfChannel.contains(viewModel.channel.id) {
                    if let firstMessageId = messages.first {
                        // print("🔄 LOAD TRIGGER: User approaching top (offset: \(offsetY)), loading older messages")
                        
                        // Set loading state
                        isLoadingMore = true
                        
                        // Show loading indicator immediately
                        DispatchQueue.main.async {
                            // Add header if not already added
                            if self.tableView.tableHeaderView == nil {
                                self.tableView.tableHeaderView = self.loadingHeaderView
                            }
                            self.loadingHeaderView.isHidden = false
                            // Force layout update to ensure indicator is visible
                            self.view.layoutIfNeeded()
                        }
                        
                        // Load older messages
                        loadMoreMessages(before: firstMessageId)
                    }
                }
            }
        }
        
        // INFINITE SCROLL DOWN: Check if user is near bottom to load newer messages
        if scrollView == tableView {
            detectScrollToBottomForLoadingMore()
        }
        
        // Update lastScrollOffset for tracking scroll direction
        lastScrollOffset = scrollView.contentOffset.y
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Stop scroll protection after deceleration ends
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil
    }
    
    // MARK: - Scroll Helper Methods
    
    private func detectScrollToBottomForLoadingMore() {
        // Only proceed if we have enough messages and not already loading
        guard localMessages.count >= 200 && !isLoadingMore else { return }
        
        let contentHeight = tableView.contentSize.height
        let offsetY = tableView.contentOffset.y
        let frameHeight = tableView.frame.size.height
        
        // Check if user is very close to the bottom (within 100 points)
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        
        if distanceFromBottom <= 100 {
            // User is near bottom - check if we should load newer messages
            if let lastMessageId = localMessages.last {
                // print("📥 SCROLL DOWN: User near bottom, loading newer messages after ID: \(lastMessageId)")
                loadNewerMessages(after: lastMessageId)
            }
        }
    }
    
    private func startScrollProtection() {
        // Cancel existing timer
        scrollProtectionTimer?.invalidate()
        
        // Start a timer that monitors for unwanted auto-scroll for 3 seconds
        scrollProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // If user is still dragging or decelerating, keep protecting
            if self.tableView.isDragging || self.tableView.isDecelerating {
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
    
    func scrollToBottom(animated: Bool) {
        print("🔍 SCROLL_TO_TOP: Called with animated: \(animated) (newest messages are now at top)")
        debugTargetMessageProtection()
        
        guard !localMessages.isEmpty else { 
            print("🚫 SCROLL_TO_TOP: No messages, returning")
            return 
        }
        
        // SIMPLIFIED TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print("🎯 scrollToTop: Target message protection active, blocking auto-scroll")
            print("🎯 Protection details - targetMessageId: \(targetMessageId != nil), isInPosition: \(isInTargetMessagePosition), processed: \(targetMessageProcessed)")
            return
        }
        
        // ADDITIONAL SAFEGUARD: Double-check that we're not in the middle of target message operations
        if let targetId = targetMessageId {
            print("🛡️ scrollToTop: Additional check - target message \(targetId) still exists, blocking scroll")
            return
        }
        
        // Force layout updates first
        view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        
        // JUMPING FIX: For very few messages, be extra conservative with scrolling
        let messageCount = localMessages.count
        if messageCount <= 10 {
            // For few messages, use longer debounce interval to prevent jumping
            let conservativeDebounceInterval: TimeInterval = 2.0
            let now = Date()
            if let lastTime = lastScrollToBottomTime,
               now.timeIntervalSince(lastTime) < conservativeDebounceInterval {
                // print("📊 CONSERVATIVE_SCROLL: Too soon since last scroll for few messages (\(messageCount)), skipping")
                return
            }
            lastScrollToBottomTime = now
            
            // For few messages with keyboard visible, use proper positioning
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let lastIndex = self.localMessages.count - 1
                guard lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) else { return }
                
                let indexPath = IndexPath(row: lastIndex, section: 0)
                
                // Check keyboard state even for few messages
                if self.isKeyboardVisible {
                    // When keyboard is visible, ensure message appears above input
                    self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
                    // print("📊 CONSERVATIVE_SCROLL: Scrolled to bottom with keyboard for \(messageCount) messages")
                } else {
                    self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
                    // print("📊 CONSERVATIVE_SCROLL: Simple scroll to bottom for \(messageCount) messages")
                }
            }
            return
        }
        
        // Use Constants for debounce interval for normal message counts
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
            guard let self = self else { return }
            
            // Force another layout update before scrolling
            self.view.layoutIfNeeded()
            self.tableView.layoutIfNeeded()
            
            // Scroll to top (row 0) since newest messages are now at the top
            let topIndex = 0
            let indexPath = IndexPath(row: topIndex, section: 0)
            
            // Check if the index path is valid
            guard topIndex >= 0 && topIndex < self.tableView.numberOfRows(inSection: 0) else {
                // print("📊 SCROLL_TO_TOP: Invalid index path \(indexPath)")
                return
            }
            
            // Always use .top positioning since newest messages are at the top
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: animated)
            
            // For keyboard visible state, do an extra scroll after animation
            if self.isKeyboardVisible && animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                    // print("📊 SCROLL_TO_TOP: Extra scroll for keyboard visibility")
                }
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
    
    // isUserNearBottom method is in main file
    
    func resetNearbyLoadingFlag() {
        // Reset any loading flags
        isLoadingMore = false
        // Update table view bouncing behavior when loading is reset
        updateTableViewBouncing()
    }
}

