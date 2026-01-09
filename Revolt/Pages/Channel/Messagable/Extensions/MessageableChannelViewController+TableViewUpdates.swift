//
//  MessageableChannelViewController+TableViewUpdates.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//  Phase 3: Medium-Risk Extensions - Table View Updates

import UIKit

// MARK: - Table View Updates
extension MessageableChannelViewController {
    
    // MARK: - Refresh Messages
    
    /// FAST: Lightweight refresh method with minimal overhead
    func refreshMessages(forceUpdate: Bool = false) {
        print("🔄 targetMessageProtectionActive: \(targetMessageProtectionActive)")
        
        // CRITICAL FIX: Don't refresh if we're in the middle of nearby loading (unless forced for reactions)
        if messageLoadingState == .loading && !forceUpdate {
            print("🔄 BLOCKED: refreshMessages blocked - nearby loading in progress")
            return
        }
        
        // CRITICAL FIX: Only block if protection is active AND we don't have a new target message to process (unless forced for reactions)
        if targetMessageProtectionActive && (targetMessageId == nil || targetMessageProcessed) && !forceUpdate {
            print("🔄 BLOCKED: refreshMessages blocked - target message protection active and no new target")
            return
        }
        
        // Skip if user is interacting with table
        guard !tableView.isDragging, !tableView.isDecelerating else { 
            // print("🔄 Skipping refreshMessages - user is interacting with table")
            return 
        }
        
        // Skip if user recently scrolled up, BUT NOT if we have a target message
        if let lastScrollUpTime = lastManualScrollUpTime,
           Date().timeIntervalSince(lastScrollUpTime) < 10.0,
           targetMessageId == nil { 
            // print("🔄 Skipping refreshMessages - user recently scrolled up (no target message)")
            return 
        } else if targetMessageId != nil {
            // print("🔄 Continuing refreshMessages despite recent scroll - have target message")
        }
        
        // Get new messages directly - no async overhead
        guard let channelMessages = viewModel.viewState.channelMessages[viewModel.channel.id],
              !channelMessages.isEmpty,
              localMessages != channelMessages else { return }
        
        // CRITICAL: Check if actual message objects exist before refreshing
        let hasActualMessages = channelMessages.first(where: { viewModel.viewState.messages[$0] != nil }) != nil
        if !hasActualMessages {
            // print("⚠️ refreshMessages: Only message IDs found, no actual messages - need to load messages")
            
            // CRITICAL FIX: Don't force reload if target message protection is active (unless forced for reactions)
            if targetMessageProtectionActive && !forceUpdate {
                print("🔄 BLOCKED: Force reload blocked - target message protection active")
                return
            }
            
            // Hide table and show loading spinner
            tableView.alpha = 0.0
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            tableView.tableFooterView = spinner
            
            // Force load messages if we only have IDs
            Task {
                await loadInitialMessages()
            }
            return
        }
        
        let wasNearBottom = isUserNearBottom()
        let oldLastMessageId = localMessages.last
        localMessages = channelMessages
        let newLastMessageId = localMessages.last
        let channelLastMessageId = viewModel.channel.last_message_id
        
        if let jsonDataBeforeReload = try? JSONSerialization.data(withJSONObject: [
            "filter": "REFRESH",
            "action": "refreshMessages_before_reload",
            "oldLastMessageId": oldLastMessageId ?? "nil",
            "newLastMessageId": newLastMessageId ?? "nil",
            "channelLastMessageId": channelLastMessageId ?? "nil",
            "localMessagesCount": localMessages.count,
            "wasNearBottom": wasNearBottom,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]),
           let jsonStringBeforeReload = String(data: jsonDataBeforeReload, encoding: .utf8) {
            print("MESSAGE_SCROLLING: \(jsonStringBeforeReload)")
        }
        
        // CRITICAL: Mark data source as updating to protect scroll events
        isDataSourceUpdating = true
        print("📊 DATA_SOURCE: Marking as updating before table reload")
        
        // FAST: Update existing data source if possible
        if let existingDataSource = dataSource as? LocalMessagesDataSource {
            existingDataSource.updateMessages(localMessages)
        } else {
            // Only create new data source if needed
            dataSource = LocalMessagesDataSource(viewModel: viewModel, viewController: self, localMessages: localMessages)
            tableView.dataSource = dataSource
        }
        
        // FAST: Single reload operation
        tableView.reloadData()
        
        if let jsonDataAfterReload = try? JSONSerialization.data(withJSONObject: [
            "filter": "REFRESH",
            "action": "refreshMessages_after_reload",
            "tableViewRows": tableView.numberOfRows(inSection: 0),
            "localMessagesCount": localMessages.count,
            "lastMessageId": localMessages.last ?? "nil",
            "channelLastMessageId": channelLastMessageId ?? "nil",
            "matchesChannelLatest": localMessages.last == channelLastMessageId,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]),
           let jsonStringAfterReload = String(data: jsonDataAfterReload, encoding: .utf8) {
            print("MESSAGE_SCROLLING: \(jsonStringAfterReload)")
        }
        
        // CRITICAL: Reset flag after reload with slight delay to prevent immediate scroll conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isDataSourceUpdating = false
            print("📊 DATA_SOURCE: Marking as stable after table reload")
        }
        
