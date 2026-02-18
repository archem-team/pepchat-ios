//
//  RepliesManager.swift
//  Revolt
//
//

import UIKit
import SwiftUI
import Types

// Simple notification banner for showing messages to the user
private class NotificationBanner {
    private let containerView = UIView()
    private let messageLabel = UILabel()
    
    init(message: String) {
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        messageLabel.text = message
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }
    
    func show(duration: TimeInterval = 2.0) {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        keyWindow.addSubview(containerView)
        
        // Position at top center
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerView.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: keyWindow.widthAnchor, constant: -40)
        ])
        
        // Start with alpha 0
        containerView.alpha = 0.0
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.containerView.alpha = 1.0
        }
        
        // Auto dismiss after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.3, animations: {
                self.containerView.alpha = 0.0
            }) { _ in
                self.containerView.removeFromSuperview()
            }
        }
    }
}

class RepliesManager: NSObject {
    weak var viewController: MessageableChannelViewController?
    private let viewModel: MessageableChannelViewModel
    
    // Replies container view
    private var repliesView: RepliesContainerView?
    private var replies: [ReplyMessage] = []
    
    // Cache viewState for synchronous access
    private var cachedViewState: ViewState?
    
    init(viewModel: MessageableChannelViewModel, viewController: MessageableChannelViewController) {
        self.viewModel = viewModel
        self.viewController = viewController
        super.init()
        
        // Cache viewState for synchronous access
        Task {
            self.cachedViewState = await viewModel.viewState
        }
    }
    
    // MARK: - Reply Management
    
    func addReply(_ reply: ReplyMessage) {
        // First clear any existing replies - only allow one reply at a time
        clearReplies()
        
        // Add the new reply
        replies.append(reply)
        updateRepliesView()
    }
    
    func removeReply(at id: String) {
        guard let viewController = viewController else { return }
        
        let wasEmpty = replies.isEmpty
        
        // Remove the reply
        replies.removeAll(where: { $0.messageId == id })
        
        // Update the UI
        updateRepliesView()
        
        // If this was the last reply, make sure we adjust the layout properly
        if !wasEmpty && replies.isEmpty {
            // Force layout update
            viewController.view.layoutIfNeeded()
            
            // If we're at the bottom, scroll to show the latest messages correctly
            // FIXED: Respect target message protection
            if viewController.isUserNearBottom() && !viewController.targetMessageProtectionActive {
                DispatchQueue.main.async {
                    viewController.scrollToBottom(animated: false)
                }
            } else if viewController.targetMessageProtectionActive {
                print("🛡️ RepliesManager: Target protection active, skipping auto-scroll")
            }
        }
    }
    
    func clearReplies() {
        guard let viewController = viewController else { return }
        
        let wasEmpty = replies.isEmpty
        
        // Clear all replies
        replies.removeAll()
        
        // DON'T clear MessageInputView's reply state - we don't use it
        // viewController.messageInputView.setReplyingToMessage(nil)
        
        // Update the UI
        updateRepliesView()
        
        // If we had replies before, make sure we adjust the layout properly
        if !wasEmpty {
            // Force layout update immediately
            viewController.view.layoutIfNeeded()
            
            // If we're at the bottom, scroll to show the latest messages correctly
            // FIXED: Respect target message protection
            if viewController.isUserNearBottom() && !viewController.targetMessageProtectionActive {
                DispatchQueue.main.async {
                    viewController.scrollToBottom(animated: false)
                }
            } else if viewController.targetMessageProtectionActive {
                print("🛡️ RepliesManager: Target protection active, skipping auto-scroll (2)")
            }
        }
    }
    
    func showReplies(_ replies: [ReplyMessage]) {
        self.replies = replies
        updateRepliesView()
    }
    
    func getCurrentReplies() -> [ReplyMessage] {
        return replies
    }
    
    // MARK: - Reply Click Handling
    
    func handleReplyClick(messageId: String, channelId: String) {
        // Delegate to the view controller's handleReplyClick method
        viewController?.handleReplyClick(messageId: messageId, channelId: channelId)
    }
    
    // MARK: - UI Management
    
