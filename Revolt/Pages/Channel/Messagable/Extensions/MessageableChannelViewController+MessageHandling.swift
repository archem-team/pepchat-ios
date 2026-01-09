//
//  MessageableChannelViewController+MessageHandling.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit
import Types

// MARK: - Message Handling (Notification Handlers)
extension MessageableChannelViewController {
    
    // MARK: - Notification Handlers
    
    /// Handle messagesDidChange notification with debouncing and reaction update support
    @objc func messagesDidChange(_ notification: Notification) {
        // Debounce rapid notifications
        let now = Date()
        guard now.timeIntervalSince(lastMessageChangeNotificationTime) >= 0.1 else { return }
        lastMessageChangeNotificationTime = now
        
        // Check if this is a reaction update
        var isReactionUpdate = false
        var reactionChannelId: String? = nil
        var reactionMessageId: String? = nil
        
        if let notificationData = notification.object as? [String: Any] {
            reactionChannelId = notificationData["channelId"] as? String
            reactionMessageId = notificationData["messageId"] as? String
            let updateType = notificationData["type"] as? String
            isReactionUpdate = updateType == "reaction_added" || updateType == "reaction_removed"
        }
        
        // For reaction updates, handle them immediately without blocking conditions
        if isReactionUpdate {
            print("🔥 CONTROLLER: Processing reaction update for channel \(reactionChannelId ?? "unknown"), message \(reactionMessageId ?? "unknown")")
            // Process reaction updates immediately since they don't interfere with loading states
            // and should always update the UI when received from the backend
        } else {
            // CRITICAL FIX: Don't process regular message changes during nearby loading
            if messageLoadingState == .loading {
                print("🔄 BLOCKED: messagesDidChange blocked - nearby loading in progress")
                return
            }
            
            // CRITICAL FIX: Don't process regular message changes if target message protection is active
            if targetMessageProtectionActive {
                print("🔄 BLOCKED: messagesDidChange blocked - target message protection active")
                return
            }
        }
        
        // For reaction updates, check if it's for this channel
        if isReactionUpdate {
            guard let channelId = reactionChannelId, channelId == viewModel.channel.id else { return }
            if let messageId = reactionMessageId,
               let messageIndex = localMessages.firstIndex(of: messageId),
               messageIndex < tableView.numberOfRows(inSection: 0) {

                let indexPath = IndexPath(row: messageIndex, section: 0)
                let isLastMessage = messageIndex == localMessages.count - 1
                let wasNearBottom = isUserNearBottom(threshold: 80)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("🔥 RELOADING ROW: Reloading row \(indexPath.row) for message \(messageId)")
                    
                    // Force check if message has been updated in ViewState
                    if let updatedMessage = self.viewModel.viewState.messages[messageId] {
                        print("🔥 FORCE CHECK: Message \(messageId) reactions in ViewState: \(updatedMessage.reactions?.keys.joined(separator: ", ") ?? "none")")
                    } else {
                        print("🔥 FORCE CHECK: Message \(messageId) not found in ViewState!")
                    }
                    
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    self.tableView.layoutIfNeeded()

                    // CRITICAL FIX: Don't auto-scroll if target message was recently highlighted
                    if let highlightTime = self.lastTargetMessageHighlightTime,
                       Date().timeIntervalSince(highlightTime) < 10.0 {
                        return
                    }

                    // Only if last message and user is at bottom, check if it went under keyboard
                    if isLastMessage && wasNearBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard let cellRect = self.tableView.cellForRow(at: indexPath)?.frame else { return }
                            let visibleHeight = self.tableView.frame.height - (self.isKeyboardVisible ? self.keyboardHeight : 0)
                            let cellBottom = cellRect.maxY - self.tableView.contentOffset.y
                            if cellBottom > visibleHeight {
                                // If cell bottom is below visible area, scroll to show it completely
                                let targetOffset = max(cellRect.maxY - visibleHeight + 20, 0)
                                self.tableView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
                            }
                        }
                    }
                }
            } else {
                refreshMessages(forceUpdate: true) // Force update for reactions
            }
            return
        }
        
        // Skip if wrong channel (for regular message updates)
        if let sender = notification.object as? MessageableChannelViewModel,
           sender.channel.id != viewModel.channel.id { return }
        
        // Skip if no actual change (for regular message updates)
        let newCount = viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0
        guard newCount != lastKnownMessageCount else { return }
        lastKnownMessageCount = newCount
        
        // Skip if user is scrolling (for regular message updates)
        guard !tableView.isDragging, !tableView.isDecelerating else { return }
        
        // Use lightweight refresh
        refreshMessages()
    }
    
    /// Handle new messages notification - only scroll if user is near bottom
    @objc func handleNewMessages(_ notification: Notification) {
        // CRITICAL FIX: Don't handle new messages during nearby loading
        if messageLoadingState == .loading {
            print("📬 BLOCKED: handleNewMessages blocked - nearby loading in progress")
            return
        }
        
        // CRITICAL FIX: Don't handle if target message protection is active
        if targetMessageProtectionActive {
            print("📬 BLOCKED: handleNewMessages blocked - target message protection active")
            return
        }
        
        let currentMessageCount = viewModel.messages.count
        let storedMessageCount = UserDefaults.standard.integer(forKey: "LastMessageCount_\(viewModel.channel.id)")
        
        // Only scroll if there are actual new messages
        if currentMessageCount > storedMessageCount {
            // print("📬 Direct notification of new messages - found \(currentMessageCount - storedMessageCount) new messages")
            // Update stored count
            UserDefaults.standard.set(currentMessageCount, forKey: "LastMessageCount_\(viewModel.channel.id)")
            
            // Check if user has manually scrolled up recently
            let hasManuallyScrolledUp = lastManualScrollUpTime != nil && 
                                       Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0
            
            // COMPREHENSIVE TARGET MESSAGE PROTECTION
            // Only scroll if user is near bottom AND hasn't manually scrolled up recently AND no target message protection
            if isUserNearBottom() && !hasManuallyScrolledUp && !targetMessageProtectionActive {
                // First scroll immediately
                scrollToBottom(animated: true)
                // Then schedule multiple scrolls with delays to ensure we catch the UI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.scrollToBottom(animated: true)
                    // One more scroll after a bit longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.scrollToBottom(animated: false)
                    }
                }
            } else {
                // print("👆 User is not near bottom or has manually scrolled up, not auto-scrolling")
                // Do NOT show new message button here anymore
                // showNewMessageButton() // <-- REMOVE THIS LINE
            }
        } else {
            // print("📬 Message notification received but no new messages found. Ignoring scroll request.")
        }
    }
    
    /// Handle new socket message - show new message button if user is not at bottom
    @objc func handleNewSocketMessage(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let channelId = userInfo["channelId"] as? String,
              channelId == viewModel.channel.id else { return }
        
        // print debug info for socket message
        // print("🔔 SOCKET: Received socket message for channel \(channelId)")
        
        let hasManuallyScrolledUp = lastManualScrollUpTime != nil &&
                                    Date().timeIntervalSince(lastManualScrollUpTime!) < 10.0
        
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if !isUserNearBottom() || hasManuallyScrolledUp || targetMessageProtectionActive {
            // This is the ONLY place where showNewMessageButton should be called
            showNewMessageButton()
            // print("🔔 SOCKET: Showing new message button because user is not at bottom or target highlighted")
        } else {
            // print("🔔 SOCKET: User is at bottom, auto-scrolling instead of showing button")
            // Use proper scrolling method that considers keyboard state
            if isKeyboardVisible && !localMessages.isEmpty {
                let lastIndex = localMessages.count - 1
                if lastIndex >= 0 && lastIndex < tableView.numberOfRows(inSection: 0) {
                    let indexPath = IndexPath(row: lastIndex, section: 0)
                    safeScrollToRow(at: indexPath, at: .bottom, animated: true, reason: "socket message with keyboard")
                }
            } else {
                scrollToBottom(animated: true)
            }
        }
    }
    
    /// Handle network error notification - prevent automatic scrolls temporarily
    @objc func handleNetworkError(_ notification: Notification) {
        // print("⚠️ Network error detected, preventing automatic scrolls for 5 seconds")
        
        // Temporarily increase the debounce time after network error
        let errorDebounceTime = Date().addingTimeInterval(5.0)
        lastScrollToBottomTime = errorDebounceTime
        
        // Block new message notifications from causing scrolls for a while
        UserDefaults.standard.set(viewModel.messages.count, forKey: "LastMessageCount_\(viewModel.channel.id)")
    }
    
    /// Handle channel search closed notification - detect returning from search
    @objc func handleChannelSearchClosed(_ notification: Notification) {
        // Check if the notification is for this channel
        guard let channelId = notification.object as? String,
              channelId == viewModel.channel.id else {
            return
        }
        
        // Set flag to prevent unwanted scrolling when returning from search
        isReturningFromSearch = true
        wasInSearch = false
        // print("🔍 SEARCH_CLOSED: Channel search closed for channel \(channelId), setting flag to prevent scroll")
        
        // Reset the flag after a short delay to ensure it doesn't interfere with future navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isReturningFromSearch = false
        }
    }
    
    /// Handle channel search closing notification - detect returning from search
    @objc func handleChannelSearchClosing(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let channelId = userInfo["channelId"] as? String,
              let isReturning = userInfo["isReturning"] as? Bool else {
            return
        }
        
        // Check if this notification is for our channel
        if channelId == viewModel.channel.id && isReturning {
            print("🔍 SEARCH_CLOSING: User is returning from search to channel \(channelId)")
            isReturningFromSearch = true
            
            // Don't clear the flag here - let viewDidAppear handle it
        }
    }
    
    /// Handle video player dismiss notification - ensure navigation bar is hidden
    @objc func handleVideoPlayerDismiss(_ notification: Notification) {
        // print("🎬 MessageableChannelViewController: Video player dismissed, ensuring navigation bar is hidden")
        
        // Force hide navigation bar
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        // Force layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Double-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }
    
    /// Handle system log notification - check for network errors
    @objc func handleSystemLog(_ notification: Notification) {
        if let logMessage = notification.object as? String {
            checkForNetworkErrors(in: logMessage)
        }
    }
    
    /// Handle memory warning notification - delegate to ViewState
    @objc func handleMemoryWarning() {
        // MEMORY MANAGEMENT: Delegate to ViewState for centralized memory pressure handling
        viewModel.viewState.didReceiveMemoryWarning()
    }
    
    // MARK: - Timer Methods
    
    /// Check if scroll is needed and perform it if user is near bottom
    @objc func checkForScrollNeeded() {
        // Skip checks if tableView is nil or user is actively scrolling or we're loading more messages
        guard let tableView = tableView else { return }
        if tableView.isDragging || tableView.isDecelerating || isLoadingMore {
            return
        }
        
        // Add a variable to track user's last manual scroll time
        if let lastManualScrollTime = lastManualScrollTime, Date().timeIntervalSince(lastManualScrollTime) < 10.0 {
            // If less than 10 seconds have passed since the last manual scroll, do nothing
            return
        }
        
        // Only check if we have messages and the app is active
        guard !viewModel.messages.isEmpty, 
              UIApplication.shared.applicationState == .active else {
            return
        }
        
        // COMPREHENSIVE TARGET MESSAGE PROTECTION
        if targetMessageProtectionActive {
            return
        }
        
        // Only scroll if we're near bottom already AND not showing last message
        // If we're in the middle or top of chat, don't auto-scroll
        if isUserNearBottom(threshold: 100) {
            // Check if the last visible row is already the last message or close to it
            if let lastVisibleRow = tableView.indexPathsForVisibleRows?.last?.row,
               lastVisibleRow >= viewModel.messages.count - 2 {
                // Already showing the last message or very close, don't scroll
                return
            }
            
            // Check if enough time has passed since the last message update
            let timeSinceLastUpdate = Date().timeIntervalSince(lastMessageUpdateTime)
            if timeSinceLastUpdate < minimumUpdateInterval {
                // Too soon after a message update, skip scrolling
                return
            }
            
            // Only scroll if we're already near bottom but not showing last message
            // // print("⏱️ Timer check - auto-scrolling since user is near bottom but not showing last message")
            scrollToBottom(animated: true)
        } else {
            // // print("👆 [Timer] User is not near bottom, skipping auto-scroll")
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Check for network errors in log messages and post notification if detected
    private func checkForNetworkErrors(in logMessage: String) {
        // Add the log message to our recent logs
        recentLogMessages.append(logMessage)
        
        // Keep only the last maxLogMessages
        if recentLogMessages.count > maxLogMessages {
            recentLogMessages.removeFirst()
        }
        
        // Check if we've detected a network error recently (avoid multiple detections)
        if let lastError = lastNetworkErrorTime, 
           Date().timeIntervalSince(lastError) < networkErrorCooldown {
            return
        }
        
        // Check for network error patterns in recent logs
        let errorPatterns = ["Connection reset by peer", "tcp_input", "nw_read_request_report"]
        for pattern in errorPatterns {
            if logMessage.contains(pattern) {
                // print("⚠️ Detected network error: \(pattern)")
                lastNetworkErrorTime = Date()
                
                // Post notification about network error
                NotificationCenter.default.post(
                    name: NSNotification.Name("NetworkErrorOccurred"),
                    object: nil
                )
                break
            }
        }
    }
}
