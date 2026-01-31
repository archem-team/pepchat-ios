//
//  ViewState+Unreads.swift
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

enum UnreadCount : Equatable {
    case unread
    case mentions(String)
    case unreadWithMentions(mentionsCount: String)
}

extension ViewState {
    func getUnreadCountFor(server: Server) -> UnreadCount? {
        if let serverNotificationValue = userSettingsStore.cache.notificationSettings.server[server.id] {
            if serverNotificationValue == .muted && serverNotificationValue == .none {
                return nil
            }
        }
        
        // FIXED: Use allEventChannels to check unreads for all channels, not just loaded ones
        let serverChannelIds = server.channels
        let channelUnreads = serverChannelIds.compactMap { channelId -> (Channel, UnreadCount?)? in
            // First try from loaded channels, then from stored channels
            if let channel = channels[channelId] {
                return (channel, getUnreadCountFor(channel: channel))
            } else if let channel = allEventChannels[channelId] {
                // For unloaded channels, check unreads directly
                let unread = unreads[channelId]
                if let unread = unread {
                    let unreadCount = getUnreadCountFromUnread(unread: unread, channel: channel)
                    return (channel, unreadCount)
                }
                return (channel, nil)
            }
            return nil
        }
        
        var mentionCount = 0
        var hasUnread = false
        
        for (channel, unread) in channelUnreads {
            let channelNotificationValue = userSettingsStore.cache.notificationSettings.channel[channel.id]
            
            if let unread = unread {
                switch unread {
                case .unread:
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .muted {
                        hasUnread = true
                    }
                    
                case .mentions(let count):
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .mention {
                        mentionCount += (Int(count) ?? 0)
                    }
                case .unreadWithMentions(let count):
                    if channelNotificationValue != NotificationState.none && channelNotificationValue != .mention {
                        hasUnread = true
                        mentionCount += (Int(count) ?? 0)
                    }
                    
                }
                
            }
        }
        
        if mentionCount > 0 && hasUnread {
            return .unreadWithMentions(mentionsCount: formattedMentionCount(mentionCount))
        }else if mentionCount > 0 {
            return .mentions(formattedMentionCount(mentionCount))
        } else if hasUnread {
            return .unread
        }
        
        return nil
    }
    
    func getUnreadCountFor(channel: Channel) -> UnreadCount? {
        /*if let unread = unreads[channel.id] {
         if let mentions = unread.mentions {
         return .mentions(formattedMentionCount(mentions.count))
         }
         
         if let last_unread_id = unread.last_id, let last_message_id = channel.last_message_id {
         if last_unread_id < last_message_id {
         return .unread
         }
         }
         }
         
         return nil*/
        
        guard let unread = unreads[channel.id] else {
            return nil
        }
        
        let hasMentions = (unread.mentions != nil && unread.mentions?.count ?? 0 > 0)
        
        
        
        let hasUnread: Bool = {
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                return lastUnreadId < lastMessageId
            }
            return false
        }()
        
        if (hasMentions) && hasUnread {
            return .unreadWithMentions(
                mentionsCount: formattedMentionCount(unread.mentions!.count)
            )
        } else if hasMentions {
            return .mentions(formattedMentionCount(unread.mentions!.count))
        } else if hasUnread {
            return .unread
        }