    private func updateRepliesView() {
        guard let viewController = viewController else { return }
        
        // Create or update the replies view
        if repliesView == nil && !replies.isEmpty {
            setupRepliesView()
        }
        
        // Use cached viewState if available, otherwise get it async
        if let viewState = cachedViewState {
            repliesView?.configure(with: replies, viewState: viewState)
        } else {
            Task {
                let viewState = await viewModel.viewState
                self.cachedViewState = viewState
                await MainActor.run {
                    self.repliesView?.configure(with: self.replies, viewState: viewState)
                }
            }
        }
        repliesView?.isHidden = replies.isEmpty
        
        // Adjust table view bottom constraint based on replies view
        if !replies.isEmpty && repliesView != nil {
            // Get actual height from frame which is more reliable
            let repliesHeight = repliesView!.frame.height
            if repliesHeight > 0 {
                // Only add contentInset if we actually have replies with height
                viewController.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: repliesHeight, right: 0)
                print("📏 Set table inset to \(repliesHeight) for replies view")
            }
        } else {
            // Remove contentInset completely when no replies
            if viewController.tableView.contentInset.bottom > 0 {
                print("📏 Removing table inset (was \(viewController.tableView.contentInset.bottom))")
                viewController.tableView.contentInset = .zero
            }
        }
        
