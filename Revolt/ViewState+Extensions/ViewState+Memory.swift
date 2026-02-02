//
//  ViewState+Memory.swift
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
    @MainActor
    internal func enforceMemoryLimits() {
        // CRITICAL FIX: Completely disable enforceMemoryLimits to prevent infinite loop and black messages
        // print("🚫 MEMORY_CLEANUP: enforceMemoryLimits DISABLED to prevent infinite loop and black messages")
        return
        
        // Check current memory usage
        let currentMemoryMB = getCurrentMemoryUsage()
        
        // EMERGENCY MEMORY RESET if over 4GB
        if currentMemoryMB > 4000 {
            // print("🚨 EMERGENCY: Memory over 4GB (\(currentMemoryMB)MB)! Performing complete reset!")
            
            // Clear everything except current user
            let currentUserId = currentUser?.id
            let currentUserObject = currentUser
            
            messages.removeAll()
            channelMessages.removeAll()
            users.removeAll()
            channels.removeAll()
            servers.removeAll()
            members.removeAll()
            dms.removeAll()
            emojis.removeAll()
            unreads.removeAll()
            
            // Restore only current user
            if let currentUserId = currentUserId, let currentUserObject = currentUserObject {
                users[currentUserId] = currentUserObject
                currentUser = currentUserObject
            }
            
            // print("🚨 EMERGENCY RESET COMPLETED! Memory should now be minimal.")
            return
        }
        
                    // AGGRESSIVE MEMORY CLEANUP if over 2GB (increased threshold for better performance)
            if currentMemoryMB > 2000 {
                // print("🚨 AGGRESSIVE CLEANUP: Memory over 2GB (\(currentMemoryMB)MB)!")
                
                // VIRTUAL SCROLLING PROTECTION: Skip aggressive cleanup if in DM view
                if currentSelection == .dms {
                    // print("🔄 VIRTUAL_DM: Skipping aggressive cleanup - user is in DM view with Virtual Scrolling active")
                    return
                }
                
                                    // CRITICAL FIX: Keep ALL users to prevent black messages - only clear non-essential data
                    // print("🚨 EMERGENCY: Keeping ALL users to prevent black messages")
                    // Don't touch users at all - they are needed for message display
                
                // Keep only last 100 messages
                let sortedMessages = messages.sorted { $0.value.id > $1.value.id }
                let recentMessages = Array(sortedMessages.prefix(100))
                messages = Dictionary(uniqueKeysWithValues: recentMessages)
                
                // Keep ALL DMs and current channel
                var channelsToKeep: [String: Channel] = [:]
                
                if case .channel(let currentChannelId) = currentChannel {
                    if let currentChannel = channels[currentChannelId] {
                        channelsToKeep[currentChannelId] = currentChannel
                    }
                }
                
                // Keep ALL DM and Group DM channels (don't limit to 10)
                for channel in channels.values {
                    switch channel {
                    case .dm_channel:
                        channelsToKeep[channel.id] = channel
                    case .group_dm_channel:
                        channelsToKeep[channel.id] = channel
                    default:
                        break
                    }
                }
                
                channels = channelsToKeep
                
                // Clear all but essential channel messages
                for (channelId, _) in channelMessages {
                    if channelsToKeep[channelId] != nil {
                        channelMessages[channelId] = Array((channelMessages[channelId] ?? []).suffix(10))
                    } else {
                        channelMessages.removeValue(forKey: channelId)
                    }
                }
                
                // Keep more servers in emergency cleanup (increased from 5 to 20)
                let topServers = Array(servers.prefix(20))
                servers = OrderedDictionary(uniqueKeysWithValues: topServers)
                
                // FIX: Don't clear DM list state during aggressive cleanup
                if isDmListInitialized {
                    // Keep DM list state intact, just reinitialize it
                    reinitializeDmListFromCache()
                }
                
                // print("🚨 AGGRESSIVE CLEANUP COMPLETED!")
                return
            }
        
        // NORMAL CLEANUP: Remove excess messages
        if messages.count > maxMessagesInMemory {
            // print("🧠 MEMORY: Enforcing message limit. Current: \(messages.count), Max: \(maxMessagesInMemory)")
            
            // Get all message IDs sorted by timestamp (older first)
            let sortedMessageIds = messages.keys.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            // Calculate how many messages to remove
            let messagesToRemove = messages.count - maxMessagesInMemory
            let idsToRemove = Array(sortedMessageIds.prefix(messagesToRemove))
            
            // Remove messages
            for id in idsToRemove {
                messages.removeValue(forKey: id)
            }
            
            // Clean up channel message references
            for (channelId, messageIds) in channelMessages {
                let filteredIds = messageIds.filter { !idsToRemove.contains($0) }
                if filteredIds.count != messageIds.count {
                    channelMessages[channelId] = filteredIds
                }
            }
            
            // print("🧠 MEMORY: Removed \(messagesToRemove) old messages")
        }
        
        // AGGRESSIVE CHANNEL MESSAGE CLEANUP
        for (channelId, messageIds) in channelMessages {
            if messageIds.count > maxChannelMessages {
                let trimmedIds = Array(messageIds.suffix(maxChannelMessages))
                channelMessages[channelId] = trimmedIds
                // print("🧠 MEMORY: Trimmed channel \(channelId) messages from \(messageIds.count) to \(trimmedIds.count)")
            }
        }
    }

    // DISABLED: Smart message cleanup based on current channel and loading direction
    @MainActor
    private func smartMessageCleanup() {
        // CRITICAL FIX: Disable message cleanup to prevent black messages
        // print("🚫 MEMORY_CLEANUP: smartMessageCleanup DISABLED to prevent black messages")
        return
    }
    
    // Smart user cleanup to prevent excessive memory usage - DISABLED to prevent black messages
    @MainActor
    internal func smartUserCleanup() {
        // CRITICAL FIX: Completely disable user cleanup to prevent black messages
        // print("🧠 MEMORY: User cleanup DISABLED to prevent black messages. Current users: \(users.count)")
        
        // Only log warning if we have too many users, but don't clean them up
        if users.count > maxUsersInMemory {
            // print("⚠️ MEMORY WARNING: \(users.count) users exceed limit of \(maxUsersInMemory), but cleanup is disabled")
        }
        
        return // Exit early, no cleanup
    }
    
    
    @MainActor
    private func cleanupMemory() {
        // CRITICAL FIX: Completely disable cleanupMemory to prevent infinite loop and black messages
        // print("🚫 MEMORY: cleanupMemory DISABLED to prevent infinite loop and black messages")
        return
    }
    
    // Smart channel cleanup to prevent excessive memory usage
    @MainActor
    internal func smartChannelCleanup() {
        // FIX: Don't cleanup when in DM view or when DM list is being displayed
        if currentSelection == .dms {
            // print("🧠 MEMORY: Skipping channel cleanup - in DM view")
            return
        }
        
        // Clean up channels that haven't been accessed
        if channels.count > maxChannelsInMemory {
            // print("🧠 MEMORY: Enforcing channel limit. Current: \(channels.count), Max: \(maxChannelsInMemory)")
            
            var essentialChannelIds = Set<String>()
            
            // Keep current channel
            if case .channel(let channelId) = currentChannel {
                essentialChannelIds.insert(channelId)
            }
            
            // ALWAYS keep ALL DM and Group DM channels (NEVER remove these!)
            for channel in channels.values {
                switch channel {
                case .dm_channel:
                    essentialChannelIds.insert(channel.id)
                case .group_dm_channel:
                    essentialChannelIds.insert(channel.id)
                default:
                    break
                }
            }
            
            // Keep channels in current server only
            if case .server(let serverId) = currentSelection {
                if let server = servers[serverId] {
                    // Only keep current server's channels to free memory
                    for channelId in server.channels {
                        if essentialChannelIds.count < maxChannelsInMemory {
                            essentialChannelIds.insert(channelId)
                        }
                    }
                }
            }
            
            // Remove non-essential channels (only server channels from other servers)
            let channelsToRemove = channels.keys.filter { channelId in
                if essentialChannelIds.contains(channelId) {
                    return false
                }
                
                // Check if it's a server text channel from non-current server
                if let channel = channels[channelId] {
                    switch channel {
                    case .text_channel:
                        return true // Remove server channels that aren't essential
                    case .voice_channel:
                        return true // Remove voice channels
                    default:
                        return false // Never remove DMs
                    }
                }
                return false
            }
            
            for channelId in channelsToRemove {
                channels.removeValue(forKey: channelId)
                channelMessages.removeValue(forKey: channelId)
            }
            
            // print("🧠 MEMORY: Removed \(channelsToRemove.count) non-essential channels (kept all DMs)")
        }
        
        // Clean up empty channel message arrays for server channels only
        let emptyChannels = channelMessages.filter { channelId, messages in
            if messages.isEmpty {
                // Check if it's a DM - if so, don't remove
                if let channel = channels[channelId] {
                    switch channel {
                    case .dm_channel, .group_dm_channel:
                        return false // Never remove DM message arrays
                    default:
                        return true // Can remove server channel message arrays if empty
                    }
                }
                return true
            }
            return false
        }.map { $0.key }
        
        if emptyChannels.count > 100 {
            // print("🧠 MEMORY: Cleaning up \(emptyChannels.count) empty server channel message arrays")
            for channelId in emptyChannels {
                // Only remove if it's not current channel and not a DM
                if case .channel(let currentChannelId) = currentChannel, currentChannelId == channelId {
                    continue
                }
                channelMessages.removeValue(forKey: channelId)
            }
        }
    }
    
    // Helper function to clean up messages that don't belong to any channel
    @MainActor
    internal func cleanupOrphanedMessages() {
        let allChannelMessageIds = Set(channelMessages.values.flatMap { $0 })
        let messagesToRemove = messages.keys.filter { messageId in
            !allChannelMessageIds.contains(messageId)
        }
        
        for messageId in messagesToRemove {
            messages.removeValue(forKey: messageId)
        }
        
        if !messagesToRemove.isEmpty {
            // print("🧠 MEMORY: Cleaned up \(messagesToRemove.count) orphaned messages")
        }
    }
    
    /// Preloads messages for important channels when the app starts or WebSocket reconnects
    @MainActor
    internal func preloadImportantChannels() async {
        // Wait a bit for the WebSocket to fully authenticate
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Only preload if user is authenticated and WebSocket is connected
        guard sessionToken != nil, currentUser != nil, state == .connected else {
            print("🚀 PRELOAD: Skipping preload - user not authenticated or not connected (state: \(state))")
            return
        }
        
        // SMART PRELOADING: Get channels from user's current server and DMs
        var channelsToPreload: [String] = []
        
        // Add current server's channels
        if case .server(let serverId) = currentSelection,
           let server = servers[serverId] {
            // Add first few text channels from current server
            let textChannels = server.channels.compactMap { channelId in
                if case .text_channel(_) = channels[channelId] {
                    return channelId
                }
                return nil
            }.prefix(3) // Preload first 3 text channels
            
            channelsToPreload.append(contentsOf: textChannels)
            print("🚀 PRELOAD: Added \(textChannels.count) channels from current server \(serverId)")
        }
        
        // Add active DM channels
        let activeDMs = dms.compactMap { channel -> String? in
            switch channel {
            case .dm_channel(let dm):
                return dm.active ? dm.id : nil
            case .group_dm_channel(let group):
                return group.id
            default:
                return nil
            }
        }.prefix(5) // Preload first 5 DMs
        
        channelsToPreload.append(contentsOf: activeDMs)
        print("🚀 PRELOAD: Added \(activeDMs.count) DM channels")
        
        // Always include the specific channel mentioned by user
        let specificChannelId = "01J7QTT66242A7Q26A2FH5TD48"
        if !channelsToPreload.contains(specificChannelId) {
            channelsToPreload.append(specificChannelId)
            print("🚀 PRELOAD: Added specific channel \(specificChannelId)")
        }
        
        print("🚀 PRELOAD: Starting preload for \(channelsToPreload.count) channels")
        
        // Preload channels in parallel for better performance
        await withTaskGroup(of: Void.self) { group in
            for channelId in channelsToPreload {
                group.addTask {
                    await self.preloadChannel(channelId: channelId)
        }
            }
        }
        
        print("🚀 PRELOAD: Completed preloading \(channelsToPreload.count) channels")
    }
    
    /// Public method to preload a specific channel by ID
    @MainActor
    public func preloadSpecificChannel(channelId: String) async {
        await preloadChannel(channelId: channelId)
    }
    
    internal func startPeriodicMemoryCleanup() {
        memoryCleanupTimer?.invalidate()
        
        // Clean up memory every 15 seconds for better stability
        memoryCleanupTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor [weak self] in
                self?.cleanupMemory()
            }
        }
        
        // Start memory monitoring
        startMemoryMonitoring()
    }
    
    /// INSTANT cleanup for a specific channel when leaving it - NO DELAYS
    @MainActor
    func cleanupChannelFromMemory(channelId: String, preserveForNavigation: Bool = false) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⚡ VIEWSTATE_INSTANT_CLEANUP: Starting IMMEDIATE cleanup for channel \(channelId)")
        
        let initialMessageCount = messages.count
        let initialUserCount = users.count
        let channelMessageCount = channelMessages[channelId]?.count ?? 0
        
        // 1. IMMEDIATE: Clear channel messages list
        channelMessages.removeValue(forKey: channelId)
        
        // 2. IMMEDIATE: Remove all message objects for this channel
        let messagesToRemove = messages.keys.filter { messageId in
            if let message = messages[messageId] {
                return message.channel == channelId
            }
            return false
        }
        
        for messageId in messagesToRemove {
            messages.removeValue(forKey: messageId)
        }
        
        // 3. IMMEDIATE: Clear all related data
        currentlyTyping.removeValue(forKey: channelId)
        preloadedChannels.remove(channelId)
        atTopOfChannel.remove(channelId)
        
        // 4. IMMEDIATE: Clean up users if not preserving for navigation
        if !preserveForNavigation {
            cleanupUnusedUsersInstant(excludingChannelId: channelId)
        }
        
        // 5. IMMEDIATE: Force garbage collection
        _ = messages.count + users.count + channelMessages.count
        
        let finalMessageCount = messages.count
        let finalUserCount = users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ VIEWSTATE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        print("⚡ FREED: \(initialMessageCount - finalMessageCount) messages, \(initialUserCount - finalUserCount) users, \(channelMessageCount) channel messages")
    }
    
    /// Clean up users that are no longer needed after leaving a channel
    @MainActor
    private func cleanupUnusedUsers(excludingChannelId: String) {
        print("👥 USER_CLEANUP: Starting cleanup of unused users")
        
        var usersToKeep = Set<String>()
        
        // Always keep current user
        if let currentUserId = currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        
        // Keep users from all active channels (except the one we're leaving)
        for (otherChannelId, messageIds) in channelMessages {
            if otherChannelId == excludingChannelId { continue }
            
            // Keep users from channel recipients (for DMs)
            if let channel = channels[otherChannelId] {
                usersToKeep.formUnion(channel.recipients)
            }
            
            // Keep message authors and mentioned users
            for messageId in messageIds {
                if let message = messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }
        
        // Keep users from servers (owners and members)
        for server in servers.values {
            usersToKeep.insert(server.owner)
            if let serverMembers = members[server.id] {
                usersToKeep.formUnion(serverMembers.keys)
            }
        }
        
        // Keep users from DM list
        for dm in dms {
            usersToKeep.formUnion(dm.recipients)
        }
        
        // Remove users that are no longer needed
        let initialUserCount = users.count
        let usersToRemove = users.keys.filter { userId in
            !usersToKeep.contains(userId) && userId != currentUser?.id
        }
        
        for userId in usersToRemove {
            users.removeValue(forKey: userId)
            
            // Also remove from members if they exist
            for serverId in members.keys {
                members[serverId]?.removeValue(forKey: userId)
            }
        }
        
        let finalUserCount = users.count
        print("👥 USER_CLEANUP: Removed \(usersToRemove.count) unused users (\(initialUserCount) -> \(finalUserCount))")
    }
    
    /// INSTANT force memory cleanup - IMMEDIATE execution
    @MainActor
    func forceMemoryCleanup() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⚡ FORCE_INSTANT_CLEANUP: Starting IMMEDIATE memory cleanup")
        
        let initialStats = (
            messages: messages.count,
            users: users.count,
            channels: channelMessages.count
        )
        
        // 1. IMMEDIATE: Enforce message limits aggressively
        if messages.count > maxMessagesInMemory {
            let sortedMessageIds = messages.keys.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 < date2
            }
            
            let messagesToRemove = messages.count - maxMessagesInMemory
            let idsToRemove = Array(sortedMessageIds.prefix(messagesToRemove))
            
            for id in idsToRemove {
                messages.removeValue(forKey: id)
            }
            
            // Clean up channel message references
            for (channelId, messageIds) in channelMessages {
                let filteredIds = messageIds.filter { !idsToRemove.contains($0) }
                channelMessages[channelId] = filteredIds
            }
        }
        
        // 2. IMMEDIATE: Enforce user limits
        if users.count > maxUsersInMemory {
            cleanupUnusedUsersInstant(excludingChannelId: "")
        }
        
        // 3. IMMEDIATE: Clean up empty channel message arrays
        for (channelId, messageIds) in channelMessages {
            if messageIds.isEmpty {
                channelMessages.removeValue(forKey: channelId)
            }
        }
        
        // 4. IMMEDIATE: Force garbage collection
        _ = messages.count + users.count + channelMessages.count
        
        let finalStats = (
            messages: messages.count,
            users: users.count,
            channels: channelMessages.count
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ FORCE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        print("   Messages: \(initialStats.messages) -> \(finalStats.messages)")
        print("   Users: \(initialStats.users) -> \(finalStats.users)")
        print("   Channels: \(initialStats.channels) -> \(finalStats.channels)")
    }
    
}
