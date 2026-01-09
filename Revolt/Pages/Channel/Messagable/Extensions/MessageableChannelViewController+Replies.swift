//
//  MessageableChannelViewController+Replies.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//  Phase 3: Medium-Risk Extensions - Reply Handling

import UIKit
import Types

// MARK: - Replies Handling
extension MessageableChannelViewController {
    
    // MARK: - Public Reply Methods
    
    func addReply(_ reply: ReplyMessage) {
        repliesManager.addReply(reply)
    }
    
    func removeReply(at id: String) {
        repliesManager.removeReply(at: id)
    }
    
    func clearReplies() {
        repliesManager.clearReplies()
    }
    
    // MARK: - Fetch Message for Reply
    
    /// Fetch a specific message from the server if it's not in cache
    /// This is used when replying to old messages that aren't currently loaded
    func fetchMessageForReply(messageId: String, channelId: String) async -> Types.Message? {
        print("🔍 FETCH_REPLY: Attempting to fetch message \(messageId) for reply")
        
        // First check if message is already in cache
        if let cachedMessage = viewModel.viewState.messages[messageId] {
            print("✅ FETCH_REPLY: Message found in cache")
            return cachedMessage
        }
        
        do {
            // Fetch the message from the server
            print("🌐 FETCH_REPLY: Fetching message from server - Channel: \(channelId), Message: \(messageId)")
            print("🌐 FETCH_REPLY: About to call viewModel.viewState.http.fetchMessage!")
            let message = try await viewModel.viewState.http.fetchMessage(
                channel: channelId,
                message: messageId
            ).get()
            
            print("✅ FETCH_REPLY: Successfully fetched message from server")
            print("✅ FETCH_REPLY: Message content: \(message.content ?? "no content")")
            
            // Store the message in cache
            await MainActor.run {
                viewModel.viewState.messages[message.id] = message
                
                // Also try to fetch the author if not in cache
                if viewModel.viewState.users[message.author] == nil {
                    Task {
                        await self.fetchUserForMessage(userId: message.author)
                    }
                }
            }
            
            return message
            
        } catch {
            print("❌ FETCH_REPLY: Failed to fetch message: \(error)")
            
            // Check if this is a 404 error (message deleted)
            if let revoltError = error as? RevoltError,
               case .HTTPError(_, let statusCode) = revoltError,
               statusCode == 404 {
                print("🗑️ FETCH_REPLY: Message \(messageId) was deleted (404)")
            }
            
            return nil
        }
    }
    
    /// Fetch user data if not in cache
    func fetchUserForMessage(userId: String) async {
        guard viewModel.viewState.users[userId] == nil else { return }
        
        do {
            print("👥 FETCH_USER: Fetching user \(userId) for reply message")
            let user = try await viewModel.viewState.http.fetchUser(user: userId).get()
            
            await MainActor.run {
                viewModel.viewState.users[user.id] = user
                print("✅ FETCH_USER: Successfully cached user \(user.username)")
            }
        } catch {
            print("❌ FETCH_USER: Failed to fetch user \(userId): \(error)")
            
            // Create a placeholder user to prevent crashes
            await MainActor.run {
                let placeholder = Types.User(
                    id: userId,
                    username: "Unknown User",
                    discriminator: "0000",
                    relationship: .None
                )
                viewModel.viewState.users[userId] = placeholder
                print("🔄 FETCH_USER: Created placeholder for user \(userId)")
            }
        }
    }
    
    // MARK: - Reply Click Handling
    