        // When changing the content inset, we need to adjust the scroll position 
        // to prevent visual jumps in the message list
        if replies.isEmpty {
            // If replies were just removed, scroll to show the bottom messages properly
            // FIXED: Respect target message protection
            if viewController.isUserNearBottom() && !viewController.targetMessageProtectionActive {
                DispatchQueue.main.async {
                    viewController.scrollToBottom(animated: false)
                }
            }
        }
    }
    
    private func setupRepliesView() {
        guard let viewController = viewController else { return }
        
        repliesView = RepliesContainerView(frame: .zero)
        repliesView?.translatesAutoresizingMaskIntoConstraints = false
        repliesView?.delegate = self
        viewController.view.addSubview(repliesView!)
        
        NSLayoutConstraint.activate([
            repliesView!.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            repliesView!.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            repliesView!.bottomAnchor.constraint(equalTo: viewController.messageInputView.topAnchor)
        ])
    }
    
    func startReply(to message: Types.Message) {
        // Load the full message if needed
        Task {
            // Capture values at the beginning to avoid async issues
            let channelId = await viewModel.channel.id
            let viewState = await viewModel.viewState
            self.cachedViewState = viewState
            
            var replyMessage = message
            
            // Check if message and author are in cache, if not fetch them
            if await viewState.messages[message.id] == nil || replyMessage.content == nil {
                // Use view controller's fetch method for consistent error handling
                if let fetchedMessage = await viewController?.fetchMessageForReply(messageId: message.id, channelId: channelId) {
                    replyMessage = fetchedMessage
                } else {
                    // Failed to fetch message - show error and return
                    await MainActor.run {
                        viewModel.viewState.showAlert(message: "Could not load message for reply. It may have been deleted.", icon: .peptideWarningCircle)
                    }
                    return
                }
            }
            
            // Make sure we have the author
            if await viewState.users[replyMessage.author] == nil {
                await viewController?.fetchUserForMessage(userId: replyMessage.author)
            }
            
            // Add the reply to our list
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let viewController = self.viewController else { return }
                
                // Create a Reply with default mention = true (matches SwiftUI version)
                let reply = ReplyMessage(message: replyMessage, mention: true)
                self.addReply(reply)
                
                // DON'T set MessageInputView's reply state - we use our own UI
                // viewController.messageInputView.setReplyingToMessage(replyMessage)
                
                // Focus the input field
                viewController.messageInputView.focusTextField()
            }
        }
    }
    
    // MARK: - Message Actions
    
    func handleMessageAction(_ action: MessageCell.MessageAction, message: Types.Message) {
        guard let viewController = viewController else { return }
        
        switch action {
        case .edit:
            // Implement editing message functionality
            print("Edit message: \(message.id)")
            
            // Set the message being edited
            Task {
                // Capture values at the beginning to avoid async issues
                let channelId = await viewModel.channel.id
                let viewState = await viewModel.viewState
                self.cachedViewState = viewState
                
                // Fetch replies for the message if any
                var replies: [ReplyMessage] = []
                
                for replyId in message.replies ?? [] {
                    var replyMessage: Types.Message? = await viewState.messages[replyId]
                    
                    if replyMessage == nil {
                        // Use view controller's fetch method for better error handling
                        replyMessage = await viewController.fetchMessageForReply(messageId: replyId, channelId: channelId)
                    }
                    
                    if let replyMessage = replyMessage {
                        // Make sure we have the author too
                        if await viewState.users[replyMessage.author] == nil {
                            await viewController.fetchUserForMessage(userId: replyMessage.author)
                        }
                        
                        // Create reply object
                        let isMention = message.mentions?.contains(replyMessage.author) ?? false
                        replies.append(ReplyMessage(
                            message: replyMessage,
                            mention: isMention
                        ))
                    }
                }
                
                // Update UI on main thread
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // Set message content in input field
                    viewController.messageInputView.setText(message.content)
                    
                    // Set editing state and show replies if any
                    viewController.messageInputView.setEditingMessage(message)
                    
                    if !replies.isEmpty {
                        self.showReplies(replies)
                    }
                    
                    // Focus the text field
                    viewController.messageInputView.focusTextField()
                }
            }
        case .delete:
            // Handle deleting message
            print("🗑️ Delete message action triggered for: \(message.id)")
            Task {
                // Capture values at the beginning to avoid async issues
                let channelId = await viewModel.channel.id
                let viewState = await viewModel.viewState
                self.cachedViewState = viewState
                
                print("🗑️ Starting delete operation for message: \(message.id) in channel: \(channelId)")
                
                let result = await viewState.http.deleteMessage(channel: channelId, message: message.id)
                
                await MainActor.run {
                    switch result {
                    case .success:
                        print("✅ Message deleted successfully: \(message.id)")
                        viewState.deletedMessageIds[channelId, default: Set()].insert(message.id)
                        if let userId = viewState.currentUser?.id, let baseURL = viewState.baseURL {
                            MessageCacheWriter.shared.enqueueDeleteMessage(id: message.id, channelId: channelId, userId: userId, baseURL: baseURL)
                        }
                        // Update local state immediately
                        Task {
                            await viewState.messages.removeValue(forKey: message.id)
                        
                        // Remove from channel messages array
                            if var channelMessages = await viewState.channelMessages[channelId] {
                            channelMessages.removeAll { $0 == message.id }
                                await viewState.channelMessages[channelId] = channelMessages
                            }
                        }
                        
                        // Show success message
                        print("Deleted")
                        print("✅ Local state updated after delete")
                        
                    case .failure(let error):
                        print("❌ Failed to delete message: \(error)")
                        print("NOT Deleted")
                    }
                }
            }
        case .report:
            // Handle reporting message
            print("Report message: \(message.id)")
        case .copy:
            // Copy message content to clipboard
            if let content = message.content {
                UIPasteboard.general.string = content
                Task { @MainActor in
                    viewModel.viewState.showAlert(message: "Message Copied!", icon: .peptideCopy)
                }
            }
        case .reply:
            startReply(to: message)
        case .mention:
            // Handle mentioning user
            print("Mention user from message: \(message.id)")
        case .markUnread:
            // Handle marking as unread
            print("🔄 Mark unread from message: \(message.id)")
            Task {
                // Capture values at the beginning to avoid async issues
                let channelId = await viewModel.channel.id
                let viewState = await viewModel.viewState
                let currentUserId = await viewState.currentUser?.id ?? ""
                
                // Get all messages in channel to find the message before this one
                let channelMessages = await viewState.channelMessages[channelId] ?? []
                
                // Find the index of the current message
                if let currentIndex = channelMessages.firstIndex(of: message.id) {
                    if currentIndex > 0 {
                        // There's a previous message - mark it as the last read message
                        let previousMessageId = channelMessages[currentIndex - 1]
                        
                        print("🔄 Setting last read message to: \(previousMessageId)")
                        
                        // Call the API to acknowledge the previous message
                        let result = await viewState.http.ackMessage(channel: channelId, message: previousMessageId)
                        
                        await MainActor.run {
                            switch result {
                            case .success:
                                print("✅ Successfully marked as unread from message: \(message.id)")
                                
                                // Update local unread state
                                Task {
                                    if var unread = await viewState.unreads[channelId] {
                                        unread.last_id = previousMessageId
                                        await viewState.unreads[channelId] = unread
                                    } else {
                                        // Create a new unread entry
                                        let unreadId = Unread.Id(channel: channelId, user: currentUserId)
                                        await viewState.unreads[channelId] = Unread(id: unreadId, last_id: previousMessageId)
                                    }
                                    
                                    // Update app badge count after marking as unread
                                    await MainActor.run {
                                        viewState.updateAppBadgeCount()
                                    }
                                }
                                
                                // CRITICAL: Disable automatic acknowledgment to prevent immediate re-acknowledgment
                                viewController.disableAutoAcknowledgment()
                                viewState.disableAutoAcknowledgment()
                                
                                // viewController.showErrorAlert(message: "Marked as unread")
                                
                            case .failure(let error):
                                print("❌ Failed to mark as unread: \(error)")
                                viewController.showErrorAlert(message: "Failed to mark as unread")
                            }
                        }
                    } else {
                        // This is the first message in the channel
                        // Remove the unread entry entirely to make all messages unread
                        print("🔄 Marking entire channel as unread (removing unread state)")
                        
                        await MainActor.run {
                            Task {
                                await viewState.unreads.removeValue(forKey: channelId)
                                
                                // Update app badge count after marking entire channel as unread
                                await MainActor.run {
                                    viewState.updateAppBadgeCount()
                                }
                            }
                            
                            // CRITICAL: Disable automatic acknowledgment for this case too
                            viewController.disableAutoAcknowledgment()
                            viewState.disableAutoAcknowledgment()
                            
                            // viewController.showErrorAlert(message: "Marked entire channel as unread")
                        }
                    }
                } else {
                    print("❌ Could not find message in channel messages list")
                    await MainActor.run {
                        viewController.showErrorAlert(message: "Could not mark as unread")
                    }
                }
            }
        case .copyLink:
            // Copy message link to clipboard
            Task {
                // Capture values at the beginning to avoid async issues
                let channel = await viewModel.channel
                let channelId = await channel.id
                
                // Generate proper URL based on channel type and current domain
                let messageLink: String = await generateMessageLink(
                    serverId: channel.server,
                    channelId: channelId,
                    messageId: message.id,
                    viewState: viewModel.viewState
                )
                
                await MainActor.run {
                    UIPasteboard.general.string = messageLink
                    viewModel.viewState.showAlert(message: "Message Link Copied!", icon: .peptideLink)
                }
            }
        case .copyId:
            // Copy message ID to clipboard
            UIPasteboard.general.string = message.id
            Task { @MainActor in
                viewModel.viewState.showAlert(message: "Message ID Copied!", icon: .peptideId)
            }
        case .react(let emoji):
            // Handle adding/removing reaction (toggle behavior)
            if emoji == "-1" {
                // Open custom emoji picker using SwiftUI
                presentEmojiPicker(for: message)
            } else {
                // Check if user already reacted with this emoji
                Task {
                    // Capture values at the beginning to avoid async issues
                    let channelId = await viewModel.channel.id
                    let viewState = await viewModel.viewState
                    let currentUserId = await viewState.currentUser?.id ?? ""
                    
                    let userAlreadyReacted = message.reactions?[emoji]?.contains(currentUserId) ?? false
                    
                    print("React with \(emoji) to message: \(message.id)")
                    print("User already reacted: \(userAlreadyReacted)")
                    
                    if userAlreadyReacted {
                        // Remove reaction (unreact)
                        let result = await viewState.http.unreactMessage(
                            channel: channelId, 
                            message: message.id, 
                            emoji: emoji
                        )
                        print("🔥 REMOVE REACTION API RESULT: \(result)")
                    } else {
                        // Add reaction
                        let result = await viewState.http.reactMessage(
                            channel: channelId, 
                            message: message.id, 
                            emoji: emoji
                        )
                        print("🔥 ADD REACTION API RESULT: \(result)")
                    }
                }
            }
        }
    }
    
    // MARK: - Emoji Picker Presentation
    
    private func presentEmojiPicker(for message: Types.Message) {
        guard let viewController = viewController else { return }
        
        // Capture message ID to ensure we're reacting to the correct message
        let messageId = message.id
        
        Task {
            // Capture values at the beginning to avoid async issues
            let channelId = await viewModel.channel.id
            let viewState = await viewModel.viewState
            
            await MainActor.run {
                // Create the EmojiPicker SwiftUI view
                let emojiPickerView = EmojiPicker(background: AnyView(Color.bgGray12)) { [weak self] emoji in
                    guard let self = self else { return }
                    
                    // Send the reaction using the emoji ID
                    let emojiToSend: String
                    if let id = emoji.emojiId {
                        // Custom emoji with ID
                        emojiToSend = ":\(id):"
                    } else {
                        // Standard Unicode emoji
                        emojiToSend = String(String.UnicodeScalarView(emoji.base.compactMap(Unicode.Scalar.init)))
                    }
                    
                    // Send the reaction in a background task
                    Task {
                        // Check if user already reacted with this emoji (toggle behavior)
                        let currentUserId = await viewState.currentUser?.id ?? ""
                        let userAlreadyReacted = message.reactions?[emojiToSend]?.contains(currentUserId) ?? false
                        
                        print("Custom emoji react with \(emojiToSend) to message: \(messageId)")
                        print("User already reacted: \(userAlreadyReacted)")
                        
                        if userAlreadyReacted {
                            // Remove reaction (unreact)
                            await viewState.http.unreactMessage(
                                channel: channelId, 
                                message: messageId, 
                                emoji: emojiToSend
                            )
                        } else {
                            // Add reaction
                            await viewState.http.reactMessage(
                                channel: channelId, 
                                message: messageId, 
                                emoji: emojiToSend
                            )
                        }
                        
                        // Dismiss the picker on main thread
                        await MainActor.run {
                            viewController.dismiss(animated: true)
                        }
                    }
                }
                .environmentObject(viewState)
                
                // Wrap the SwiftUI view in a UIHostingController
                let hostingController = UIHostingController(rootView: emojiPickerView)
                
                // Set the background color to match the app's theme
                hostingController.view.backgroundColor = UIColor(named: "bgGray12") ?? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
                
                // Configure the presentation style to match other emoji pickers in the app
                hostingController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
                
                // Configure sheet presentation for iOS 15+
                if #available(iOS 15.0, *) {
                    if let sheet = hostingController.sheetPresentationController {
                        sheet.detents = [UISheetPresentationController.Detent.medium(), UISheetPresentationController.Detent.large()]
                        sheet.prefersGrabberVisible = true
                        sheet.preferredCornerRadius = 16
                    }
                }
                
                // Present the sheet
                viewController.present(hostingController, animated: true)
            }
        }
    }
}

