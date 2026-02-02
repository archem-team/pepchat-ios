//
//  MessageableChannelViewController+Replies.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import Combine
import Kingfisher
import ObjectiveC
import SwiftUI
import Types
import UIKit
import ULID

extension MessageableChannelViewController {
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
            print(
                "🌐 FETCH_REPLY: Fetching message from server - Channel: \(channelId), Message: \(messageId)"
            )
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
                statusCode == 404
            {
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
    
    /// Check if any messages have missing reply content and fetch them
    internal func checkAndFetchMissingReplies() async {
        // CRITICAL FIX: Throttle reply checks to avoid excessive API calls
        let now = Date()
        if let lastCheck = lastReplyCheckTime, now.timeIntervalSince(lastCheck) < replyCheckCooldown
        {
            print(
                "🔗 CHECK_THROTTLED: Skipping reply check (last check was \(now.timeIntervalSince(lastCheck))s ago)"
            )
            return
        }
        lastReplyCheckTime = now

        // Get current visible messages
        let currentMessages = localMessages.compactMap { messageId in
            viewModel.viewState.messages[messageId]
        }

        print("🔗 CHECK_MISSING: Checking \(currentMessages.count) messages for missing replies")

        // Find messages with replies that aren't loaded yet
        var messagesNeedingReplies: [Types.Message] = []
        var totalMessagesWithReplies = 0
        var totalReplyIds = 0
        var missingReplyIds = 0

        for message in currentMessages {
            guard let replies = message.replies, !replies.isEmpty else { continue }

            totalMessagesWithReplies += 1
            totalReplyIds += replies.count

            // Check if any reply content is missing
            let unloadedReplies = replies.filter { replyId in
                viewModel.viewState.messages[replyId] == nil
            }

            if !unloadedReplies.isEmpty {
                messagesNeedingReplies.append(message)
                missingReplyIds += unloadedReplies.count
                print(
                    "🔗 CHECK_MISSING: Message \(message.id) has \(unloadedReplies.count) missing replies: \(unloadedReplies)"
                )
            }
        }

        print(
            "🔗 CHECK_MISSING: Summary - Total messages with replies: \(totalMessagesWithReplies), Total reply IDs: \(totalReplyIds), Missing reply IDs: \(missingReplyIds)"
        )

        if !messagesNeedingReplies.isEmpty {
            print(
                "🔗 CHECK_MISSING: Found \(messagesNeedingReplies.count) messages with missing reply content, fetching now..."
            )
            await fetchReplyMessagesContent(for: messagesNeedingReplies)

            // Refresh UI after fetching missing replies
            await MainActor.run {
                print("🔗 CHECK_MISSING: Refreshing UI after loading missing replies")
                self.refreshMessages()
            }
        } else {
            print("🔗 CHECK_MISSING: All reply content is already loaded!")
        }
    }
    
    // MARK: - Reply Handling

    /// Handle clicking on a reply to jump to the original message
    func handleReplyClick(messageId: String, channelId: String) {
        print(
            "🔗 REPLY_CLICK: User clicked on reply to message \(messageId) in channel \(channelId)")
        print(
            "🔍 REPLY_CLICK: This is the main handleReplyClick method in MessageableChannelViewController!"
        )

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
                print(
                    "🌐 REPLY_CLICK: About to call refreshWithTargetMessage - this should trigger API calls!"
                )
                print("🔍 REPLY_CLICK: Current localMessages count: \(localMessages.count)")
                print(
                    "🔍 REPLY_CLICK: Current viewState messages count: \(viewModel.viewState.messages.count)"
                )
                print(
                    "🔍 REPLY_CLICK: Current channel messages count: \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0)"
                )

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
                                print(
                                    "✅ REPLY_CLICK: Message successfully loaded and should be visible"
                                )
                            } else {
                                print("❌ REPLY_CLICK: Message was not loaded successfully")
                                // Ensure loading state is reset
                                self.messageLoadingState = .notLoading
                                self.loadingHeaderView.isHidden = true
                                self.targetMessageId = nil
                                self.viewModel.viewState.currentTargetMessageId = nil

                                // Show error message to user
                                print(
                                    "❌ REPLY_CLICK: Could not load the original message. It may have been deleted."
                                )
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

    /// Briefly highlight a message cell
    internal func highlightMessageBriefly(cell: MessageCell) {
        let originalBackgroundColor = cell.backgroundColor

        // Highlight with blue color
        UIView.animate(
            withDuration: 0.3,
            animations: {
                cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
            }
        ) { _ in
            // Fade back to original color
            UIView.animate(withDuration: 1.0) {
                cell.backgroundColor = originalBackgroundColor
            }
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Reply Handling
    internal func addReply(_ message: Types.Message) {
        // This method is deprecated and will be removed
        // Use startReply(to:) instead
        let reply = ReplyMessage(message: message, mention: true)
        addReply(reply)
    }

    // Add a method to display replies when editing a message
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
    
}
