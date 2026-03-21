//
//  ViewState+WebSocketEvents.swift
//  Revolt
//
//  Created by Akshat Srivastava on 31/01/26.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network

extension ViewState {
    internal func processEvent(_ event: WsMessage) async {
        switch event {
        case .ready(let event):
            // print("🚀 VIEWSTATE: Processing READY event")
            // print("   - Users: \(event.users.count)")
            // print("   - Servers: \(event.servers.count)")
            // print("   - Channels: \(event.channels.count)")
            // print("   - Members: \(event.members.count)")
            // print("   - Emojis: \(event.emojis.count)")
            
            // CRITICAL FIX: Preserve current channel and selection during ready event
            let savedCurrentChannel = currentChannel
            let savedCurrentSelection = currentSelection
            // print("💾 READY: Saving current state - channel: \(savedCurrentChannel), selection: \(savedCurrentSelection)")
            
            // CRITICAL FIX: Don't clear servers/channels/users completely - merge with existing data
            // print("🔄 READY: Merging servers with existing data (current: \(servers.count), incoming: \(event.servers.count))")
            
            // Only clear messages as they should be fresh from server
            messages.removeAll()
            channelMessages.removeAll()
            
            // For users, channels, and servers: merge instead of clearing completely
            // This preserves any data loaded from UserDefaults
            // print("🔄 READY: Preserving existing servers/channels/users, will merge with server data")
            
            // MEMORY FIX: Extract only needed data and process immediately
            // This allows the large event object to be released from memory
            let neededData = extractNeededDataFromReadyEvent(event)

            // PERF: Start unreads fetch in parallel (only needs auth token, not processed data)
            let unreadsTask = Task { () -> [Unread]? in
                try? await self.http.fetchUnreads().get()
            }

            // Process the extracted data (runs concurrently with unreads fetch)
            await processReadyData(neededData)
            
            // CRITICAL FIX: Restore saved state after ready event processing
            // print("🔄 READY: Restoring saved state - channel: \(savedCurrentChannel), selection: \(savedCurrentSelection)")
            currentChannel = savedCurrentChannel
            currentSelection = savedCurrentSelection
            
            // If the saved channel is from a server, make sure that server's channels are loaded
            if case .channel(let channelId) = savedCurrentChannel {
                if let restoredChannel = allEventChannels[channelId] {
                    // Make sure the channel is in active channels
                    channels[channelId] = restoredChannel
                    
                    if let serverId = restoredChannel.server {
                        // Make sure we're in the right selection and server channels are loaded
                        if savedCurrentSelection != .server(serverId) {
                            // print("🔄 READY: Correcting selection to server \(serverId) for channel \(channelId)")
                            currentSelection = .server(serverId)
                        }
                        loadServerChannels(serverId: serverId)
                    }
                    // print("✅ READY: Successfully restored channel \(channelId)")
                } else {
                    // print("⚠️ READY: Could not restore channel \(channelId) - not found in stored channels")
                }
            }
            
            // CONDITIONAL: Only preload after Ready event if automatic preloading is enabled
            if self.enableAutomaticPreloading {
                // PRELOAD: Trigger preload of important channels after Ready event
                Task {
                    await self.preloadImportantChannels()
                }
                // print("🚀 PRELOAD_ENABLED: Started automatic preloading after Ready event")
            } else {
                // print("📵 PRELOAD_DISABLED: Skipped automatic preloading after Ready event")
            }
            
            // CLEANUP: Clean up stale unreads after Ready event
            // This ensures that unreads for deleted channels are removed after server sync
            Task {
                await MainActor.run {
                    self.cleanupStaleUnreads()
                    // print("🧹 Cleaned up stale unreads after Ready event")
                }
            }

            // PERF: Apply unreads from parallel fetch (likely already finished by now)
            Task {
                if let remoteUnreads = await unreadsTask.value {
                    await MainActor.run {
                        let newUnreads = Dictionary(
                            remoteUnreads.map { ($0.id.channel, $0) },
                            uniquingKeysWith: { _, latest in latest }
                        )
                        self.unreads.merge(newUnreads) { _, remote in remote }
                    }
                }
            }

        case .message(let m):
          batchUpdate {

            if let user = m.user {
                // CRITICAL FIX: Always add/update message authors to prevent black messages
                users[user.id] = user
                // CRITICAL FIX: Also store in allEventUsers for permanent access
                allEventUsers[user.id] = user
                // print("📥 VIEWSTATE: Added/updated user \(user.username) for message author to both dictionaries")
            } else {
                // CRITICAL FIX: If user data not provided, try to load from stored data or create placeholder
                if users[m.author] == nil {
                    if let storedUser = allEventUsers[m.author] {
                        users[m.author] = storedUser
                        // print("📥 VIEWSTATE: Loaded message author \(storedUser.username) from stored data")
                    } else {
                        // Create placeholder to prevent black messages
                        let placeholderUser = Types.User(
                            id: m.author,
                            username: "Unknown User",
                            discriminator: "0000",
                            relationship: .None
                        )
                        users[m.author] = placeholderUser
                        allEventUsers[m.author] = placeholderUser
                        // print("⚠️ VIEWSTATE: Created placeholder for missing message author: \(m.author)")
                    }
                }
            }
            
            if let member = m.member {
                members[member.id.server]?[member.id.user] = member
            }
            
            let userMentioned = m.mentions?.contains(where: {
                $0 == currentUser?.id
            }) ?? false
            
            // Check if message is from current user
            let isFromCurrentUser = m.author == currentUser?.id
                        
            if let unread = unreads[m.channel]{
                // Don't update unread for messages sent by the current user
                if !isFromCurrentUser {
                    // Update last_id for messages from other users
                    // This ensures unread count properly reflects new messages
                    unreads[m.channel]?.last_id = m.id
                    
                    if userMentioned {
                        if unreads[m.channel]?.mentions != nil {
                            unreads[m.channel]?.mentions?.append(m.id)
                        } else {
                            unreads[m.channel]!.mentions = [m.id]
                        }
                    }
                }
            } else if !isFromCurrentUser {
                // Only create unread entry for messages from other users
                unreads[m.channel] = .init(id: .init(channel: m.channel, user: currentUser?.id ?? ""),
                                           last_id: m.id,
                                           mentions: userMentioned ? [m.id]:[])
            }
            
            // Check if message already exists
            if messages[m.id] != nil {
                // print("⚠️ VIEWSTATE: Message \(m.id) already exists, updating")
            }
            
            messages[m.id] = m
            
            // Check if this message matches a queued message and clean it up
            var matchedQueuedMessage = false
            if let channelQueuedMessages = queuedMessages[m.channel] {
                let queuedIndex: Int? = {
                    if let messageNonce = m.nonce {
                        return channelQueuedMessages.firstIndex(where: { $0.nonce == messageNonce })
                    }
                    return nil
                }() ?? channelQueuedMessages.firstIndex(where: { queued in
                    return queued.content == m.content &&
                           queued.author == m.author &&
                           queued.channel == m.channel
                })
                if let queuedIndex = queuedIndex {
                    matchedQueuedMessage = true
                    let queuedMessage = channelQueuedMessages[queuedIndex]
                    // print("📥 VIEWSTATE: Found matching queued message, cleaning up nonce: \(queuedMessage.nonce)")
                    
                    // Remove the temporary message from messages dictionary (if it exists)
                    messages.removeValue(forKey: queuedMessage.nonce)
                    
                    // For messages without attachments: Replace nonce with real ID in channel messages
                    // For messages with attachments: Add to channel messages for the first time
                    if let nonceMsgIndex = channelMessages[m.channel]?.firstIndex(of: queuedMessage.nonce) {
                        // This was an optimistic message (no attachments), replace it
                        channelMessages[m.channel]?[nonceMsgIndex] = m.id
                        // print("📥 VIEWSTATE: Replaced optimistic nonce \(queuedMessage.nonce) with real ID \(m.id)")
                    } else if queuedMessage.hasAttachments {
                        // This was an attachment message (not shown optimistically), add it now
                        if channelMessages[m.channel] == nil {
                            channelMessages[m.channel] = []
                        }
                        channelMessages[m.channel]?.append(m.id)
                        // print("📥 VIEWSTATE: Added attachment message \(m.id) to channel messages for first time")
                    }
                    
                    // Remove from queued messages for this channel
                    queuedMessages[m.channel]?.remove(at: queuedIndex)
                    if queuedMessages[m.channel]?.isEmpty == true {
                        queuedMessages.removeValue(forKey: m.channel)
                    }
                    // print("📥 VIEWSTATE: Removed queued message from channel \(m.channel)")
                }
            }
            if !matchedQueuedMessage {
                // Check channel messages array
                if channelMessages[m.channel] == nil {
                    // print("📥 VIEWSTATE: Creating new channelMessages array for channel \(m.channel)")
                    channelMessages[m.channel] = []
                }
                
                // MEMORY FIX: Check if message already exists in channel to avoid duplicates
                if !(channelMessages[m.channel]?.contains(m.id) ?? false) {
                    channelMessages[m.channel]?.append(m.id)
                } else {
                    // print("⚠️ VIEWSTATE: Message \(m.id) already exists in channelMessages, skipping append")
                }
            }
            
            // Update message cache so new messages (from this device or others) appear on next session
            if let userId = currentUser?.id, let baseURL = baseURL,
               let authorUser = users[m.author] ?? allEventUsers[m.author] ?? m.user {
                MessageCacheWriter.shared.enqueueCacheMessagesAndUsers([m], users: [authorUser], channelId: m.channel, userId: userId, baseURL: baseURL, lastMessageId: m.id)
            }
            
            let channelMessagesAfter = channelMessages[m.channel]?.count ?? 0
            
            // print("📥 VIEWSTATE: Channel messages count - before: \(channelMessagesBefore), after: \(channelMessagesAfter)")
            // print("📥 VIEWSTATE: Total messages count AFTER: \(messages.count)")
            // print("📥 VIEWSTATE: Total channel message arrays: \(channelMessages.count)")
            
            // Log memory info
            let totalChannelMessages = channelMessages.values.reduce(0) { $0 + $1.count }
            // print("📥 VIEWSTATE: Total messages across all channels: \(totalChannelMessages)")
            
            // DISABLED: MEMORY MANAGEMENT: Proactive cleanup
            // checkAndCleanupIfNeeded() - Disabled to prevent black messages
            
            NotificationCenter.default.post(
                name: NSNotification.Name("NewMessagesReceived"),
                object: nil,
                userInfo: ["channelId": m.channel]
            )
            
            if let index = dms.firstIndex(where: { $0.id == m.channel }) {
                let dmChannel = dms.remove(at: index)

                let updatedDM: Channel
                switch dmChannel {
                    case .dm_channel(var c):
                        c.last_message_id = m.id
                        updatedDM = .dm_channel(c)
                    case .group_dm_channel(var c):
                        c.last_message_id = m.id
                        updatedDM = .group_dm_channel(c)
                    default:
                        updatedDM = dmChannel
                }

                dms.insert(updatedDM, at: 0)
            }

            // Always keep canonical DM order (most recent at top), even when user is not on DMs tab,
            // so that when they open DMs the list is correct and does not revert on scroll.
            let isDM: Bool = {
                if let ch = channels[m.channel] {
                    if case .dm_channel = ch { return true }
                    if case .group_dm_channel = ch { return true }
                }
                return false
            }()
            if isDM {
                if let idx = allDmChannelIds.firstIndex(of: m.channel) {
                    allDmChannelIds.remove(at: idx)
                    allDmChannelIds.insert(m.channel, at: 0)
                } else {
                    // New DM (e.g. from another device) or not yet in list
                    allDmChannelIds.insert(m.channel, at: 0)
                }
            }

            if var existing = channels[m.channel] {
                switch existing {
                case .dm_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .dm_channel(c)
                case .group_dm_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .group_dm_channel(c)
                case .text_channel(var c):
                    c.last_message_id = m.id
                    channels[m.channel] = .text_channel(c)
                default:
                    break
                }
            }
            if var existing = allEventChannels[m.channel], existing.server != nil {
                if case .text_channel(var c) = existing {
                    c.last_message_id = m.id
                    allEventChannels[m.channel] = .text_channel(c)
                    saveChannelCacheAsync()
                }
            }
          } // end batchUpdate for .message


        case .message_update(let event):
            // Invalidate cached attributed string so the cell re-renders with new content
            MessageCell.attributedStringCache.removeObject(forKey: event.id as NSString)

            let message = messages[event.id]

            if var message = message {
                message.edited = event.data.edited
                if let content = event.data.content {
                    message.content = content
                }
                messages[event.id] = message
                if let userId = currentUser?.id, let baseURL = baseURL {
                    let parsedEditedAt = message.edited.flatMap { ISO8601DateFormatter().date(from: $0) }
                    MessageCacheWriter.shared.enqueueUpdateMessage(id: event.id, content: message.content, editedAt: parsedEditedAt, channelId: message.channel, userId: userId, baseURL: baseURL)
                }
                NotificationCenter.default.post(
                    name: NSNotification.Name("MessageContentDidChange"),
                    object: nil,
                    userInfo: ["channelId": message.channel, "messageId": event.id]
                )
            } else if let userId = currentUser?.id, let baseURL = baseURL {
                // Message not in ViewState (e.g. user wasn't in channel when another user edited). Still update cache so next open shows the edit.
                let parsedEditedAt = ISO8601DateFormatter().date(from: event.data.edited)
                MessageCacheWriter.shared.enqueueUpdateMessageById(id: event.id, content: event.data.content, editedAt: parsedEditedAt, userId: userId, baseURL: baseURL)
            }
            
        case .authenticated:
            // print("authenticated")
            
            break
        case .invalid_session:
            Task {
                await self.signOut()
            }
            
        case .logout:
            Task {
                await self.signOut(afterRemoveSession: true)
            }
        case .channel_start_typing(let e):
            updateTyping(channelId: e.id, userId: e.user, isTyping: true)

        case .channel_stop_typing(let e):
            updateTyping(channelId: e.id, userId: e.user, isTyping: false)
            
        case .message_delete(let e):
            deletedMessageIds[e.channel, default: Set()].insert(e.id)
            if var channel = channelMessages[e.channel] {
                if let index = channel.firstIndex(of: e.id) {
                    channel.remove(at: index)
                    channelMessages[e.channel] = channel
                }
            }
            if let userId = currentUser?.id, let baseURL = baseURL {
                MessageCacheWriter.shared.enqueueDeleteMessage(id: e.id, channelId: e.channel, userId: userId, baseURL: baseURL)
            }
            
        case .channel_ack(let e):
            unreads[e.id]?.last_id = e.message_id
            unreads[e.id]?.mentions?.removeAll { $0 <= e.message_id }
            
        case .message_react(let e):
            if var message = messages[e.id] {
                var reactions = message.reactions ?? [:]
                var users = reactions[e.emoji_id] ?? []
                
                // Check if user is not already in the reaction list to avoid duplicates
                if !users.contains(e.user_id) {
                    users.append(e.user_id)
                    reactions[e.emoji_id] = users
                    message.reactions = reactions
                    messages[e.id] = message
                    
                    // print("🔥 VIEWSTATE: Added reaction \(e.emoji_id) from user \(e.user_id) to message \(e.id) in channel \(e.channel_id)")
                    
                    // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessagesDidChange"),
                            object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_added"]
                        )
                    }
                } else {
                    // print("🔥 VIEWSTATE: User \(e.user_id) already reacted with \(e.emoji_id) on message \(e.id)")
                }
            } else {
                // print("🔥 VIEWSTATE: Message \(e.id) not found for reaction add")
            }
            