        // Update table view bouncing behavior after refresh
        updateTableViewBouncing()
        
        // CRITICAL FIX: Check if we need to fetch reply content for newly loaded messages
        // Only check if we have messages and table view is visible, and not loading
        if !localMessages.isEmpty && tableView.alpha > 0 && messageLoadingState == .notLoading {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await self.checkAndFetchMissingReplies()
            }
        }
        
        // CRITICAL FIX: Check for target message after reload - ONLY call scrollToTargetMessage ONCE
        if let targetId = targetMessageId, !targetMessageProcessed {
            print("🎯 Found unprocessed targetMessageId in refreshMessages: \(targetId)")
            print("🎯 localMessages count: \(localMessages.count)")
            
            // Check if target message is actually loaded
            let targetInLocalMessages = localMessages.contains(targetId)
            let targetInViewState = viewModel.viewState.messages[targetId] != nil
            
            if targetInLocalMessages && targetInViewState {
                print("✅ Target message is loaded in refreshMessages, calling scrollToTargetMessage ONCE")
                // Mark as processed BEFORE calling scrollToTargetMessage to prevent multiple calls
                targetMessageProcessed = true
                scrollToTargetMessage()
            } else {
                print("❌ Target message NOT loaded in refreshMessages, skipping scroll")
            }
        } else if let targetId = targetMessageId, targetMessageProcessed {
            print("🎯 Found targetMessageId but already processed: \(targetId) - preserving target position")
            // CRITICAL FIX: Do NOT auto-scroll when we have a target message
            // The target message should remain visible regardless of bottom position
        } else if wasNearBottom {
            // CRITICAL FIX: Don't auto-scroll if user was positioned on a target message recently
            if targetMessageProtectionActive || isInTargetMessagePosition {
                print("🎯 REFRESH_MESSAGES: Target message protection or position active, skipping auto-scroll")
                return
            }
            
            // CRITICAL FIX: Don't auto-scroll if target message was highlighted recently (within 30 seconds)
            if let highlightTime = lastTargetMessageHighlightTime,
               Date().timeIntervalSince(highlightTime) < 30.0 {
                print("🎯 REFRESH_MESSAGES: Target message highlighted recently (\(Date().timeIntervalSince(highlightTime))s ago), skipping auto-scroll")
                return
            }
            
            // Auto-scroll if user was at bottom and no target message protection
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                print("🎯 REFRESH_MESSAGES: Auto-scrolling because user was near bottom and no target protection")
                
                // Use proper scrolling method that considers keyboard state
                if self.isKeyboardVisible && !self.localMessages.isEmpty {
                    let lastIndex = self.localMessages.count - 1
                    if lastIndex >= 0 && lastIndex < self.tableView.numberOfRows(inSection: 0) {
                        let indexPath = IndexPath(row: lastIndex, section: 0)
                        self.safeScrollToRow(at: indexPath, at: .bottom, animated: false, reason: "refresh messages with keyboard")
                    }
                } else {
                    self.scrollToBottom(animated: false)
                }
            }
        }
        
        updateEmptyStateVisibility()
    }
    
    // MARK: - Enforce Message Window
    
    @MainActor
    func enforceMessageWindow(keepingMostRecent: Bool) {
        // CRITICAL FIX: When loading older messages, always keep the most recent messages
        // Never trim the latest messages when we're in the process of loading older messages
        if isLoadingOlderMessages && !keepingMostRecent {
            print("🛡️ WINDOW_TRIM: Blocked trimming latest messages while loading older messages - forcing keepingMostRecent: true")
            // Force keepingMostRecent to true to preserve latest messages
            // Don't return early - we still need to trim if over limit, just keep the most recent
        }
        
        let channelId = viewModel.channel.id
        let currentIds = viewModel.viewState.channelMessages[channelId] ?? localMessages
        let maxCount = MessageableChannelConstants.maxMessagesInMemory
        let channelLastMessageId = viewModel.channel.last_message_id
        
        // CRITICAL FIX: If we're loading older messages, always keep most recent regardless of parameter
        let shouldKeepMostRecent = isLoadingOlderMessages ? true : keepingMostRecent
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: [
            "filter": "WINDOW_TRIM",
            "action": "enforceMessageWindow_start",
            "keepingMostRecent": shouldKeepMostRecent,
            "originalKeepingMostRecent": keepingMostRecent,
            "isLoadingOlderMessages": isLoadingOlderMessages,
            "channelId": channelId,
            "currentCount": currentIds.count,
            "maxCount": maxCount,
            "channelLastMessageId": channelLastMessageId ?? "nil",
            "currentLastMessageId": currentIds.last ?? "nil",
            "willTrim": currentIds.count > maxCount,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("MESSAGE_SCROLLING: \(jsonString)")
        }
        
        guard currentIds.count > maxCount else { return }
        
        // Calculate which messages to keep/remove (lightweight operation, can stay on main thread)
        // CRITICAL FIX: Use shouldKeepMostRecent to ensure we never trim latest when loading older messages
        let kept = shouldKeepMostRecent
            ? Array(currentIds.suffix(maxCount))
            : Array(currentIds.prefix(maxCount))
        guard kept.count < currentIds.count else { return }
        
        let keptSet = Set(kept)
        let removedIds = currentIds.filter { !keptSet.contains($0) }
        
        if let jsonData2 = try? JSONSerialization.data(withJSONObject: [
            "filter": "WINDOW_TRIM",
            "action": "enforceMessageWindow_result",
            "keptCount": kept.count,
            "removedCount": removedIds.count,
            "keptFirst": kept.first ?? "nil",
            "keptLast": kept.last ?? "nil",
            "removedFirst": removedIds.first ?? "nil",
            "removedLast": removedIds.last ?? "nil",
            "keepingMostRecent": shouldKeepMostRecent,
            "originalKeepingMostRecent": keepingMostRecent,
            "isLoadingOlderMessages": isLoadingOlderMessages,
            "channelLastMessageId": channelLastMessageId ?? "nil",
            "keptLastMatchesChannel": kept.last == channelLastMessageId,
            "removedContainsLatest": removedIds.contains(where: { $0 == channelLastMessageId }),
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]),
           let jsonString2 = String(data: jsonData2, encoding: .utf8) {
            print("MESSAGE_SCROLLING: \(jsonString2)")
        }
        
        // MEMORY MANAGEMENT: Remove messages from dictionary off-main-thread to prevent UI hitches
        if !removedIds.isEmpty {
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                // Remove messages off-main-thread
                await MainActor.run {
                    for messageId in removedIds {
                        self.viewModel.viewState.messages.removeValue(forKey: messageId)
                    }
                }
            }
        }
        
        // Update UI immediately on main thread (synchronous updates for responsiveness)
        viewModel.viewState.channelMessages[channelId] = kept
        viewModel.messages = kept
        localMessages = kept
        
        if let localDataSource = dataSource as? LocalMessagesDataSource {
            localDataSource.updateMessages(kept)
        }
        
        let trimDirection = shouldKeepMostRecent ? "mostRecent" : "oldest"
        print("🛡️ WINDOW_TRIM: Trimmed \(removedIds.count) \(trimDirection) messages, kept \(kept.count) messages")
    }
    
    // MARK: - Table View Insets and Bouncing
    
    /// Method to adjust table insets based on message count
    func adjustTableInsetsForMessageCount() {
        // Safety check - make sure table view is loaded
        guard tableView != nil, tableView.window != nil else {
            // print("⚠️ Table view not ready for inset adjustment")
            return
        }
        
        // CRITICAL FIX: Don't adjust insets during target message operations
        if targetMessageProtectionActive {
            print("📏 BLOCKED: Inset adjustment blocked - target message protection active")
            return
        }
        
        // Get the current number of messages
        let messageCount = tableView.numberOfRows(inSection: 0)
        
        // If no messages, don't adjust insets
        guard messageCount > 0 else {
            // print("📏 No messages to adjust insets for")
            // Disable bouncing for empty state
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            // Remove header to prevent scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            return
        }
        
        // JUMPING FIX: Implement cooldown to prevent excessive calls
        let now = Date()
        let timeSinceLastAdjustment = now.timeIntervalSince(lastInsetAdjustmentTime)
        
        // Skip if called too recently AND message count hasn't changed significantly
        if timeSinceLastAdjustment < insetAdjustmentCooldown && 
           abs(messageCount - lastMessageCountForInsets) <= 1 {
            // print("📏 COOLDOWN: Skipping inset adjustment (called \(timeSinceLastAdjustment)s ago, count change: \(abs(messageCount - lastMessageCountForInsets)))")
            return
        }
        
        // Update tracking variables
        lastInsetAdjustmentTime = now
        lastMessageCountForInsets = messageCount
        
        // CRITICAL FIX: For very few messages (under 10), just update bouncing
        // Don't use contentInset for positioning - it causes scrolling issues
        if messageCount <= 10 {
            // Just update bouncing behavior
            updateTableViewBouncing()
            // print("📏 Updated bouncing for \(messageCount) messages")
            return
        }
        
        // Improvement: Increased message threshold for better user experience - apply spacing for up to 15 messages
        if messageCount > 15 {
            // If we have more than 15 messages, remove the spacing
            if tableView.contentInset.top > 0 {
                UIView.animate(withDuration: 0.2) {
                    self.tableView.contentInset = UIEdgeInsets.zero
                }
                // print("📏 Reset insets to zero (message count > 15)")
            }
            // Enable bouncing for many messages
            tableView.alwaysBounceVertical = true
            tableView.bounces = true
            return
        }
        
        // For messages between 11-15, calculate spacing more carefully
        
        // Calculate the visible height of the table
        let visibleHeight = tableView.bounds.height
        
        // Calculate the total height of all cells with error handling
        var totalCellHeight: CGFloat = 0
        
        for i in 0..<messageCount {
            let indexPath = IndexPath(row: i, section: 0)
            // Add safety check for rect calculation
            guard indexPath.row < tableView.numberOfRows(inSection: 0) else {
                // print("⚠️ Index path out of bounds: \(indexPath)")
                break
            }
            let rowHeight = tableView.rectForRow(at: indexPath).height
            totalCellHeight += rowHeight
        }
        
        // print("📏 ADJUST_TABLE_INSETS: visibleHeight=\(visibleHeight), totalCellHeight=\(totalCellHeight), messageCount=\(messageCount)")
        
        // Just update bouncing behavior for medium message counts
        updateTableViewBouncing()
        
        // print("📊 Medium message count (\(messageCount)), inset adjustment complete")
    }
    
    // MARK: - Helper method to update table view bouncing behavior
    internal func updateTableViewBouncing() {
        // First check if table view is ready
        guard tableView.window != nil else { return }
        
        // CRITICAL FIX: Don't update bouncing during target message operations
        if targetMessageProtectionActive {
            print("📏 BOUNCE_BLOCKED: Bouncing update blocked - target message protection active")
            return
        }
        
        let rowCount = tableView.numberOfRows(inSection: 0)
        
        // If no rows, disable scrolling completely
        guard rowCount > 0 else {
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            // Remove header to prevent scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            print("📏 Disabled scrolling - no messages")
            return
        }
        
        // Calculate actual content height by summing row heights
        var actualContentHeight: CGFloat = 0
        for i in 0..<rowCount {
            let indexPath = IndexPath(row: i, section: 0)
            actualContentHeight += tableView.rectForRow(at: indexPath).height
        }
        
        // Add header/footer heights only if they are visible
        if let header = tableView.tableHeaderView, !header.isHidden {
            actualContentHeight += header.frame.height
        }
        if let footer = tableView.tableFooterView, !footer.isHidden {
            actualContentHeight += footer.frame.height
        }
        
        // Calculate visible height
        let visibleHeight = tableView.bounds.height - keyboardHeight
        
        // Be very strict - only enable scrolling if content truly exceeds visible area
        let shouldEnableScrolling = actualContentHeight > visibleHeight + 10 // 10px margin
        
        // Force update scrolling and bouncing settings
        if shouldEnableScrolling {
            tableView.isScrollEnabled = true
            tableView.alwaysBounceVertical = true
            tableView.bounces = true
            tableView.showsVerticalScrollIndicator = true
            
            // Re-add header only if it was removed AND we are loading
            if tableView.tableHeaderView == nil && isLoadingMore {
                tableView.tableHeaderView = loadingHeaderView
            }
            
        } else {
            // Completely disable scrolling when content fits
            tableView.isScrollEnabled = false
            tableView.alwaysBounceVertical = false
            tableView.bounces = false
            tableView.showsVerticalScrollIndicator = false
            // CRITICAL: Remove all content insets when scrolling is disabled
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            
            // Remove header to prevent any scrolling
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            
            // CRITICAL FIX: Don't reset scroll position during target message operations
            if !targetMessageProtectionActive {
                // Reset scroll position to top
                tableView.contentOffset = .zero
            }
            
            print("📏 Disabled scrolling completely - actual content: \(actualContentHeight), visible: \(visibleHeight), rows: \(rowCount)")
        }
    }
}