    /// Handle clicking on a reply to jump to the original message
    func handleReplyClick(messageId: String, channelId: String) {
        print("🔗 REPLY_CLICK: User clicked on reply to message \(messageId) in channel \(channelId)")
        print("🔍 REPLY_CLICK: This is the main handleReplyClick method in MessageableChannelViewController!")
        
        // CRITICAL FIX: Clear target message protection first to allow new reply click
        print("🎯 REPLY_CLICK: Clearing target message protection to allow new reply click")
        clearTargetMessageProtection(reason: "user clicked on reply")
        
        // Check if it's the same channel
        if channelId == viewModel.channel.id {
            // Same channel - scroll to the message
            print("📍 REPLY_CLICK: Same channel, attempting to scroll to message")
            
            // Check if message is already loaded
            if localMessages.contains(messageId) {
                // Message is loaded, scroll directly
                print("✅ REPLY_CLICK: Message is already loaded, scrolling directly")
                scrollToMessage(messageId: messageId)
            } else {
                // Message not loaded, use target message functionality
                print("🎯 REPLY_CLICK: Message not loaded, using target message functionality")
                print("🌐 REPLY_CLICK: About to call refreshWithTargetMessage - this should trigger API calls!")
                print("🔍 REPLY_CLICK: Current localMessages count: \(localMessages.count)")
                print("🔍 REPLY_CLICK: Current viewState messages count: \(viewModel.viewState.messages.count)")
                print("🔍 REPLY_CLICK: Current channel messages count: \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0)")
                
                // Set target message and trigger load
                targetMessageId = messageId
                viewModel.viewState.currentTargetMessageId = messageId
                
                // Show loading indicator with more specific message
                DispatchQueue.main.async {
                    print("🔄 REPLY_CLICK: Loading original message...")
                }
                
                // Trigger target message refresh with enhanced error handling
                Task {
                    do {
                        print("🚀 REPLY_CLICK: Starting refreshWithTargetMessage for \(messageId)")
                        await refreshWithTargetMessage(messageId)
                        
                        // Check if the message was successfully loaded
                        await MainActor.run {
                            if self.localMessages.contains(messageId) {
                                print("✅ REPLY_CLICK: Message successfully loaded and should be visible")
                            } else {
                                print("❌ REPLY_CLICK: Message was not loaded successfully")
                                // Ensure loading state is reset
                                self.messageLoadingState = .notLoading
                                self.loadingHeaderView.isHidden = true
                                self.targetMessageId = nil
                                self.viewModel.viewState.currentTargetMessageId = nil
                                
                                // Show error message to user
                                print("❌ REPLY_CLICK: Could not load the original message. It may have been deleted.")
                            }
                        }
                    } catch {
                        print("❌ REPLY_CLICK: Error in refreshWithTargetMessage: \(error)")
                        // Ensure all loading states are reset on error
                        await MainActor.run {
                            self.messageLoadingState = .notLoading
                            self.loadingHeaderView.isHidden = true
                            self.targetMessageId = nil
                            self.viewModel.viewState.currentTargetMessageId = nil
                            self.tableView.alpha = 1.0
                            self.tableView.tableFooterView = nil
                            
                            print("❌ REPLY_CLICK_ERROR: Failed to load message. Please try again.")
                        }
                    }
                }
            }
        } else {
            // Different channel - navigate to that channel with target message
            print("🔄 REPLY_CLICK: Different channel, navigating to channel \(channelId)")
            
            // Set target message in ViewState for cross-channel navigation
            viewModel.viewState.currentTargetMessageId = messageId
            
            // Navigate to the channel
            if let channel = viewModel.viewState.channels[channelId] {
                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                // This ensures that when user presses back, they go to server list instead of previous channel
                print("🔄 REPLY_CLICK: Clearing navigation path to prevent back to previous channel")
                viewModel.viewState.path = []
                
                // Clear any existing channel messages for the target channel
                viewModel.viewState.channelMessages[channelId] = []
                viewModel.viewState.atTopOfChannel.remove(channelId)
                
                // Select the server and channel properly
                if let serverId = channel.server {
                    viewModel.viewState.selectServer(withId: serverId)
                    viewModel.viewState.selectChannel(inServer: serverId, withId: channelId)
                } else {
                    // It's a DM channel
                    viewModel.viewState.selectDm(withId: channelId)
                }
                
                // Add the channel view to the navigation path
                viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                
                // Show loading message
                DispatchQueue.main.async {
                    print("🔄 NAVIGATE: Navigating to message...")
                }
            } else {
                // Channel not found, show error
                DispatchQueue.main.async {
                    print("❌ NAVIGATE: Channel not found")
                }
            }
        }
    }
    