// MARK: - RepliesContainerViewDelegate
extension RepliesManager: RepliesContainerViewDelegate {
    func repliesContainerView(_ view: RepliesContainerView, didRemoveReplyAt id: String) {
        removeReply(at: id)
    }
    
    func getViewState() -> ViewState {
        // Use cached viewState if available, otherwise access directly
        if let viewState = cachedViewState {
            return viewState
        } else {
            // Fallback to direct access (may cause async issues but maintains compatibility)
        return viewModel.viewState
        }
    }
}

// MARK: - Reply Click Handling (Add method to support reply clicks)
extension RepliesManager {
    func replyItemViewDidPressReply(messageId: String, channelId: String) {
        // Handle the reply click by delegating to handleReplyClick
        print("🔗 RepliesManager: Reply click received for messageId: \(messageId), channelId: \(channelId)")
        handleReplyClick(messageId: messageId, channelId: channelId)
    }
}

// MARK: - Helper Functions
/// Generates a dynamic message link based on the current domain
private func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
    // Get the current base URL and determine the web domain
    let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
    let webDomain: String
    
    if baseURL.contains("peptide.chat") {
        webDomain = "https://peptide.chat"
    } else if baseURL.contains("app.revolt.chat") {
        webDomain = "https://app.revolt.chat"
    } else {
        // Fallback for other instances - extract domain from API URL
        if let url = URL(string: baseURL),
           let host = url.host {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat" // Ultimate fallback
        }
    }
    
    // Generate proper URL based on channel type
    if let serverId = serverId, !serverId.isEmpty {
        // Server channel
        return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
    } else {
        // DM channel
        return "\(webDomain)/channel/\(channelId)/\(messageId)"
    }
}

