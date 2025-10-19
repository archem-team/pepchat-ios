//
//  MessageableChannelViewController+TextView.swift
//  Revolt
//
//

import UIKit
import Types

// MARK: - UITextViewDelegate
extension MessageableChannelViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        // Always log what happens
        
        // Check if this is the message input text view
        if textView == messageInputView.textView {
            // Log that we've matched the right textView
            
            // Handle mention functionality
            let text = textView.text ?? ""
            if text.contains("@") {
                // Check for mention triggers
                messageInputView.checkForMention(in: text)
            } else {
                // Hide mention view if no @ character
                messageInputView.hideMentionView()
            }
            
            // Then forward to the original MessageInputView's method
            messageInputView.textViewDidChange(textView)
        } else {
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Safety check for range bounds (use UTF-16 length to handle emoji correctly)
        guard let textViewText = textView.text else { return true }
        let nsText = textViewText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else {
            return false
        }
        
        // Check if this is the message input text view
        if textView == messageInputView.textView {
            // Forward to MessageInputView's delegate method
            return messageInputView.textView(textView, shouldChangeTextIn: range, replacementText: text)
        }
        
        return true
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Handle URL interactions for message content
        if interaction == .invokeDefaultAction {
            
            // Check if this is a mention URL
            if URL.scheme == "mention", let userId = URL.host {
                // Handle mention tap - open user sheet
                if let user = viewModel.viewState.users[userId] {
                    // Find the member for this user in the current channel
                    let member: Member? = viewModel.server.flatMap { server in
                        viewModel.viewState.members[server.id]?[userId]
                    }
                    
                    // Open user sheet
                    viewModel.viewState.openUserSheet(user: user, member: member)
                }
                return false // Prevent default behavior
            }
            
            // Check if this is a peptide.chat or app.revolt.chat link that should be handled internally
            if URL.absoluteString.hasPrefix("https://peptide.chat/server/") ||
               URL.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
               URL.absoluteString.hasPrefix("https://peptide.chat/invite/") ||
               URL.absoluteString.hasPrefix("https://app.revolt.chat/server/") ||
               URL.absoluteString.hasPrefix("https://app.revolt.chat/channel/") ||
               URL.absoluteString.hasPrefix("https://app.revolt.chat/invite/") {
                
                handleInternalURL(URL)
                return false // Prevent default behavior
            }
            
            // For all other URLs, open in Safari
            
            // Temporarily suspend WebSocket to reduce network conflicts
            viewModel.viewState.temporarilySuspendWebSocket()
            
            UIApplication.shared.open(URL)
            return false // Prevent default behavior
        }
        return true // Allow other interactions like preview
    }
    
    private func handleInternalURL(_ url: URL) {
        
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") ||
           url.absoluteString.hasPrefix("https://app.revolt.chat/server/") {
            let components = url.pathComponents
            
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components.count >= 6 ? components[5] : nil
                
                
                // Check if server and channel exist
                if viewModel.viewState.servers[serverId] != nil && viewModel.viewState.channels[channelId] != nil {
                    // Check if user is a member of the server
                    guard let currentUser = viewModel.viewState.currentUser else {
                        return
                    }
                    
                    let userMember = viewModel.viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        // Clear existing messages for this channel
                        viewModel.viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            // Prepare state and navigate without relying on helpers
                            if let mid = messageId {
                                self.viewModel.viewState.currentTargetMessageId = mid
                                self.viewModel.viewState.channelMessages[channelId] = []
                                self.viewModel.viewState.atTopOfChannel.remove(channelId)
                                self.viewModel.viewState.selectServer(withId: serverId)
                                self.viewModel.viewState.selectChannel(inServer: serverId, withId: channelId)
                                self.viewModel.viewState.path = []
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                                NetworkSyncService.shared.syncTargetMessage(messageId: mid, channelId: channelId, viewState: self.viewModel.viewState)
                            } else {
                                self.viewModel.viewState.selectServer(withId: serverId)
                                self.viewModel.viewState.selectChannel(inServer: serverId, withId: channelId)
                                self.viewModel.viewState.path = []
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                            }
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.viewModel.viewState.selectDiscover()
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.viewState.selectDiscover()
                    }
                }
            } else {
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/channel/") {
            let components = url.pathComponents
            
            if components.count >= 3 {
                let channelId = components[2]
                let messageId = components.count >= 4 ? components[3] : nil
                
                
                if let channel = viewModel.viewState.channels[channelId] {
                    // For DM channels, check if user has access
                    switch channel {
                    case .dm_channel(let dmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewModel.viewState.currentUser else {
                            return
                        }
                        
                        if dmChannel.recipients.contains(currentUser.id) {
                            // User has access to this DM - navigate to it
                            // Clear existing messages for this channel
                            viewModel.viewState.channelMessages[channelId] = []
                            
                            DispatchQueue.main.async {
                                if let mid = messageId {
                                    self.viewModel.viewState.currentTargetMessageId = mid
                                    self.viewModel.viewState.channelMessages[channelId] = []
                                    self.viewModel.viewState.atTopOfChannel.remove(channelId)
                                    self.viewModel.viewState.selectDm(withId: channelId)
                                    self.viewModel.viewState.path = []
                                    self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                                    NetworkSyncService.shared.syncTargetMessage(messageId: mid, channelId: channelId, viewState: self.viewModel.viewState)
                                } else {
                                    self.viewModel.viewState.path = []
                                    self.viewModel.viewState.selectDm(withId: channelId)
                                    self.viewModel.viewState.currentTargetMessageId = nil
                                    self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.viewModel.viewState.selectDiscover()
                            }
                        }
                    case .group_dm_channel(let groupDmChannel):
                        // Check if current user is in the recipients list  
                        guard let currentUser = viewModel.viewState.currentUser else {
                            return
                        }
                        
                        if groupDmChannel.recipients.contains(currentUser.id) {
                            // User has access to this group DM - navigate to it
                            // Clear existing messages for this channel
                            viewModel.viewState.channelMessages[channelId] = []
                            
                            DispatchQueue.main.async {
                                if let messageId = messageId {
                                    self.viewModel.viewState.navigateToChannelMessage(
                                        serverId: nil,
                                        channelId: channelId,
                                        messageId: messageId
                                    )
                                } else {
                                    self.viewModel.viewState.path = []
                                    self.viewModel.viewState.selectDm(withId: channelId)
                                    self.viewModel.viewState.currentTargetMessageId = nil
                                    self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.viewModel.viewState.selectDiscover()
                            }
                        }
                    default:
                        // For other channel types (text, voice, saved messages), navigate normally
                        // Clear existing messages for this channel
                        viewModel.viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            if let mid = messageId {
                                self.viewModel.viewState.currentTargetMessageId = mid
                                self.viewModel.viewState.channelMessages[channelId] = []
                                self.viewModel.viewState.atTopOfChannel.remove(channelId)
                                self.viewModel.viewState.selectDm(withId: channelId)
                                self.viewModel.viewState.path = []
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                                NetworkSyncService.shared.syncTargetMessage(messageId: mid, channelId: channelId, viewState: self.viewModel.viewState)
                            } else {
                                self.viewModel.viewState.path = []
                                self.viewModel.viewState.selectDm(withId: channelId)
                                self.viewModel.viewState.currentTargetMessageId = nil
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.viewState.selectDiscover()
                    }
                }
            } else {
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/invite/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/invite/") {
            let components = url.pathComponents
            if let inviteCode = components.last {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewModel.viewState.path.append(NavigationDestination.invite(inviteCode))
                }
            }
        }
    }
}

