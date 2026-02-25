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
        print("DEBUG: textViewDidChange called in MessageableChannelViewController with text: '\(textView.text ?? "")'")
        
        // Check if this is the message input text view
        if textView == messageInputView.textView {
            // Log that we've matched the right textView
            print("DEBUG: Confirmed this is the messageInputView's textView")
            
            // Handle mention functionality
            let text = textView.text ?? ""
            if text.contains("@") {
                // print("DEBUG: @ character detected in text: \(text)")
                // Check for mention triggers
                messageInputView.checkForMention(in: text)
            } else {
                // Hide mention view if no @ character
                messageInputView.hideMentionView()
            }
            
            // Then forward to the original MessageInputView's method
            messageInputView.textViewDidChange(textView)
            // Draft: debounced save (step 2b)
            draftSaveWorkItem?.cancel()
            let channelId = viewModel.channel.id
            let workItem = DispatchWorkItem { [weak self] in
                self?.viewModel.viewState.saveDraft(channelId: channelId, text: text)
            }
            draftSaveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        } else {
            // print("DEBUG: This is NOT the messageInputView's textView. Current textView: \(textView)")
            // print("DEBUG: Our messageInputView.textView: \(messageInputView.textView)")
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Safety check for range bounds (use UTF-16 length to handle emoji correctly)
        guard let textViewText = textView.text else { return true }
        let nsText = textViewText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else {
            // print("DEBUG: Invalid range in shouldChangeTextIn: \(range) for text length: \(nsText.length)")
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
            print("🔗 MessageableChannelViewController: URL tapped: \(URL.absoluteString)")
            
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
                
                print("🔗 MessageableChannelViewController: Handling internal peptide.chat link")
                handleInternalURL(URL)
                return false // Prevent default behavior
            }
            
            // For all other URLs, open in Safari
            print("🔗 MessageableChannelViewController: Opening external URL in Safari")
            
            // Temporarily suspend WebSocket to reduce network conflicts
            viewModel.viewState.temporarilySuspendWebSocket()
            
            UIApplication.shared.open(URL)
            return false // Prevent default behavior
        }
        return true // Allow other interactions like preview
    }
    
    private func handleInternalURL(_ url: URL) {
        print("🔗 MessageableChannelViewController: Handling URL: \(url.absoluteString)")
        
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") ||
           url.absoluteString.hasPrefix("https://app.revolt.chat/server/") {
            let components = url.pathComponents
            print("🔗 MessageableChannelViewController: URL components: \(components)")
            
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components.count >= 6 ? components[5] : nil
                
                print("🔗 MessageableChannelViewController: Parsed - Server: \(serverId), Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageableChannelViewController: Server exists: \(viewModel.viewState.servers[serverId] != nil)")
                print("🔗 MessageableChannelViewController: Channel exists: \(viewModel.viewState.channels[channelId] != nil)")
                
                // Check if server and channel exist
                if viewModel.viewState.servers[serverId] != nil && (viewModel.viewState.channels[channelId] != nil || viewModel.viewState.allEventChannels[channelId] != nil) {
                    // Check if user is a member of the server
                    guard let currentUser = viewModel.viewState.currentUser else {
                        print("❌ MessageableChannelViewController: Current user not found")
                        return
                    }
                    
                    let userMember = viewModel.viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        print("✅ MessageableChannelViewController: User is member, navigating to channel")
                        // Clear existing messages for this channel
                        viewModel.viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                            // This ensures that when user presses back, they go to server list instead of previous channel
                            print("🔄 MessageableChannelViewController: Clearing navigation path to prevent back to previous channel")
                            self.viewModel.viewState.path = []
                            
                            // Navigate to the server and channel
                            self.viewModel.viewState.selectServer(withId: serverId)
                            self.viewModel.viewState.selectChannel(inServer: serverId, withId: channelId)
                            
                            if let messageId = messageId {
                                self.viewModel.viewState.currentTargetMessageId = messageId
                                print("🎯 MessageableChannelViewController: Setting target message ID: \(messageId)")
                            } else {
                                self.viewModel.viewState.currentTargetMessageId = nil
                            }
                            
                            self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        print("🔍 MessageableChannelViewController: User is not member, navigating to Discover")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.viewModel.viewState.selectDiscover()
                        }
                    }
                } else {
                    print("🔍 MessageableChannelViewController: Server or channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.viewState.selectDiscover()
                    }
                }
            } else {
                print("❌ MessageableChannelViewController: Invalid URL format - not enough components")
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/channel/") {
            let components = url.pathComponents
            print("🔗 MessageableChannelViewController: Channel URL components: \(components)")
            
            if components.count >= 3 {
                let channelId = components[2]
                let messageId = components.count >= 4 ? components[3] : nil
                
                print("🔗 MessageableChannelViewController: Parsed - Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageableChannelViewController: Channel exists: \(viewModel.viewState.channels[channelId] != nil)")
                
                if let channel = viewModel.viewState.channels[channelId] ?? viewModel.viewState.allEventChannels[channelId] {
                    // For DM channels, check if user has access
                    switch channel {
                    case .dm_channel(let dmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewModel.viewState.currentUser else {
                            print("❌ MessageableChannelViewController: Current user not found")
                            return
                        }
                        
                        if dmChannel.recipients.contains(currentUser.id) {
                            // User has access to this DM - navigate to it
                            print("✅ MessageableChannelViewController: User has access to DM, navigating")
                            // Clear existing messages for this channel
                            viewModel.viewState.channelMessages[channelId] = []
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                // This ensures that when user presses back, they go to server list instead of previous channel
                                print("🔄 MessageableChannelViewController: Clearing navigation path to prevent back to previous channel (DM)")
                                self.viewModel.viewState.path = []
                                
                                // Navigate to the channel
                                self.viewModel.viewState.selectDm(withId: channelId)
                                
                                if let messageId = messageId {
                                    self.viewModel.viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageableChannelViewController: Setting target message ID: \(messageId)")
                                } else {
                                    self.viewModel.viewState.currentTargetMessageId = nil
                                }
                                
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            print("🔍 MessageableChannelViewController: User doesn't have access to DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.viewModel.viewState.selectDiscover()
                            }
                        }
                    case .group_dm_channel(let groupDmChannel):
                        // Check if current user is in the recipients list  
                        guard let currentUser = viewModel.viewState.currentUser else {
                            print("❌ MessageableChannelViewController: Current user not found")
                            return
                        }
                        
                        if groupDmChannel.recipients.contains(currentUser.id) {
                            // User has access to this group DM - navigate to it
                            print("✅ MessageableChannelViewController: User has access to group DM, navigating")
                            // Clear existing messages for this channel
                            viewModel.viewState.channelMessages[channelId] = []
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                // This ensures that when user presses back, they go to server list instead of previous channel
                                print("🔄 MessageableChannelViewController: Clearing navigation path to prevent back to previous channel (Group DM)")
                                self.viewModel.viewState.path = []
                                
                                // Navigate to the channel
                                self.viewModel.viewState.selectDm(withId: channelId)
                                
                                if let messageId = messageId {
                                    self.viewModel.viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageableChannelViewController: Setting target message ID: \(messageId)")
                                } else {
                                    self.viewModel.viewState.currentTargetMessageId = nil
                                }
                                
                                self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            print("🔍 MessageableChannelViewController: User doesn't have access to group DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.viewModel.viewState.selectDiscover()
                            }
                        }
                    default:
                        // For other channel types (text, voice, saved messages), navigate normally
                        print("✅ MessageableChannelViewController: Navigating to channel")
                        // Clear existing messages for this channel
                        viewModel.viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                            // This ensures that when user presses back, they go to server list instead of previous channel
                            print("🔄 MessageableChannelViewController: Clearing navigation path to prevent back to previous channel (Default)")
                            self.viewModel.viewState.path = []
                            
                            // Navigate to the channel
                            self.viewModel.viewState.selectDm(withId: channelId)
                            
                            if let messageId = messageId {
                                self.viewModel.viewState.currentTargetMessageId = messageId
                                print("🎯 MessageableChannelViewController: Setting target message ID: \(messageId)")
                            } else {
                                self.viewModel.viewState.currentTargetMessageId = nil
                            }
                            
                            self.viewModel.viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    }
                } else {
                    print("🔍 MessageableChannelViewController: Channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.viewState.selectDiscover()
                    }
                }
            } else {
                print("❌ MessageableChannelViewController: Invalid channel URL format")
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

