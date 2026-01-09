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

        isUserScrolling = true
        replyFetchDebounceTask?.cancel()
        
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
        
        if !decelerate {
            handleScrollEndForReplyPrefetch()
        }

        // Check if we've reached near the top and trigger message loading
        let offsetY = scrollView.contentOffset.y
        let triggerThreshold: CGFloat = 100.0 // Same threshold as in scrollViewDidScroll
        
        // If user has dragged near the top, load more messages
        if offsetY <= triggerThreshold && !isLoadingMore && scrollView == tableView {
            // CRITICAL FIX: Check if we recently received an empty response (reached beginning)
            // Reduced cooldown from 60s to 10s to allow retries if user scrolls again
            if let lastEmpty = lastEmptyResponseTime,
               Date().timeIntervalSince(lastEmpty) < 10.0 {
                print("⏹️ DRAG_END_BLOCKED: Reached beginning of conversation recently, skipping load")
                return
            }
            
            // Ensure we have messages to work with
            let messages = !viewModel.messages.isEmpty ? viewModel.messages : localMessages
            
            // Only load if we have messages and not already at the top of channel history
            if !messages.isEmpty && !viewModel.viewState.atTopOfChannel.contains(viewModel.channel.id) {
                if let firstMessageId = messages.first {
                    // print("🔄 DRAG_END TRIGGER: User released near top, loading older messages")
                    
                    // CRITICAL FIX: Set trigger time and loading state atomically to prevent duplicates
                    lastOlderMessagesLoadTriggerTime = Date()
                    isLoadingMore = true
                    
                    // Show loading indicator immediately (only if not already showing)
                    DispatchQueue.main.async {
                        // Add header if not already added
                        if self.tableView.tableHeaderView == nil {
                            self.tableView.tableHeaderView = self.loadingHeaderView
                        }
                        // Only show if not already visible to prevent jumping
                        if self.loadingHeaderView.isHidden {
                            self.loadingHeaderView.isHidden = false
                        }
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
        
        // MEMORY MANAGEMENT: Aggressive cleanup during scrolling to prevent memory growth to 1.8GB
        // Check every 20 scroll events to avoid performance impact
        scrollEventCount += 1
        if scrollEventCount % 20 == 0 {
            let currentCount = localMessages.count
            let maxCount = MessageableChannelConstants.maxMessagesInMemory
            if currentCount > Int(Double(maxCount) * 1.2) {
                enforceMessageWindow(keepingMostRecent: true)
                // Also trigger ViewState cleanup if total messages are very high
                let totalMessages = viewModel.viewState.messages.count
                if totalMessages > 1500 {
                    Task.detached(priority: .background) { [weak self] in
                        guard let self = self else { return }
                        await MainActor.run {
                            self.viewModel.viewState.enforceMemoryLimits()
                        }
                    }
                }
            }
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
            // CRITICAL FIX: Add debounce to prevent rapid-fire triggers and duplicate logs
            let minTimeBetweenLoads: TimeInterval = 1.0 // Minimum 1 second between load triggers
            let canTriggerLoad = lastOlderMessagesLoadTriggerTime == nil || 
                                Date().timeIntervalSince(lastOlderMessagesLoadTriggerTime!) >= minTimeBetweenLoads
            
            if offsetY <= triggerThreshold && !isLoadingMore && scrollView == tableView && canTriggerLoad {
                // CRITICAL FIX: Check if we recently received an empty response (reached beginning)
                // Reduced cooldown from 60s to 10s to allow retries if user scrolls again
                if let lastEmpty = lastEmptyResponseTime,
                   Date().timeIntervalSince(lastEmpty) < 10.0 {
                    print("⏹️ SCROLL_BLOCKED: Reached beginning of conversation recently, skipping load")
                    return
                }
                
                // Ensure we have messages to work with
                let messages = !viewModel.messages.isEmpty ? viewModel.messages : localMessages
                
                // Only load if we have messages and not already at the top of channel history
                if !messages.isEmpty && !viewModel.viewState.atTopOfChannel.contains(viewModel.channel.id) {
                    if let firstMessageId = messages.first {
                        // CRITICAL FIX: Set trigger time and loading state atomically to prevent duplicates
                        lastOlderMessagesLoadTriggerTime = Date()
                        isLoadingMore = true
                        
                        // MEMORY MANAGEMENT: Cleanup before loading if we're over limit
                        // CRITICAL FIX: When loading older messages, keep the most recent (latest) messages
                        // Don't trim the latest messages - we want to preserve them!
                        if localMessages.count > Int(Double(MessageableChannelConstants.maxMessagesInMemory) * 1.2) {
                            enforceMessageWindow(keepingMostRecent: true)
                        }
                        
                        // Show loading indicator immediately (only if not already showing)
                        DispatchQueue.main.async {
                            // Add header if not already added
                            if self.tableView.tableHeaderView == nil {
                                self.tableView.tableHeaderView = self.loadingHeaderView
                            }
                            // Only show if not already visible to prevent jumping
                            if self.loadingHeaderView.isHidden {
                                self.loadingHeaderView.isHidden = false
                            }
                        }
                        
                        // Load older messages
                        loadMoreMessages(before: firstMessageId)
                    }
                }
            }
        }
        
        // INFINITE SCROLL DOWN: Check if user is near bottom to load newer messages
        if scrollView == tableView {
            let contentHeight = scrollView.contentSize.height
            let offsetY = scrollView.contentOffset.y
            let frameHeight = scrollView.frame.size.height
            let distanceFromBottom = contentHeight - (offsetY + frameHeight)
            let channelLastMessageId = viewModel.channel.last_message_id
            let ourLastMessageId = localMessages.last
            let isMissingLatest = channelLastMessageId != nil && channelLastMessageId != ourLastMessageId
            
            // CRITICAL FIX: Throttle scroll event logging to reduce excessive logs (max once per 100ms)
            let shouldLog = lastScrollLogTime == nil || Date().timeIntervalSince(lastScrollLogTime!) >= 0.1
            if shouldLog {
                lastScrollLogTime = Date()
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: [
                    "filter": "SCROLL_DOWN",
                    "action": "scrollViewDidScroll_check",
                    "localMessagesCount": localMessages.count,
                    "distanceFromBottom": distanceFromBottom,
                    "isNearBottom": distanceFromBottom <= 100,
                    "lastMessageId": ourLastMessageId ?? "nil",
                    "channelLastMessageId": channelLastMessageId ?? "nil",
                    "isMissingLatest": isMissingLatest,
                    "isLoadingMore": isLoadingMore,
                    "isDragging": scrollView.isDragging,
                    "isDecelerating": scrollView.isDecelerating,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("MESSAGE_SCROLLING: \(jsonString)")
                }
            }
            
            detectScrollToBottomForLoadingMore()
        }
        
        // Update lastScrollOffset for tracking scroll direction
        lastScrollOffset = scrollView.contentOffset.y
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Stop scroll protection after deceleration ends
        scrollProtectionTimer?.invalidate()
        scrollProtectionTimer = nil

        handleScrollEndForReplyPrefetch()
        
        // CRITICAL FIX: Check if we're at bottom and missing latest messages when scrolling stops
        if scrollView == tableView {
            let contentHeight = scrollView.contentSize.height
            let offsetY = scrollView.contentOffset.y
            let frameHeight = scrollView.frame.size.height
            let distanceFromBottom = contentHeight - (offsetY + frameHeight)
            
            // If we're very close to bottom (within 50 points), check for missing latest messages
            if distanceFromBottom <= 50 && !isLoadingMore && !localMessages.isEmpty {
                let channelLastMessageId = viewModel.channel.last_message_id
                let ourLastMessageId = localMessages.last
                let isMissingLatestMessages = channelLastMessageId != nil && channelLastMessageId != ourLastMessageId
                
                if isMissingLatestMessages, let lastMessageId = localMessages.last {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: [
                        "filter": "SCROLL_DOWN",
                        "action": "scrollViewDidEndDecelerating_missing_latest",
                        "channelLastMessageId": channelLastMessageId ?? "nil",
                        "ourLastMessageId": ourLastMessageId ?? "nil",
                        "distanceFromBottom": distanceFromBottom,
                        "willCallLoadNewerMessages": true,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        print("MESSAGE_SCROLLING: \(jsonString)")
                    }
                    
                    loadNewerMessages(after: lastMessageId)
                }
            }
        }
    }
    
    // MARK: - Scroll Helper Methods
    
    private func detectScrollToBottomForLoadingMore() {
        let channelLastMessageId = viewModel.channel.last_message_id
        let ourLastMessageId = localMessages.last
        let isMissingLatest = channelLastMessageId != nil && channelLastMessageId != ourLastMessageId
        
        // CRITICAL FIX: Throttle logging to reduce excessive logs (only log important events)
        let shouldLog = lastScrollLogTime == nil || Date().timeIntervalSince(lastScrollLogTime!) >= 0.1
        
        if shouldLog {
            if let jsonData = try? JSONSerialization.data(withJSONObject: [
                "filter": "SCROLL_DOWN",
                "action": "detectScrollToBottomForLoadingMore_start",
                "localMessagesCount": localMessages.count,
                "isLoadingMore": isLoadingMore,
                "isEmpty": localMessages.isEmpty,
                "lastMessageId": ourLastMessageId ?? "nil",
                "channelLastMessageId": channelLastMessageId ?? "nil",
                "isMissingLatest": isMissingLatest,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("MESSAGE_SCROLLING: \(jsonString)")
            }
        }
        
        // CRITICAL FIX: Don't require 200 messages when scrolling back down near bottom
        // After window trimming, we might have fewer messages but still need to reload latest
        guard !isLoadingMore && !localMessages.isEmpty else { 
            // Only log guard failures if not throttled
            if shouldLog {
                if let jsonDataGuard = try? JSONSerialization.data(withJSONObject: [
                    "filter": "SCROLL_DOWN",
                    "action": "detectScrollToBottomForLoadingMore_guard_failed",
                    "isLoadingMore": isLoadingMore,
                    "isEmpty": localMessages.isEmpty,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]),
                   let jsonStringGuard = String(data: jsonDataGuard, encoding: .utf8) {
                    print("MESSAGE_SCROLLING: \(jsonStringGuard)")
                }
            }
            return 
        }
        
        let contentHeight = tableView.contentSize.height
        let offsetY = tableView.contentOffset.y
        let frameHeight = tableView.frame.size.height
        
        // Check if user is very close to the bottom (within 100 points)
        let distanceFromBottom = contentHeight - (offsetY + frameHeight)
        
        // Only log distance check if not throttled
        if shouldLog {
            if let jsonDataDistance = try? JSONSerialization.data(withJSONObject: [
                "filter": "SCROLL_DOWN",
                "action": "detectScrollToBottomForLoadingMore_distance_check",
                "distanceFromBottom": distanceFromBottom,
                "isNearBottom": distanceFromBottom <= 100,
                "contentHeight": contentHeight,
                "offsetY": offsetY,
                "frameHeight": frameHeight,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]),
               let jsonStringDistance = String(data: jsonDataDistance, encoding: .utf8) {
                print("MESSAGE_SCROLLING: \(jsonStringDistance)")
            }
        }
        
        // CRITICAL FIX: Only load newer messages if:
        // 1. User is actually near the bottom (distanceFromBottom >= 0, not negative)
        // 2. User is scrolling down (not up) - check if current offset is greater than last
        // 3. User hasn't recently scrolled up (within last 2 seconds)
        // Negative distanceFromBottom means user has scrolled past bottom (likely scrolling up to load older messages)
        let isScrollingDown = offsetY > lastScrollOffset
        let isActuallyNearBottom = distanceFromBottom >= 0 && distanceFromBottom <= 100
        let hasRecentlyScrolledUp = lastManualScrollUpTime != nil && 
                                   Date().timeIntervalSince(lastManualScrollUpTime!) < 2.0
        
        if isActuallyNearBottom && isScrollingDown && !hasRecentlyScrolledUp {
            // User is near bottom and scrolling down - check if we should load newer messages
            // CRITICAL FIX: Always reload latest messages when near bottom, even if count < 200
            // This ensures we restore messages that were trimmed when scrolling up
            
            // If channel has a last_message_id and it doesn't match ours, we're missing latest messages
            let isMissingLatestMessages = channelLastMessageId != nil && channelLastMessageId != ourLastMessageId
            
            if let lastMessageId = localMessages.last {
                // CRITICAL FIX: Always reload if we're missing latest messages OR if we have fewer than 200 messages
                // This ensures we restore messages that were trimmed when scrolling up
                if isMissingLatestMessages || localMessages.count < 200 {
                    if let jsonData2 = try? JSONSerialization.data(withJSONObject: [
                        "filter": "SCROLL_DOWN",
                        "action": "detectScrollToBottomForLoadingMore_trigger",
                        "lastMessageId": lastMessageId,
                        "distanceFromBottom": distanceFromBottom,
                        "localMessagesCount": localMessages.count,
                        "isMissingLatestMessages": isMissingLatestMessages,
                        "channelLastMessageId": channelLastMessageId ?? "nil",
                        "willCallLoadNewerMessages": true,
                        "isScrollingDown": isScrollingDown,
                        "isActuallyNearBottom": isActuallyNearBottom,
                        "offsetY": offsetY,
                        "lastScrollOffset": lastScrollOffset,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]),
                       let jsonString2 = String(data: jsonData2, encoding: .utf8) {
                        print("MESSAGE_SCROLLING: \(jsonString2)")
                    }
                    
                    // print("📥 SCROLL DOWN: User near bottom, loading newer messages after ID: \(lastMessageId)")
                    loadNewerMessages(after: lastMessageId)
                } else {
                    if let jsonDataSkip = try? JSONSerialization.data(withJSONObject: [
                        "filter": "SCROLL_DOWN",
                        "action": "detectScrollToBottomForLoadingMore_skip",
                        "reason": "notMissingLatestAndCount>=200",
                        "isMissingLatestMessages": isMissingLatestMessages,
                        "localMessagesCount": localMessages.count,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]),
                       let jsonStringSkip = String(data: jsonDataSkip, encoding: .utf8) {
                        print("MESSAGE_SCROLLING: \(jsonStringSkip)")
                    }
                }
            } else if isMissingLatestMessages && isActuallyNearBottom && isScrollingDown {
                // CRITICAL FIX: If we have no messages but channel has latest, reload from scratch
                if let jsonData3 = try? JSONSerialization.data(withJSONObject: [
                    "filter": "SCROLL_DOWN",
                    "action": "detectScrollToBottomForLoadingMore_reload_initial",
                    "channelLastMessageId": channelLastMessageId ?? "nil",
                    "localMessagesEmpty": localMessages.isEmpty,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]),
                   let jsonString3 = String(data: jsonData3, encoding: .utf8) {
                    print("MESSAGE_SCROLLING: \(jsonString3)")
                }
                
                Task {
                    await loadInitialMessages()
                }
            } else {
                // Log why we're skipping loading newer messages
                if let jsonDataSkip = try? JSONSerialization.data(withJSONObject: [
                    "filter": "SCROLL_DOWN",
                    "action": "detectScrollToBottomForLoadingMore_skip_conditions",
                    "isActuallyNearBottom": isActuallyNearBottom,
                    "isScrollingDown": isScrollingDown,
                    "hasRecentlyScrolledUp": hasRecentlyScrolledUp,
                    "distanceFromBottom": distanceFromBottom,
                    "offsetY": offsetY,
                    "lastScrollOffset": lastScrollOffset,
                    "lastManualScrollUpTime": lastManualScrollUpTime?.timeIntervalSince1970 ?? 0,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]),
                   let jsonStringSkip = String(data: jsonDataSkip, encoding: .utf8) {
                    print("MESSAGE_SCROLLING: \(jsonStringSkip)")
                }
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
        print("🔍 SCROLL_TO_BOTTOM: Called with animated: \(animated)")
        debugTargetMessageProtection()
        
        guard !localMessages.isEmpty else { 
            print("🚫 SCROLL_TO_BOTTOM: No messages, returning")
            return 
        }
        
        // SIMPLIFIED TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            print("🎯 scrollToBottom: Target message protection active, blocking auto-scroll")
            print("🎯 Protection details - targetMessageId: \(targetMessageId != nil), isInPosition: \(isInTargetMessagePosition), processed: \(targetMessageProcessed)")
            return
        }
        
        // ADDITIONAL SAFEGUARD: Double-check that we're not in the middle of target message operations
        if let targetId = targetMessageId {
            print("🛡️ scrollToBottom: Additional check - target message \(targetId) still exists, blocking scroll")
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
            
            let lastIndex = self.localMessages.count - 1
            let indexPath = IndexPath(row: lastIndex, section: 0)
            
            // Check if the index path is valid
            guard lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) else {
                // print("📊 SCROLL_TO_BOTTOM: Invalid index path \(indexPath)")
                return
            }
            
            // Always use .bottom positioning when keyboard is visible
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
            
            // For keyboard visible state, do an extra scroll after animation
            if self.isKeyboardVisible && animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
                    // print("📊 SCROLL_TO_BOTTOM: Extra scroll for keyboard visibility")
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
