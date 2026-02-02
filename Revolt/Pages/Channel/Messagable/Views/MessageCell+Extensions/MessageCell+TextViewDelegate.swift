//
//  MessageCell+TextViewDelegate.swift
//  Revolt
//
//  Created by Akshat Srivastava on 02/02/26.
//

import UIKit
import Types
import Kingfisher
import AVKit

// MARK: - UITextViewDelegate Extension for MessageCell
extension MessageCell {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Only handle if this is the content label and it's an invoke action
        guard textView == contentLabel && interaction == .invokeDefaultAction else {
            return true
        }
        
        print("🔗 MessageCell: URL tapped: \(URL.absoluteString)")
        
        // Check if this is a mention URL
        if URL.scheme == "mention", let userId = URL.host {
            // Handle mention tap - open user sheet using current view state
            if let viewState = self.viewState, let user = viewState.users[userId] {
                let member: Member? = {
                    if let serverId = currentMember?.id.server {
                        return viewState.members[serverId]?[userId]
                    }
                    return nil
                }()
                viewState.openUserSheet(user: user, member: member)
            }
            return false // Prevent default behavior
        }
        
        // Check if this is a channel URL
        if URL.scheme == "channel", let channelId = URL.host {
            // Handle channel mention tap - navigate to channel
            if let viewState = self.viewState,
               let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                
                // print("📱 Channel mention tapped: channel \(channelId)")
                
                // Get current user
                guard let currentUser = viewState.currentUser else {
                    // print("❌ Current user not found")
                    return false
                }
                
                // Check if it's a server channel
                if let serverId = channel.server {
                    // Check if user is a member of the server
                    let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        // print("✅ User is member of server, navigating to channel")
                        viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            viewState.selectServer(withId: serverId)
                            viewState.selectChannel(inServer: serverId, withId: channelId)
                            viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        // print("🔍 User is not member of server \(serverId), navigating to Discover")
                        DispatchQueue.main.async {
                            // Clear path first to avoid navigation conflicts
                            viewState.path.removeAll()
                            viewState.selectDiscover()
                        }
                    }
                } else {
                    // DM or Group DM channel
                    var hasAccess = false
                    
                    // Check access based on channel type
                    switch channel {
                    case .dm_channel(let dmChannel):
                        hasAccess = dmChannel.recipients.contains(currentUser.id)
                    case .group_dm_channel(let groupDmChannel):
                        hasAccess = groupDmChannel.recipients.contains(currentUser.id)
                    case .saved_messages(let savedMessages):
                        hasAccess = savedMessages.user == currentUser.id
                    default:
                        hasAccess = true // For other types, allow access
                    }
                    
                    if hasAccess {
                        // User has access - navigate to the channel
                        // print("✅ User has access to channel, navigating")
                        viewState.channelMessages[channelId] = []
                        
                        DispatchQueue.main.async {
                            viewState.selectDm(withId: channelId)
                            viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                    } else {
                        // User doesn't have access - navigate to Discover
                        // print("🔍 User doesn't have access to channel \(channelId), navigating to Discover")
                        DispatchQueue.main.async {
                            // Clear path first to avoid navigation conflicts
                            viewState.path.removeAll()
                            viewState.selectDiscover()
                        }
                    }
                }
            } else {
                // Channel not found - navigate to Discover
                // print("🔍 Channel \(channelId) not found, navigating to Discover")
                if let viewState = self.viewState {
                    DispatchQueue.main.async {
                        // Clear path first to avoid navigation conflicts
                        viewState.path.removeAll()
                        viewState.selectDiscover()
                    }
                }
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
            
            print("🔗 MessageCell: Handling internal peptide.chat link")
            
            // Find the view controller to handle the URL
            if let viewController = findParentViewController() {
                handleInternalURL(URL, from: viewController)
            }
            
            return false // Prevent default behavior (going to Safari)
        }
        
        // For all other URLs, open in Safari
        // print("🔗 MessageCell: Opening external URL in Safari")
        
        // Temporarily suspend WebSocket to reduce network conflicts
        if let viewState = self.viewState {
            viewState.temporarilySuspendWebSocket()
        }
        