        return nil
        
    }
    
    // Helper function to convert Unread object to UnreadCount for lazy loaded channels
    func getUnreadCountFromUnread(unread: Unread, channel: Channel) -> UnreadCount? {
        // Check channel notification settings
        let channelNotificationValue = userSettingsStore.cache.notificationSettings.channel[channel.id]
        
        if channelNotificationValue == NotificationState.none || channelNotificationValue == .muted {
            return nil
        }
        
        // Check if channel has last message
        guard let lastMessageId = channel.last_message_id else {
            return nil
        }
        
        // Check if there are unread messages
        let hasUnreadMessages = unread.last_id != lastMessageId
        
        // Check for mentions
        let mentionCount = unread.mentions?.count ?? 0
        let hasMentions = mentionCount > 0
        
        if hasUnreadMessages && hasMentions {
            return .unreadWithMentions(mentionsCount: formattedMentionCount(mentionCount))
        } else if hasMentions {
            return .mentions(formattedMentionCount(mentionCount))
        } else if hasUnreadMessages {
            return .unread
        }
        
        return nil
    }
    
    func formattedMentionCount(_ input: Int) -> String {
        if input > 10 {
            return "+9"
        } else {
            return "\(input)"
        }
    }
    
    /// Clean up stale unread entries for channels that no longer exist
    func cleanupStaleUnreads() {
        print("🧹 Cleaning up stale unreads...")
        var removedCount = 0
        var staleChannels: [String] = []
        
        for channelId in unreads.keys {
            // Check if channel exists in our channels dictionary or allEventChannels
            if channels[channelId] == nil && allEventChannels[channelId] == nil {
                staleChannels.append(channelId)
                removedCount += 1
            }
        }
        
        // Remove stale entries
        for channelId in staleChannels {
            unreads.removeValue(forKey: channelId)
            print("  ❌ Removed stale unread for channel: \(channelId)")
        }
        
        print("🧹 Cleanup complete. Removed \(removedCount) stale entries.")
        
        // Update badge count after cleanup
        updateAppBadgeCount()
    }
    
    /// Force mark all channels as read and clear the app badge
    func forceMarkAllAsRead() {
        print("📖 Force marking all channels as read...")
        let channelCount = unreads.count
        
        // Clear all unreads
        unreads.removeAll()
        
        // Clear the app badge
        clearAppBadge()
        
        print("📖 Marked \(channelCount) channels as read and cleared badge")
    }
    
    /// Show detailed unread message counts for each channel
    func showUnreadCounts() {
        print("\n📊 === UNREAD MESSAGE COUNTS ===")
        
        var totalUnreadMessages = 0
        var totalMentions = 0
        var channelsWithUnread: [(name: String, id: String, unreadCount: Int, mentionCount: Int)] = []
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId] ?? allEventChannels[channelId]
            let channelName = channel?.name ?? "Unknown Channel"
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                print("❌ Channel \(channelId) not found - skipping")
                continue
            }
            
            // Check notification settings
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted ||
                                userSettingsStore.cache.notificationSettings.channel[channelId] == .none
            let serverIdForChannel = channel.server
            let isServerMuted = serverIdForChannel != nil ?
                (userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted ||
                 userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .none) : false
            
            // Calculate unread count
            var unreadCount = 0
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    // We can't get exact count without fetching messages, but we know there are unread messages
                    unreadCount = -1 // -1 means "has unread but count unknown"
                }
            }
            
            let mentionCount = unread.mentions?.count ?? 0
            
            if unreadCount != 0 || mentionCount > 0 {
                let mutedIndicator = (isChannelMuted || isServerMuted) ? " 🔇" : ""
                channelsWithUnread.append((
                    name: channelName + mutedIndicator,
                    id: channelId,
                    unreadCount: unreadCount,
                    mentionCount: mentionCount
                ))
                
                if !(isChannelMuted || isServerMuted) {
                    if unreadCount == -1 {
                        totalUnreadMessages += 1 // Count as at least 1
                    } else if unreadCount > 0 {
                        totalUnreadMessages += unreadCount
                    }
                    totalMentions += mentionCount
                }
            }
        }
        
        // Sort by mention count first, then by name
        channelsWithUnread.sort {
            if $0.mentionCount != $1.mentionCount {
                return $0.mentionCount > $1.mentionCount
            }
            return $0.name < $1.name
        }
        
        // Print results
        if channelsWithUnread.isEmpty {
            print("✅ No channels with unread messages!")
        } else {
            print("\n📌 Channels with unread messages:")
            for channel in channelsWithUnread {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
                print("  • \(channel.name): \(unreadText)\(mentionText)")
            }
        }
        
        print("\n📊 Summary:")
        print("  - Total channels with unread: \(channelsWithUnread.count)")
        print("  - Total unread channels (unmuted): \(totalUnreadMessages)")
        print("  - Total mentions (unmuted): \(totalMentions)")
        print("  - Current badge count: \(ViewState.application?.applicationIconBadgeNumber ?? 0)")
        print("📊 === END UNREAD COUNTS ===\n")
    }
    
    /// Get unread counts as a formatted string for UI display
    func getUnreadCountsString() -> String {
        var result = "📊 UNREAD MESSAGE COUNTS\n\n"
        
        var channelsWithUnread: [(name: String, id: String, unreadCount: Int, mentionCount: Int, isMuted: Bool)] = []
        
        for (channelId, unread) in unreads {
            let channel = channels[channelId] ?? allEventChannels[channelId]
            let channelName = channel?.name ?? "Unknown Channel"
            
            // Skip if channel doesn't exist
            guard let channel = channel else {
                continue
            }
            
            // Check notification settings
            let isChannelMuted = userSettingsStore.cache.notificationSettings.channel[channelId] == .muted ||
                                userSettingsStore.cache.notificationSettings.channel[channelId] == .none
            let serverIdForChannel = channel.server
            let isServerMuted = serverIdForChannel != nil ?
                (userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .muted ||
                 userSettingsStore.cache.notificationSettings.server[serverIdForChannel!] == .none) : false
            
            let isMuted = isChannelMuted || isServerMuted
            
            // Calculate unread count
            var unreadCount = 0
            if let lastUnreadId = unread.last_id, let lastMessageId = channel.last_message_id {
                if lastUnreadId < lastMessageId {
                    unreadCount = -1 // -1 means "has unread but count unknown"
                }
            }
            
            let mentionCount = unread.mentions?.count ?? 0
            
            if unreadCount != 0 || mentionCount > 0 {
                channelsWithUnread.append((
                    name: channelName,
                    id: channelId,
                    unreadCount: unreadCount,
                    mentionCount: mentionCount,
                    isMuted: isMuted
                ))
            }
        }
        
        // Sort by muted status first, then mention count, then name
        channelsWithUnread.sort {
            if $0.isMuted != $1.isMuted {
                return !$0.isMuted // Unmuted first
            }
            if $0.mentionCount != $1.mentionCount {
                return $0.mentionCount > $1.mentionCount
            }
            return $0.name < $1.name
        }
        
        if channelsWithUnread.isEmpty {
            result += "✅ No channels with unread messages!"
        } else {
            var unmutedCount = 0
            var mutedCount = 0
            
            result += "📌 Unmuted channels:\n"
            for channel in channelsWithUnread where !channel.isMuted {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
                result += "• \(channel.name): \(unreadText)\(mentionText)\n"
                unmutedCount += 1
            }
            
            if unmutedCount == 0 {
                result += "None\n"
            }
            
            result += "\n🔇 Muted channels:\n"
            for channel in channelsWithUnread where channel.isMuted {
                let unreadText = channel.unreadCount == -1 ? "Has unread" : "\(channel.unreadCount) unread"
                let mentionText = channel.mentionCount > 0 ? ", \(channel.mentionCount) mention(s)" : ""
                result += "• \(channel.name): \(unreadText)\(mentionText)\n"
                mutedCount += 1
            }
            
            if mutedCount == 0 {
                result += "None\n"
            }
            
            result += "\n📊 Summary:\n"
            result += "• Total channels with unread: \(channelsWithUnread.count)\n"
            result += "• Unmuted channels: \(unmutedCount)\n"
            result += "• Muted channels: \(mutedCount)\n"
            result += "• Current badge: \(ViewState.application?.applicationIconBadgeNumber ?? 0)"
        }
        
        return result
    }
}
