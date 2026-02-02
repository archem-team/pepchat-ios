//
//  ViewState+Notifications.swift
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
    /// Retry uploading pending notification token
    func retryUploadNotificationToken() async {
        guard let token = pendingNotificationToken else { return }
        
        // print("🔄 RETRY_NOTIFICATION_TOKEN: Attempting to upload previously failed token...")
        
        let response = await http.uploadNotificationToken(token: token)
        switch response {
            case .success:
                // print("✅ RETRY_NOTIFICATION_TOKEN: Successfully uploaded pending token")
                pendingNotificationToken = nil // Clear pending token after success
                UserDefaults.standard.removeObject(forKey: "pendingNotificationToken")
            case .failure(let error):
                print("❌ RETRY_NOTIFICATION_TOKEN: Failed again: \(error)")
                // Keep the pending token for next retry
        }
    }
    
    /// Store notification token for later retry
    func storePendingNotificationToken(_ token: String) {
        pendingNotificationToken = token
        UserDefaults.standard.set(token, forKey: "pendingNotificationToken")
    }
    
    /// Load any pending notification token from storage
    func loadPendingNotificationToken() {
        pendingNotificationToken = UserDefaults.standard.string(forKey: "pendingNotificationToken")
        if pendingNotificationToken != nil {
            // print("📱 PENDING_TOKEN_FOUND: Found pending notification token to upload")
        }
    }
    
    // MARK: - App Badge Management
    
    /// Calculates the total unread count across all channels and updates the app badge
    func updateAppBadgeCount() {
        guard let application = ViewState.application else { return }
        
        var totalUnreadCount = 0
        var totalMentionCount = 0
        
        // Iterate through all unreads
        for (channelId, unread) in unreads {
            // Get channel info
            let channel = channels[channelId] ?? allEventChannels[channelId]
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                continue
            }
            
            // Check if channel is muted
            let channelNotificationState = userSettingsStore.cache.notificationSettings.channel[channelId]
            let isChannelMuted = channelNotificationState == .muted || channelNotificationState == .none
            
            // Check if server is muted (only for server channels, not DMs or group DMs)
            var isServerMuted = false
            if let serverId = channel.server {
                let serverNotificationState = userSettingsStore.cache.notificationSettings.server[serverId]
                isServerMuted = serverNotificationState == .muted || serverNotificationState == .none
            }
            // For DMs and group DMs, server is nil, so isServerMuted stays false
            
            // Skip if channel or server is muted
            if isChannelMuted || isServerMuted {
                continue
            }
            
            // Count unread channels (including group DMs)
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    totalUnreadCount += 1
                    
                    // Debug log for group DMs
                    if case .group_dm_channel(let groupDM) = channel {
                        print("🔔 Badge: Counting group DM '\(groupDM.name)' as unread")
                    }
                }
            }
        }
        
        // Total badge count is only unread channels (not mentions)
        let finalBadgeCount = totalUnreadCount
        
        // Update app badge count
        DispatchQueue.main.async {
            let currentBadge = application.applicationIconBadgeNumber
            application.applicationIconBadgeNumber = finalBadgeCount
            print("🔔 Badge: \(currentBadge) -> \(finalBadgeCount) (unreads: \(totalUnreadCount))")
        }
    }
    
    /// Clears the app badge count
    func clearAppBadge() {
        guard let application = ViewState.application else { return }
        
        DispatchQueue.main.async {
            application.applicationIconBadgeNumber = 0
            print("🔔 Cleared app badge count")
        }
    }
    
    /// Manually refreshes the app badge count - useful for debugging or when the count seems incorrect
    func refreshAppBadge() {
        print("🔔 Manually refreshing app badge count...")
        updateAppBadgeCount()
    }
    
    /// Preload recent messages for channels in a server to improve performance
    internal func preloadMessagesForServer(serverId: String) {
        // Cancel any existing preloading task for this server
        preloadingTasks[serverId]?.cancel()
        
        guard let server = servers[serverId] else { return }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Get text channels that don't have messages loaded yet
            let channelsToPreload = server.channels.compactMap { channelId -> String? in
                guard let channel = self.channels[channelId] else { return nil }
                
                // Only preload text channels
                switch channel {
                case .text_channel(_):
                    // Only preload if we don't have messages or have very few
                    let existingMessageCount = self.channelMessages[channelId]?.count ?? 0
                    return existingMessageCount < 5 ? channelId : nil
                default:
                    return nil
                }
            }
            
            // Limit concurrent preloading to avoid overwhelming the API
            let maxConcurrentPreloads = 3
            for channelBatch in channelsToPreload.chunked(into: maxConcurrentPreloads) {
                await withTaskGroup(of: Void.self) { group in
                    for channelId in channelBatch {
                        group.addTask {
                            await self.preloadChannelMessages(channelId: channelId, serverId: serverId)
                        }
                    }
                }
                
                // Small delay between batches to be respectful to the API
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        preloadingTasks[serverId] = task
    }
    
    private func preloadChannelMessages(channelId: String, serverId: String) async {
        // Check if task was cancelled
        guard !Task.isCancelled else { return }
        
        do {
            // SMART LIMIT: Use 10 for specific channel in specific server, 20 for others in preload
            let messageLimit = (channelId == "01J7QTT66242A7Q26A2FH5TD48" && serverId == "01J544PT4T3WQBVBSDK3TBFZW7") ? 10 : maxPreloadedMessagesPerChannel
            
            let result = try await http.fetchHistory(
                channel: channelId,
                limit: messageLimit,
                before: nil,
                server: serverId,
                messages: []
            ).get()
            
            // Check if task was cancelled after API call
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Store users and members
                for user in result.users {
                    self.users[user.id] = user
                }
                
                if let members = result.members {
                    for member in members {
                        self.members[member.id.server, default: [:]][member.id.user] = member
                    }
                }
                
                // Store messages
                var messageIds: [String] = []
                for message in result.messages {
                    self.messages[message.id] = message
                    messageIds.append(message.id)
                }
                
                // Store message IDs in channel (sorted by creation time)
                let sortedIds = messageIds.sorted { id1, id2 in
                    let date1 = createdAt(id: id1)
                    let date2 = createdAt(id: id2)
                    return date1 < date2
                }
                
                self.channelMessages[channelId] = sortedIds
                
                // print("📥 PRELOAD: Cached \(result.messages.count) messages for channel \(channelId)")
            }
        } catch {
            // Silently handle errors - preloading is a performance optimization, not critical
            // print("⚠️ PRELOAD: Failed to preload messages for channel \(channelId): \(error)")
        }
    }
}