        case .message_unreact(let e):
            if var message = messages[e.id] {
                if var reactions = message.reactions {
                    if var users = reactions[e.emoji_id] {
                        users.removeAll { $0 == e.user_id }
                        
                        if users.isEmpty {
                            reactions.removeValue(forKey: e.emoji_id)
                        } else {
                            reactions[e.emoji_id] = users
                        }
                        message.reactions = reactions
                        messages[e.id] = message
                        
                        // print("🔥 VIEWSTATE: Removed reaction \(e.emoji_id) from user \(e.user_id) on message \(e.id) in channel \(e.channel_id)")
                        
                        // Post notification to update UI
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("MessagesDidChange"),
                                object: ["channelId": e.channel_id, "messageId": e.id, "type": "reaction_removed"]
                            )
                        }
                    } else {
                        // print("🔥 VIEWSTATE: No users found for emoji \(e.emoji_id) on message \(e.id)")
                    }
                } else {
                    // print("🔥 VIEWSTATE: No reactions found on message \(e.id)")
                }
            } else {
                // print("🔥 VIEWSTATE: Message \(e.id) not found for reaction remove")
            }
        case .message_append(let e):
            if var message = messages[e.id] {
                var embeds = message.embeds ?? []
                embeds.append(e.append)
                message.embeds = embeds
                messages[e.id] = message
            }
        case .user_update(let e):
            updateUser(with: e)
        case .server_create(let e):
          batchUpdate {
            for channel in e.channels {
                self.allEventChannels[channel.id] = channel
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
            }
            var server = e.server
            for channel in e.channels {
                if !server.channels.contains(channel.id) {
                    server.channels.append(channel.id)
                }
            }
            self.servers[e.id] = server
            self.updateMembershipCache(serverId: e.id, isMember: true)
            self.saveChannelCacheAsync()
            self.saveServersCacheAsync()
          }

        case .server_delete(let e):
          batchUpdate {
            if let server = self.servers[e.id] {
                for channelId in server.channels {
                    self.channels.removeValue(forKey: channelId)
                    self.channelMessages.removeValue(forKey: channelId)
                    self.unreads.removeValue(forKey: channelId)
                    self.preloadedChannels.remove(channelId)
                    self.allEventChannels.removeValue(forKey: channelId)
                }
                self.loadedServerChannels.remove(e.id)
                if case .channel(let id) = self.currentChannel, server.channels.contains(id) {
                    self.path = .init()
                    self.currentChannel = .home
                }
            }
            self.servers.removeValue(forKey: e.id)
            self.updateMembershipCache(serverId: e.id, isMember: false)
            self.saveChannelCacheAsync()
            self.saveServersCacheAsync()
            if case .server(let string) = currentSelection, string == e.id {
                self.path = .init()
                self.selectDms()
            }
          }
            
            
        case .server_update(let e):
            
            if let tmpServer = self.servers[e.id] {
                
                var t = tmpServer
                
                if let icon = e.data?.icon {
                    t.icon = icon
                }
                
                if let name = e.data?.name  {
                    t.name = name
                }
                
                if let description = e.data?.description {
                    t.description = description
                }
                
                if let banner = e.data?.banner {
                    t.banner = banner
                }
                
                if let systemMessage = e.data?.system_messages {
                    t.system_messages = systemMessage
                }
                
                if let categories = e.data?.categories {
                    t.categories = categories
                }
                
                if let default_permissions = e.data?.default_permissions {
                    t.default_permissions = default_permissions
                }
                
                if let owner = e.data?.owner {
                    t.owner = owner
                }
                
                if let nsfw = e.data?.nsfw {
                    t.nsfw = nsfw
                }
                
                
                if e.clear?.contains(ServerEdit.Remove.icon) == true {
                    t.icon = nil
                }
                
                if e.clear?.contains(ServerEdit.Remove.banner) == true {
                    t.banner = nil
                }
                
                let oldChannelIds = Set(self.servers[e.id]?.channels ?? [])
                let newChannelIds = Set(t.channels)
                let removedIds = oldChannelIds.subtracting(newChannelIds)
                for id in removedIds {
                    self.channels.removeValue(forKey: id)
                    self.channelMessages.removeValue(forKey: id)
                    self.unreads.removeValue(forKey: id)
                    self.preloadedChannels.remove(id)
                    self.allEventChannels.removeValue(forKey: id)
                }
                if case .channel(let id) = self.currentChannel, removedIds.contains(id) {
                    self.path = .init()
                    self.currentChannel = .home
                }
                self.servers[e.id] = t
                if e.data?.channels != nil || e.data?.categories != nil {
                    self.saveChannelCacheAsync()
                    self.saveServersCacheAsync()
                }
            }
            
        case .channel_create(let channel):
            // Store the channel in our event channels for lazy loading
            allEventChannels[channel.id] = channel
            
            // Handle different channel types
            switch channel {
            case .dm_channel(_):
                // DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                // print("📥 VIEWSTATE: Added new DM channel \(channel.id) immediately")
                
            case .group_dm_channel(_):
                // Group DMs are always loaded immediately
                self.channels[channel.id] = channel
                self.channelMessages[channel.id] = []
                self.dms.insert(channel, at: 0)
                // print("📥 VIEWSTATE: Added new Group DM channel \(channel.id) immediately")
                
            case .text_channel(let textChannel):
                // Server channels: only load if server is currently active
                if case .server(let currentServerId) = currentSelection,
                   currentServerId == textChannel.server {
                    // Load immediately if this server is active
                    self.channels[channel.id] = channel
                    self.channelMessages[channel.id] = []
                    // print("📥 VIEWSTATE: Added new text channel \(channel.id) immediately (server active)")
                } else {
                    // Just store for lazy loading later
                    // print("🔄 LAZY_CHANNEL: Stored new text channel \(channel.id) for lazy loading")
                }
                
                // Update server's channel list (duplicate guard §0.37)
                if let serverId = channel.server, var server = self.servers[serverId], !server.channels.contains(channel.id) {
                    server.channels.append(channel.id)
                    self.servers[serverId] = server
                }
                
            case .voice_channel(let voiceChannel):
                // Voice channels: only load if server is currently active
                if case .server(let currentServerId) = currentSelection,
                   currentServerId == voiceChannel.server {
                    self.channels[channel.id] = channel
                }
                if let serverId = channel.server, var server = self.servers[serverId], !server.channels.contains(channel.id) {
                    server.channels.append(channel.id)
                    self.servers[serverId] = server
                }
                
            default:
                break
            }
            
            if channel.server != nil {
                self.saveChannelCacheAsync()
                self.saveServersCacheAsync()
            }
            updateAppBadgeCount()
            
        case .channel_update(let e):
            
            if let index = self.dms.firstIndex(where: { $0.id == e.id }),
               case .group_dm_channel(var groupDMChannel) = self.dms[index] {
                
                
                if let name = e.data?.name {
                    groupDMChannel.name = name
                }
                
                if let icon = e.data?.icon {
                    groupDMChannel.icon = icon
                }
                
                if let description = e.data?.description {
                    groupDMChannel.description = description
                }
                
                if let nsfw = e.data?.nsfw {
                    groupDMChannel.nsfw = nsfw
                }
                
                if let permission = e.data?.permissions {
                    groupDMChannel.permissions = permission
                }
                
                if let owner = e.data?.owner {
                    groupDMChannel.owner = owner
                }
                
                if e.clear?.contains(.icon) == true {
                    groupDMChannel.icon = nil
                }
                
                if e.clear?.contains(.description) == true {
                    groupDMChannel.description = nil
                }
                
                
                
                self.dms[index] = .group_dm_channel(groupDMChannel)
                
            } else if let index = self.dms.firstIndex(where: { $0.id == e.id }),
                      case .dm_channel(let dmChannel) = self.dms[index] {
                
                //TODO
                
                self.dms[index] = .dm_channel(dmChannel)
                
            }
            
            if let channel = self.channels[e.id] {
                
                
                if case .group_dm_channel(var t) = channel {
                    if let name = e.data?.name {
                        t.name = name
                    }
                    
                    if let icon = e.data?.icon {
                        t.icon = icon
                    }
                    
                    
                    if let description = e.data?.description {
                        t.description = description
                    }
                    
                    if let nsfw = e.data?.nsfw {
                        t.nsfw = nsfw
                    }
                    
                    if let permission = e.data?.permissions {
                        t.permissions = permission
                    }
                    
                    if let owner = e.data?.owner {
                        t.owner = owner
                    }
                    
                    
                    if e.clear?.contains(.icon) == true {
                        t.icon = nil
                    }
                    
                    if e.clear?.contains(.description) == true {
                        t.description = nil
                    }
                    
                    
                    self.channels[e.id] = .group_dm_channel(t)
                    
                    
                } else if case .text_channel(var t) = channel {
                    if let name = e.data?.name {
                        t.name = name
                    }
                    
                    if let icon = e.data?.icon {
                        t.icon = icon
                    }
                    
                    if let description = e.data?.description {
                        t.description = description
                    }
                    
                    if let nsfw = e.data?.nsfw {
                        t.nsfw = nsfw
                    }
                    
                    if let default_permissions = e.data?.default_permissions {
                        t.default_permissions = default_permissions
                    }
                    
                    if let newRolePermissions = e.data?.role_permissions {
                        if t.role_permissions == nil {
                            t.role_permissions = newRolePermissions
                        } else {
                            for (roleId, permission) in newRolePermissions {
                                t.role_permissions?[roleId] = permission
                            }
                        }
                    }
                    
                    if e.clear?.contains(.icon) == true {
                        t.icon = nil
                    }
                    
                    if e.clear?.contains(.description) == true {
                        t.description = nil
                    }
                    
                    self.channels[e.id] = .text_channel(t)
                    
                } else if case .voice_channel(var v) = channel {
                    if let name = e.data?.name { v.name = name }
                    if let icon = e.data?.icon { v.icon = icon }
                    if let description = e.data?.description { v.description = description }
                    if let nsfw = e.data?.nsfw { v.nsfw = nsfw }
                    self.channels[e.id] = .voice_channel(v)
                }
            }
            if let ch = self.channels[e.id], ch.server != nil {
                self.allEventChannels[e.id] = ch
            }
            if self.allEventChannels[e.id] != nil || self.channels[e.id]?.server != nil {
                self.saveChannelCacheAsync()
                self.saveServersCacheAsync()
            }
            
        case .channel_delete(let e):
            self.deleteChannel(channelId: e.id)
            
        case .channel_group_leave(let e):
            if e.user == currentUser?.id {
                deleteChannel(channelId: e.id)
            } else {
                
                if case .group_dm_channel(var channel) = self.channels[e.id] {
                    channel.recipients.removeAll { $0 == e.user }
                    self.channels[e.id] = .group_dm_channel(channel)
                    if let index = dms.firstIndex(where: { $0.id == e.id }) {
                        dms[index] = .group_dm_channel(channel)
                    }
                } else {
                    //Todo
                }
                
            }
            
        case .channel_group_join(let e):
            if case .group_dm_channel(var channel) = self.channels[e.id] {
                channel.recipients.append(e.user)
                self.channels[e.id] = .group_dm_channel(channel)
                if let index = dms.firstIndex(where: { $0.id == e.id }) {
                    dms[index] = .group_dm_channel(channel)
                }

                // Fetch user in background — don't block batch event processing
                Task { [weak self] in
                    guard let self else { return }
                    let response = await self.http.fetchUser(user: e.user)
                    switch response {
                        case .success(let user):
                            if self.users.count < self.maxUsersInMemory {
                                self.users[user.id] = user
                            }
                            self.checkAndCleanupIfNeeded()
                        case .failure(let error):
                            print(error)
                    }
                }

            } else {
                //Todo other types channel
            }
            
            // MEMORY MANAGEMENT: Cleanup after new user
            checkAndCleanupIfNeeded()
            
            
            
        case .server_member_update(let e):
            let serverId = e.id.server
            let userId = e.id.user

            guard var serverMembers = members[serverId], var member = serverMembers[userId] else {
                return
            }

            // Apply updates only to non-nil fields
            if let newNickname = e.data?.nickname {
                member.nickname = newNickname
            }
            
            if let newAvatar = e.data?.avatar {
                member.avatar = newAvatar
            }
            
            if let newRoles = e.data?.roles {
                member.roles = newRoles
            }
            
            if let newJoinedAt = e.data?.joined_at {
                member.joined_at = newJoinedAt
            }
            
            if let newTimeout = e.data?.timeout {
                member.timeout = newTimeout
            }

            // Handle `clean` fields (removing values if specified)
            for field in e.clear {
                switch field {
                case .nickname:
                    member.nickname = nil
                case .avatar:
                    member.avatar = nil
                case .roles:
                    member.roles = nil
                case .timeout:
                    member.timeout = nil
                }
            }

            // Update the local members dictionary
            serverMembers[userId] = member
            members[serverId] = serverMembers
            
        case .server_member_join(let e):

            Task {
                async let fetchedUser = self.http.fetchUser(user: e.user)
                async let fetchedMember = self.http.fetchMember(server: e.id, member: e.user)

                // Wait for both API calls to complete
                let (userResult, memberResult) = await (fetchedUser, fetchedMember)
                
                
                switch userResult {
                    case .success(let user):
                        // MEMORY FIX: Only add users if we have space
                        if self.users.count < self.maxUsersInMemory {
                            self.users[e.user] = user
                            // print("📥 VIEWSTATE: Added user \(e.user) during server_member_join")
                        }
                        self.checkAndCleanupIfNeeded()
                    case .failure(_):
                         // print("error fetching user")
                        break
                }
                
                switch memberResult {
                    case .success(let member):
                        var serverMembers = self.members[e.id, default: [:]]
                        serverMembers[e.user] = member
                        self.members[e.id] = serverMembers
                    case .failure(_):
                         // print("error fetching member")
                        break
                }

            }
            
        case .server_member_leave(let e):
                if e.user == self.currentUser?.id {
                    self.updateMembershipCache(serverId: e.id, isMember: false)
                }
                guard var serverMembers = self.members[e.id] else {
                    return
                }
                serverMembers.removeValue(forKey: e.user)
                self.members[e.id] = serverMembers
            
        case .server_role_update(let e):
                // Ensure the server exists
                guard var server = self.servers[e.id] else {
                    return
                }
                
                // Ensure the roles dictionary exists
                var serverRoles = server.roles ?? [:]
                
                // Check if the role already exists
                var role = serverRoles[e.role_id] ?? Role(
                    name: e.data.name ?? "New Role",
                    permissions: e.data.permissions ?? Overwrite(a: .none, d: .none),
                    colour: e.data.colour,
                    hoist: e.data.hoist,
                    rank: e.data.rank ?? 0
                )

                // Update fields if they exist in the event
                if let name = e.data.name {
                    role.name = name
                }
                if let permissions = e.data.permissions as Overwrite? {
                    role.permissions = permissions
                }
                if let colour = e.data.colour {
                    role.colour = colour
                }
                if let hoist = e.data.hoist {
                    role.hoist = hoist
                }
                if let rank = e.data.rank {
                    role.rank = rank
                }

                // Remove fields specified in `clear`
                for field in e.clear {
                    switch field {
                    case .colour:
                        role.colour = nil
                    }
                }

                // Save the updated role
                serverRoles[e.role_id] = role
                server.roles = serverRoles
                self.servers[e.id] = server
            
            
        case .server_role_delete(let e):
                // Ensure the server exists
                guard var server = self.servers[e.id] else {
                    return
                }
                
                // Ensure the roles dictionary exists
                guard var serverRoles = server.roles else {
                    return
                }
            
                serverRoles.removeValue(forKey: e.role_id)
               
                // Update the server's roles
                server.roles = serverRoles
                self.servers[e.id] = server
            
        case .user_relationship(let event):
            updateUserRelationship(with: event)
            
        case .user_setting_update(let event):
            
            if let update = event.update {
                self.userSettingsStore.storeFetchData(settingsValues: update)
                
                if update["ordering"] != nil {
                    DispatchQueue.main.async {
                        self.applyServerOrdering()
                    }
                }
            }
            
        }
        
    }
}
