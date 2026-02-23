//
//  ViewState+ReadyEvent.swift
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
    // MARK: - Ready Event Processing Functions
    
    // Structure to hold only the data we need
    internal struct ReadyEventData {
        let channels: [Channel]
        let servers: [Server]
        let users: [Types.User]
        let members: [Member]
        let emojis: [Emoji]
    }
    
    // Extract only needed data from the large event
    internal func extractNeededDataFromReadyEvent(_ event: ReadyEvent) -> ReadyEventData {
        // print("🚀 VIEWSTATE: Extracting needed data from ready event")
        
        // Process all servers (removed limitation)
        let ordering = self.userSettingsStore.cache.orderSettings.servers
        let serverDict = Dictionary(uniqueKeysWithValues: event.servers.map { ($0.id, $0) })
        let orderedServers: [Server] = ordering.compactMap { serverDict[$0] }
        let remainingServers = event.servers.filter { !ordering.contains($0.id) }
        let allServers = orderedServers + remainingServers
        
        // print("   - Processing all \(event.servers.count) servers (no limitation)")
        
        // Get server IDs for channel filtering
        let serverIds = Set(allServers.map { $0.id })
        
        // LAZY LOADING: Store ALL channels but only load DMs immediately
        allEventChannels.removeAll() // Clear existing stored channels
        
        var neededChannels: [Channel] = [] // Only DMs will be loaded immediately
        var dmCount = 0
        var storedServerChannels = 0
        
        for channel in event.channels {
            // Store ALL channels for lazy loading
            allEventChannels[channel.id] = channel
            
            var shouldLoadNow = false
            
            switch channel {
            case .dm_channel(let dm):
                // ALWAYS load DMs immediately (both active and inactive)
                shouldLoadNow = true
                dmCount += 1
                // print("🚀 VIEWSTATE: Loading DM channel \(channel.id) immediately (active: \(dm.active))")
            case .group_dm_channel:
                // ALWAYS load Group DMs immediately
                shouldLoadNow = true
                dmCount += 1
                // print("🚀 VIEWSTATE: Loading Group DM channel \(channel.id) immediately")
            case .text_channel(let textChannel):
                // Store server channels but don't load them yet
                if serverIds.contains(textChannel.server) {
                    storedServerChannels += 1
                    // print("🔄 LAZY_CHANNEL: Stored text channel \(channel.id) for server \(textChannel.server)")
                }
            case .voice_channel(let voiceChannel):
                // Store voice channels but don't load them yet
                if serverIds.contains(voiceChannel.server) {
                    storedServerChannels += 1
                    // print("🔄 LAZY_CHANNEL: Stored voice channel \(channel.id) for server \(voiceChannel.server)")
                }
            default:
                break
            }
            
            if shouldLoadNow {
                neededChannels.append(channel)
            }
        }
        
        // print("   - Stored \(allEventChannels.count) total channels for lazy loading")
        // print("   - Loading immediately: \(neededChannels.count) channels (DMs: \(dmCount))")
        // print("   - Stored for lazy loading: \(storedServerChannels) server channels")
        
        // Return only the data we need
        return ReadyEventData(
            channels: neededChannels,
            servers: allServers,
            users: event.users, // Keep all users for now
            members: event.members,
            emojis: event.emojis
        )
    }
    
    // Process the extracted data
    internal func processReadyData(_ data: ReadyEventData) async {
        let processReadySpan = launchTransaction?.startChild(operation: "processReady")
        
        // Process channels
        processChannelsFromData(data.channels)
        
        // Process servers
        processServersFromData(data.servers)
        
        // Process users
        processUsers(data.users)
        
        // EMERGENCY: If still too many users, force immediate cleanup
        if users.count > maxUsersInMemory {
            // print("🚨 EMERGENCY: Still have \(users.count) users after processing, forcing cleanup!")
            let currentUserId = currentUser?.id
            let currentUserObject = currentUser
            
            users.removeAll()
            
            if let currentUserId = currentUserId, let currentUserObject = currentUserObject {
                users[currentUserId] = currentUserObject
                currentUser = currentUserObject
            }
            
            // print("🚨 EMERGENCY CLEANUP: Reduced users to \(users.count)")
        }
        
        // Process members
        processMembers(data.members)
        
        // Process DMs
        processDMs(channels: Array(channels.values))
        
        // Process emojis
        for emoji in data.emojis {
            self.emojis[emoji.id] = emoji
        }
        
        // MEMORY FIX: Don't fetch unreads here - it might trigger another ready event
        // We'll fetch them separately after full initialization
        // print("🚀 VIEWSTATE: Skipping unreads fetch during ready processing to prevent memory spike")
        
        // Update state
        state = .connected
        wsCurrentState = .connected
        ws?.currentState = .connected
        ws?.retryCount = 0
        if let uid = currentUser?.id, let url = baseURL {
            MessageCacheWriter.shared.setSession(userId: uid, baseURL: url)
        }
        
        await verifyStateIntegrity()
        
        processReadySpan?.finish()
        launchTransaction?.finish()
        
        // Check for stale messages
        for channel in channels.values {
            if let last_message_id = channel.last_message_id,
               let last_cached_message = channelMessages[channel.id]?.last,
               last_message_id != last_cached_message
            {
                channelMessages[channel.id] = []
            }
        }
        
        // print("🚀 VIEWSTATE: Ready event processing completed")
        // print("   - Final channels: \(channels.count)")
        // print("   - Final users: \(users.count)")
        // print("   - Final servers: \(servers.count)")
        
        // Retry any pending notification token upload
        if pendingNotificationToken != nil {
            // print("🔄 READY_EVENT: Found pending notification token, attempting retry...")
            Task {
                await retryUploadNotificationToken()
            }
        }
        
        // MEMORY FIX: Fetch unreads separately to prevent memory spike
        Task {
            // print("🚀 VIEWSTATE: Starting unreads fetch after ready completion")
            if let remoteUnreads = try? await http.fetchUnreads().get() {
                await MainActor.run {
                    for unread in remoteUnreads {
                        unreads[unread.id.channel] = unread
                    }
                    // print("🚀 VIEWSTATE: Unreads loaded: \(remoteUnreads.count)")
                    
                    // Update app badge count after loading unreads from server
                    updateAppBadgeCount()
                    print("🔔 Updated badge count after loading \(remoteUnreads.count) unreads from server (mentions not counted)")
                }
            }
        }
    }
    
    private func processChannelsFromData(_ eventChannels: [Channel]) {
        // print("🚀 VIEWSTATE: Processing \(eventChannels.count) channels from WebSocket")
        // print("🚀 VIEWSTATE: Existing channels count: \(channels.count)")
        
        // CRITICAL FIX: Don't clear existing channels - merge instead
        // Only clear channelMessages as they should be fresh from server
        channelMessages.removeAll()
        
        var messageArrayCount = 0
        var dmChannels = 0
        var groupDmChannels = 0
        var textChannels = 0
        
        // Process all channels (already filtered)
        for channel in eventChannels {
            channels[channel.id] = channel
            
            // Create message array for messageable channels
            switch channel {
            case .dm_channel(let dm):
                // Create message array for ALL DMs (active and inactive)
                channelMessages[channel.id] = []
                messageArrayCount += 1
                dmChannels += 1
                // print("🚀 VIEWSTATE: Added DM channel \(channel.id) (active: \(dm.active))")
            case .group_dm_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                groupDmChannels += 1
                // print("🚀 VIEWSTATE: Added Group DM channel \(channel.id)")
            case .text_channel:
                channelMessages[channel.id] = []
                messageArrayCount += 1
                textChannels += 1
            default:
                break
            }
        }
        
        // print("🚀 VIEWSTATE: Stored \(channels.count) channels, created \(messageArrayCount) message arrays")
        // print("🚀 VIEWSTATE: Channel breakdown - DMs: \(dmChannels), Group DMs: \(groupDmChannels), Text: \(textChannels)")
    }
    
    private func processServersFromData(_ servers: [Server]) {
        // print("🚀 VIEWSTATE: Processing \(servers.count) servers from WebSocket")
        // print("🚀 VIEWSTATE: Existing servers count: \(self.servers.count)")
        
        let readyServerIds = Set(servers.map { $0.id })
        
        // Merge Ready servers into self.servers
        for server in servers {
            self.servers[server.id] = server
            if members[server.id] == nil {
                members[server.id] = [:]
            }
        }
        
        // Treat Ready as authoritative: remove servers not in payload (e.g. left on another device)
        for key in self.servers.keys.filter({ !readyServerIds.contains($0) }) {
            self.servers.removeValue(forKey: key)
        }
        
        // Sync membership cache: user is member of all servers in Ready payload
        for server in servers {
            updateMembershipCache(serverId: server.id, isMember: true)
        }
        
        // Reconcile membership cache: mark as non-member any cached server not in Ready payload
        for serverId in discoverMembershipCache.keys where !readyServerIds.contains(serverId) {
            updateMembershipCache(serverId: serverId, isMember: false)
        }
        
        // Apply ordering before saving cache to ensure correct order is persisted
        self.applyServerOrdering()
        self.saveServersCacheAsync()
    }
}