        // Explicitly open URL in Safari
        DispatchQueue.main.async {
            UIApplication.shared.open(URL, options: [:]) { success in
                // print("🌐 Safari open result for \(URL.absoluteString): \(success)")
            }
        }
        return false // Prevent default behavior
    }
    
    internal func handleInternalURL(_ url: URL, from viewController: UIViewController) {
        guard let viewState = self.viewState else {
            print("❌ MessageCell: ViewState is nil")
            return
        }
        
        print("🔗 MessageCell: Handling URL: \(url.absoluteString)")
        
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") ||
           url.absoluteString.hasPrefix("https://app.revolt.chat/server/") {
            let components = url.pathComponents
            print("🔗 MessageCell: URL components: \(components)")
            
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components.count >= 6 ? components[5] : nil
                
                print("🔗 MessageCell: Parsed - Server: \(serverId), Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageCell: Server exists: \(viewState.servers[serverId] != nil)")
                print("🔗 MessageCell: Channel exists: \(viewState.channels[channelId] != nil)")
                
                // Check if server and channel exist
                if viewState.servers[serverId] != nil && (viewState.channels[channelId] != nil || viewState.allEventChannels[channelId] != nil) {
                    // Check if user is a member of the server
                    guard let currentUser = viewState.currentUser else {
                        // print("❌ MessageCell: Current user not found")
                        return
                    }
                    
                    let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        print("✅ MessageCell: User is member, navigating to channel")
                        
                        DispatchQueue.main.async {
                            // CRITICAL FIX: Set target message BEFORE navigation
                            // This ensures the new view controller will pick it up correctly
                            if let messageId = messageId {
                                viewState.currentTargetMessageId = messageId
                                print("🎯 MessageCell: Setting target message ID BEFORE navigation: \(messageId)")
                            } else {
                                viewState.currentTargetMessageId = nil
                            }
                            
                            // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                            // This ensures that when user presses back, they go to server list instead of previous channel
                            print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel")
                            viewState.path = []
                            
                            // CRITICAL FIX: Clear existing messages for target channel to force reload
                            viewState.channelMessages[channelId] = []
                            viewState.preloadedChannels.remove(channelId)
                            viewState.atTopOfChannel.remove(channelId)
                            
                            // Navigate to the server and channel
                            viewState.selectServer(withId: serverId)
                            viewState.selectChannel(inServer: serverId, withId: channelId)
                            
                            // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.path.append(NavigationDestination.maybeChannelView)
                                print("🎯 MessageCell: Navigation completed - new view controller will handle target message")
                            }
                        }
                    } else {
                        // User is not a member - navigate to Discover
                        print("🔍 MessageCell: User is not member, navigating to Discover")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewState.selectDiscover()
                        }
                    }
                } else {
                    // print("🔍 MessageCell: Server or channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewState.selectDiscover()
                    }
                }
            } else {
                // print("❌ MessageCell: Invalid URL format - not enough components")
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/channel/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/channel/") {
            let components = url.pathComponents
            print("🔗 MessageCell: Channel URL components: \(components)")
            
                                                      if components.count >= 3 {
                let channelId = components[2]
                let messageId = components.count >= 4 ? components[3] : nil
                
                print("🔗 MessageCell: Parsed - Channel: \(channelId), Message: \(messageId ?? "nil")")
                print("🔗 MessageCell: Channel exists: \(viewState.channels[channelId] != nil)")
                
                if let channel = viewState.channels[channelId] ?? viewState.allEventChannels[channelId] {
                    // For DM channels, check if user has access
                    switch channel {
                    case .dm_channel(let dmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewState.currentUser else {
                            // print("❌ MessageCell: Current user not found")
                            return
                        }
                        
                        if dmChannel.recipients.contains(currentUser.id) {
                            // User has access to this DM - navigate to it
                            // print("✅ MessageCell: User has access to DM, navigating")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                // This ensures that when user presses back, they go to server list instead of previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (DM)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                    print("🎯 MessageCell: DM Navigation completed - new view controller will handle target message")
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            // print("🔍 MessageCell: User doesn't have access to DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.selectDiscover()
                            }
                        }
                    case .group_dm_channel(let groupDmChannel):
                        // Check if current user is in the recipients list
                        guard let currentUser = viewState.currentUser else {
                            // print("❌ MessageCell: Current user not found")
                            return
                        }
                        
                        if groupDmChannel.recipients.contains(currentUser.id) {
                            // User has access to this group DM - navigate to it
                            // print("✅ MessageCell: User has access to group DM, navigating")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE Group DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Group DM)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                    print("🎯 MessageCell: Group DM Navigation completed - new view controller will handle target message")
                                }
                            }
                        } else {
                            // User doesn't have access - navigate to Discover
                            // print("🔍 MessageCell: User doesn't have access to group DM, navigating to Discover")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewState.selectDiscover()
                            }
                        }
                    default:
                        // For other channel types (text, voice, saved messages), check if it's a server channel
                        // print("✅ MessageCell: Navigating to channel")
                        
                        // Check if this channel belongs to a server
                        if let serverId = channel.server {
                            // This is a server channel - navigate to server first, then channel
                            print("🔗 MessageCell: Channel \(channelId) belongs to server \(serverId)")
                            
                            // Check if user has access to this server
                            guard let currentUser = viewState.currentUser else {
                                print("❌ MessageCell: Current user not found")
                                return
                            }
                            
                            let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                            
                            if userMember != nil {
                                // User is a member - navigate to the server and channel
                                print("✅ MessageCell: User is member of server, navigating to server channel")
                                
                                DispatchQueue.main.async {
                                    // CRITICAL FIX: Set target message BEFORE navigation
                                    if let messageId = messageId {
                                        viewState.currentTargetMessageId = messageId
                                        print("🎯 MessageCell: Setting target message ID BEFORE server channel navigation: \(messageId)")
                                    } else {
                                        viewState.currentTargetMessageId = nil
                                    }
                                    
                                    // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                    print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Server Channel)")
                                    viewState.path = []
                                    
                                    // CRITICAL FIX: Clear existing messages for target channel to force reload
                                    viewState.channelMessages[channelId] = []
                                    viewState.preloadedChannels.remove(channelId)
                                    viewState.atTopOfChannel.remove(channelId)
                                    
                                    // Navigate to the server and channel
                                    viewState.selectServer(withId: serverId)
                                    viewState.selectChannel(inServer: serverId, withId: channelId)
                                    
                                    // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        viewState.path.append(NavigationDestination.maybeChannelView)
                                        print("🎯 MessageCell: Server Channel Navigation completed - new view controller will handle target message")
                                    }
                                }
                            } else {
                                // User is not a member - navigate to Discover
                                print("🔍 MessageCell: User is not member of server \(serverId), navigating to Discover")
                                DispatchQueue.main.async {
                                    viewState.selectDiscover()
                                }
                            }
                        } else {
                            // This is not a server channel (saved messages, etc.) - navigate as DM
                            print("🔗 MessageCell: Channel \(channelId) is not a server channel, treating as DM")
                            
                            DispatchQueue.main.async {
                                // CRITICAL FIX: Set target message BEFORE navigation
                                if let messageId = messageId {
                                    viewState.currentTargetMessageId = messageId
                                    print("🎯 MessageCell: Setting target message ID BEFORE DM navigation: \(messageId)")
                                } else {
                                    viewState.currentTargetMessageId = nil
                                }
                                
                                // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                print("🔄 MessageCell: Clearing navigation path to prevent back to previous channel (Non-server Channel)")
                                viewState.path = []
                                
                                // CRITICAL FIX: Clear existing messages for target channel to force reload
                                viewState.channelMessages[channelId] = []
                                viewState.preloadedChannels.remove(channelId)
                                viewState.atTopOfChannel.remove(channelId)
                                
                                // Navigate to the channel
                                viewState.selectDm(withId: channelId)
                                
                                // CRITICAL FIX: Use a small delay before adding to path to ensure state updates are processed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                }
                                print("🎯 MessageCell: DM Navigation completed - new view controller will handle target message")
                            }
                        }
                    }
                } else {
                    // print("🔍 MessageCell: Channel not found, navigating to Discover")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewState.selectDiscover()
                    }
                }
            } else {
                // print("❌ MessageCell: Invalid channel URL format")
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/invite/") ||
                  url.absoluteString.hasPrefix("https://app.revolt.chat/invite/") {
            let components = url.pathComponents
            if let inviteCode = components.last {
                // print("🔗 MessageCell: Processing invite code: \(inviteCode)")
                
                // First, try to fetch invite info to check if user is already a member
                Task {
                    do {
                        // Fetch invite info
                        let inviteInfo = try await viewState.http.fetchInvite(code: inviteCode).get()
                        
                        await MainActor.run {
                            // Check if user is already a member of this server (only applies to server invites)
                            if let serverId = inviteInfo.getServerID(),
                               let currentUser = viewState.currentUser,
                               viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil {
                                // User is already a member - navigate directly to the server
                                // print("✅ MessageCell: User is already a member of server \(serverId), navigating directly")
                                
                                // Clear existing messages for the default channel
                                if let server = viewState.servers[serverId],
                                   let channelId = inviteInfo.getChannelID() ?? server.channels.first {
                                    viewState.channelMessages[channelId] = []
                                }
                                
                                // Navigate to the server and channel
                                viewState.selectServer(withId: serverId)
                                
                                // If invite has a specific channel, go to it, otherwise go to first channel
                                if let channelId = inviteInfo.getChannelID() {
                                    viewState.selectChannel(inServer: serverId, withId: channelId)
                                } else if let server = viewState.servers[serverId],
                                          let firstChannelId = server.channels.first {
                                    viewState.selectChannel(inServer: serverId, withId: firstChannelId)
                                }
                                
                                viewState.path.append(NavigationDestination.maybeChannelView)
                            } else if case .group(let groupInfo) = inviteInfo {
                                // For group invites, check if user is already in the group
                                let channelId = groupInfo.channel_id
                                if let channel = viewState.channels[channelId],
                                   case .group_dm_channel(let groupDM) = channel,
                                   let currentUser = viewState.currentUser,
                                   groupDM.recipients.contains(currentUser.id) {
                                    // User is already in the group - navigate directly
                                    // print("✅ MessageCell: User is already in group \(channelId), navigating directly")
                                    viewState.channelMessages[channelId] = []
                                    viewState.selectDm(withId: channelId)
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                } else {
                                    // User is not in the group - show invite acceptance screen
                                    // print("🔗 MessageCell: User is not in group, showing invite screen")
                                    viewState.path.append(NavigationDestination.invite(inviteCode))
                                }
                            } else {
                                // User is not a member - show invite acceptance screen
                                // print("🔗 MessageCell: User is not a member, showing invite screen")
                                viewState.path.append(NavigationDestination.invite(inviteCode))
                            }
                        }
                    } catch {
                        // If we can't fetch invite info, just go to invite screen
                        // print("❌ MessageCell: Failed to fetch invite info: \(error)")
                        await MainActor.run {
                            viewState.path.append(NavigationDestination.invite(inviteCode))
                        }
                    }
                }
            }
        }
    }
}
