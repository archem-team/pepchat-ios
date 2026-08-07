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
    /// Max message IDs stored per channel in UserDefaults (full in-memory lists are unchanged).
    internal static let channelMessagesPersistenceCapPerChannel = 200

    /// Snapshot for persistence — caps ID lists so JSON encode does not allocate multi‑GB buffers.
    @MainActor
    internal func channelMessagesPersistenceSnapshot() -> [String: [String]] {
        let cap = Self.channelMessagesPersistenceCapPerChannel
        var snapshot: [String: [String]] = [:]
        snapshot.reserveCapacity(channelMessages.count)
        for (channelId, ids) in channelMessages {
            snapshot[channelId] = ids.count <= cap ? ids : Array(ids.suffix(cap))
        }
        return snapshot
    }

    @MainActor
    internal func enforceMemoryLimits() {
        if isLoadingOlderMessages { return }

        let activeChannelId: String? = {
            if case .channel(let id) = currentChannel { return id }
            return nil
        }()

        // Remove excess messages from the global store
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
        
        // Trim per-channel ID lists (keep the channel the user is viewing intact)
        for (channelId, messageIds) in channelMessages {
            guard channelId != activeChannelId, messageIds.count > maxChannelMessages else { continue }
            channelMessages[channelId] = Array(messageIds.suffix(maxChannelMessages))
        }

        cleanupOrphanedMessages()
    }

    @MainActor
    private func smartMessageCleanup() {
        enforceMemoryLimits()
    }

    @MainActor
    internal func smartUserCleanup() {
        guard users.count > maxUsersInMemory, users.count <= 2000 else { return }
        let excluding: String = {
            if case .channel(let id) = currentChannel { return id }
            return ""
        }()
        cleanupUnusedUsersInstant(excludingChannelId: excluding)
    }

    @MainActor
    private func cleanupMemory() {
        enforceMemoryLimits()
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
        // Wait for connected state (up to 5 seconds) instead of fixed 2-second sleep
        let deadline = Date().addingTimeInterval(5.0)
        while state != .connected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000) // Poll every 200ms
        }
        
        // Only preload if user is authenticated and WebSocket is connected
        guard sessionToken != nil, currentUser != nil, state == .connected else {
            // print("🚀 PRELOAD: Skipping preload - user not authenticated or not connected (state: \(state))")
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
            // print("🚀 PRELOAD: Added \(textChannels.count) channels from current server \(serverId)")
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
        // print("🚀 PRELOAD: Added \(activeDMs.count) DM channels")
        
        // Always include the specific channel mentioned by user
        let specificChannelId = "01J7QTT66242A7Q26A2FH5TD48"
        if !channelsToPreload.contains(specificChannelId) {
            channelsToPreload.append(specificChannelId)
            // print("🚀 PRELOAD: Added specific channel \(specificChannelId)")
        }
        
        // print("🚀 PRELOAD: Starting preload for \(channelsToPreload.count) channels")
        
        // Preload at most two channels at a time to avoid memory/network spikes
        let channelList = Array(channelsToPreload)
        for chunkStart in stride(from: 0, to: channelList.count, by: 2) {
            let chunkEnd = min(chunkStart + 2, channelList.count)
            let chunk = Array(channelList[chunkStart..<chunkEnd])
            await withTaskGroup(of: Void.self) { group in
                for channelId in chunk {
                    group.addTask {
                        await self.preloadChannel(channelId: channelId)
                    }
                }
            }
        }
        
        // print("🚀 PRELOAD: Completed preloading \(channelsToPreload.count) channels")
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
        // print("⚡ VIEWSTATE_INSTANT_CLEANUP: Starting IMMEDIATE cleanup for channel \(channelId)")

        let initialMessageCount = messages.count
        let initialUserCount = users.count
        let channelMessageCount = channelMessages[channelId]?.count ?? 0

        // 1. Capture message IDs for this channel then clear list (avoids iterating entire messages dict = memory spike)
        let messageIdsToRemove = channelMessages[channelId] ?? []
        channelMessages.removeValue(forKey: channelId)

        // 2. IMMEDIATE: Remove message objects for this channel only (O(channel size), not O(total messages))
        for messageId in messageIdsToRemove {
            messages.removeValue(forKey: messageId)
        }

        // 3. IMMEDIATE: Clear all related data
        clearTyping(forChannel: channelId)
        preloadedChannels.remove(channelId)
        atTopOfChannel.remove(channelId)

        // 4. Skip heavy user cleanup when already memory-heavy to avoid OOM (offline/cached scroll scenario).
        // Also skip when user count is very high: cleanupUnusedUsersInstant allocates large temporaries and can trigger jetsam (Channel.md §12.2).
        if !preserveForNavigation, initialMessageCount <= 1500, initialUserCount <= 2000 {
            cleanupUnusedUsersInstant(excludingChannelId: channelId)
        }
        
        // 5. IMMEDIATE: Force garbage collection
        _ = messages.count + users.count + channelMessages.count
        
        let finalMessageCount = messages.count
        let finalUserCount = users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        // print("⚡ VIEWSTATE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        // print("⚡ FREED: \(initialMessageCount - finalMessageCount) messages, \(initialUserCount - finalUserCount) users, \(channelMessageCount) channel messages")
    }
    
    /// Clean up users that are no longer needed after leaving a channel
    @MainActor
    private func cleanupUnusedUsers(excludingChannelId: String) {
        // print("👥 USER_CLEANUP: Starting cleanup of unused users")
        
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
        // print("👥 USER_CLEANUP: Removed \(usersToRemove.count) unused users (\(initialUserCount) -> \(finalUserCount))")
    }
    
    /// INSTANT force memory cleanup - IMMEDIATE execution
    @MainActor
    func forceMemoryCleanup() {
        let startTime = CFAbsoluteTimeGetCurrent()
        // print("⚡ FORCE_INSTANT_CLEANUP: Starting IMMEDIATE memory cleanup")
        
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
        
        // 2. IMMEDIATE: Enforce user limits (skip when already very high to avoid OOM spike from cleanupUnusedUsersInstant; see Channel.md §12.2)
        if users.count > maxUsersInMemory, users.count <= 2000 {
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
        
        // print("⚡ FORCE_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms")
        // print("   Messages: \(initialStats.messages) -> \(finalStats.messages)")
        // print("   Users: \(initialStats.users) -> \(finalStats.users)")
        // print("   Channels: \(initialStats.channels) -> \(finalStats.channels)")
    }
    
}