    /// Scroll to a specific message that's already loaded
    private func scrollToMessage(messageId: String) {
        guard let index = localMessages.firstIndex(of: messageId) else {
            print("❌ SCROLL_TO_MESSAGE: Message \(messageId) not found in local messages")
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        
        // Make sure the index is valid
        guard index < tableView.numberOfRows(inSection: 0) else {
            print("❌ SCROLL_TO_MESSAGE: Index \(index) out of bounds")
            return
        }
        
        print("🎯 SCROLL_TO_MESSAGE: Scrolling to message at index \(index)")
        
        // Scroll to the message
        safeScrollToRow(at: indexPath, at: .middle, animated: true, reason: "scroll to specific message")
        
        // Highlight the message briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let cell = self.tableView.cellForRow(at: indexPath) as? MessageCell {
                self.highlightMessageBriefly(cell: cell)
            }
        }
    }
    
    /// Briefly highlight a message cell
    private func highlightMessageBriefly(cell: MessageCell) {
        let originalBackgroundColor = cell.backgroundColor
        
        // Highlight with blue color
        UIView.animate(withDuration: 0.3, animations: {
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        }) { _ in
            // Fade back to original color
            UIView.animate(withDuration: 1.0) {
                cell.backgroundColor = originalBackgroundColor
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Show Replies
    
    /// Deprecated method - use startReply(to:) instead
    internal func addReply(_ message: Types.Message) {
        // This method is deprecated and will be removed
        // Use startReply(to:) instead
        let reply = ReplyMessage(message: message, mention: true)
        addReply(reply)
    }
    
    /// Display replies when editing a message
    func showReplies(_ replies: [ReplyMessage]) {
        // print("📄 Showing \(replies.count) replies")
        
        // If repliesView has not been initialized, create it
        if repliesView == nil {
            repliesView = RepliesContainerView(frame: .zero)
            repliesView?.translatesAutoresizingMaskIntoConstraints = false
            if let repliesView = repliesView {
                view.addSubview(repliesView)
                
                // Setup constraints for repliesView - position it above messageInputView
                NSLayoutConstraint.activate([
                    repliesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    repliesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    repliesView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),
                ])
            }
        }
        
        // Set the replies and show the view
        self.replies = replies
        repliesView?.configure(with: replies, viewState: viewModel.viewState)
        repliesView?.isHidden = false
        
        // Adjust layout to make space for the replies view
        updateLayoutForReplies(isVisible: true)
    }
    
    /// Update layout when replies visibility changes
    private func updateLayoutForReplies(isVisible: Bool) {
        // Get the height of the replies view
        let repliesHeight: CGFloat = isVisible ? min(CGFloat(replies.count) * 60, 180) : 0
        
        // Update tableView bottom inset to make space for replies
        var insets = tableView.contentInset
        insets.bottom = messageInputView.frame.height + repliesHeight + (isKeyboardVisible ? keyboardHeight : 0)
        tableView.contentInset = insets
        
        // Also update the scroll indicator insets
        tableView.scrollIndicatorInsets = insets
        
        // Animate the change
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Reply Content Fetching
    
    // Note: checkAndFetchMissingReplies is defined in the main class
    // Note: lastReplyCheckTime and replyCheckCooldown are defined in the main class
    
    /// Fetch reply message content for messages that have replies and immediately refresh UI
    func fetchReplyMessagesContentAndRefreshUI(for messages: [Types.Message]) async {
        scheduleReplyPrefetch(for: messages)
    }

    func scheduleReplyPrefetch(for messages: [Types.Message]) {
        let combinedMessages = (pendingReplyFetchMessages + messages)
        var unique: [String: Types.Message] = [:]
        for message in combinedMessages {
            unique[message.id] = message
        }
        pendingReplyFetchMessages = Array(unique.values)

        if isUserScrolling {
            return
        }

        replyFetchDebounceTask?.cancel()
        let currentChannelId = viewModel.channel.id
        replyFetchDebounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, !self.isUserScrolling else { return }

            let messagesWithReplies = self.pendingReplyFetchMessages.filter { ($0.replies?.isEmpty == false) }
            self.pendingReplyFetchMessages.removeAll()
            guard !messagesWithReplies.isEmpty else { return }

            self.replyFetchTask?.cancel()
            self.replyFetchTask = Task { [weak self] in
                guard let self = self else { return }
                await self.fetchReplyMessagesContent(for: messagesWithReplies)

                await MainActor.run {
                    guard self.activeChannelId == currentChannelId,
                          self.isViewLoaded,
                          !Task.isCancelled else { return }
                    self.refreshMessages()
                }
            }
        }
    }
    
    // Note: ongoingReplyFetches is defined in the main class
    
    /// Fetch reply message content for messages that have replies
    func fetchReplyMessagesContent(for messages: [Types.Message]) async {
        if Task.isCancelled { return }
        print("🔗 FETCH_REPLIES: Processing \(messages.count) messages for reply content")
        
        var messagesWithReplies = 0
        var totalReplyIds = 0
        
        for message in messages {
            if Task.isCancelled { return }
            if let replies = message.replies, !replies.isEmpty {
                messagesWithReplies += 1
                totalReplyIds += replies.count
            }
        }
        
        print("🔗 FETCH_REPLIES: Found \(messagesWithReplies) messages with replies, total \(totalReplyIds) reply IDs")
        
        // Collect all unique reply message IDs that need to be fetched
        var replyIdsToFetch = Set<String>()
        var replyChannelMap = [String: String]() // messageId -> channelId
        
        for message in messages {
            if Task.isCancelled { return }
            guard let replies = message.replies, !replies.isEmpty else { continue }
            
            for replyId in replies {
                if Task.isCancelled { return }
                // Check if already in cache or being fetched
                let isInCache = viewModel.viewState.messages[replyId] != nil
                let isBeingFetched = ongoingReplyFetches.contains(replyId)
                
                // Only fetch if not already in cache and not being fetched
                if !isInCache && !isBeingFetched {
                    replyIdsToFetch.insert(replyId)
                    replyChannelMap[replyId] = message.channel
                    ongoingReplyFetches.insert(replyId) // Mark as being fetched
                }
            }
        }
        
        print("🔗 FETCH_REPLIES: Total unique reply IDs to fetch: \(replyIdsToFetch.count)")
        
        guard !replyIdsToFetch.isEmpty else {
            print("✅ FETCH_REPLIES: All reply messages already cached or no replies found")
            return
        }
        
        print("🔗 FETCH_REPLIES: Need to fetch \(replyIdsToFetch.count) reply messages")
        
        // Fetch reply messages concurrently for better performance
        await withTaskGroup(of: Void.self) { group in
            for replyId in replyIdsToFetch {
                group.addTask { [weak self] in
                    guard let self = self,
                          let channelId = replyChannelMap[replyId] else { 
                        print("❌ FETCH_REPLIES: Missing self or channelId for reply \(replyId)")
                        return 
                    }
                    
                    if let replyMessage = await self.fetchMessageForReply(messageId: replyId, channelId: channelId) {
                        // Also fetch the author if needed
                        await MainActor.run {
                            if self.viewModel.viewState.users[replyMessage.author] == nil {
                                Task {
                                    await self.fetchUserForMessage(userId: replyMessage.author)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("🔗 FETCH_REPLIES: Completed fetching reply messages")
        
        // CRITICAL FIX: Force UI refresh after fetching replies
        await MainActor.run {
            // Clear ongoing fetches
            for replyId in replyIdsToFetch {
                ongoingReplyFetches.remove(replyId)
            }
            
            // FORCE refresh UI to show newly loaded reply content
            if !replyIdsToFetch.isEmpty {
                // Force table view to reload data for messages with replies
                if let tableView = self.tableView {
                    // Find visible cells that might have replies
                    let visibleIndexPaths = tableView.indexPathsForVisibleRows ?? []
                    var indexPathsToReload: [IndexPath] = []
                    
                    for indexPath in visibleIndexPaths {
                        if indexPath.row < localMessages.count {
                            let messageId = localMessages[indexPath.row]
                            if let message = viewModel.viewState.messages[messageId],
                               let replies = message.replies, !replies.isEmpty {
                                // Check if any of the replies we just fetched belong to this message
                                let hasNewlyFetchedReplies = replies.contains { replyId in
                                    replyIdsToFetch.contains(replyId)
                                }
                                if hasNewlyFetchedReplies {
                                    indexPathsToReload.append(indexPath)
                                }
                            }
                        }
                    }
                    
                    if !indexPathsToReload.isEmpty {
                        tableView.reloadRows(at: indexPathsToReload, with: .none)
                    }
                }
            }
        }
    }
}
