//
//  ViewState+UsersAndDms.swift
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
    
    internal func processUsers(_ eventUsers: [Types.User]) {
        // print("🚀 VIEWSTATE: Processing \(eventUsers.count) users from WebSocket")
        // print("🚀 VIEWSTATE: Existing users count: \(users.count)")
        
        // Store ALL users for lazy loading (this is our data source)
        allEventUsers = Dictionary(uniqueKeysWithValues: eventUsers.map { ($0.id, $0) })
        // print("🔄 LAZY_USER: Stored \(allEventUsers.count) users for lazy loading")
        
        // CRITICAL FIX: Don't clear existing users - merge instead
        // Keep existing users and add/update new ones from WebSocket
        
        var addedCount = 0
        var updatedCount = 0
        var currentUserFound = false
        
        // 1. Update/Add current user
        for user in eventUsers {
            if user.relationship == .User {
                currentUser = user
                if users[user.id] == nil {
                    users[user.id] = user
                    addedCount += 1
                    // print("🚀 VIEWSTATE: Added current user: \(user.id)")
                } else {
                    users[user.id] = user
                    updatedCount += 1
                    // print("🚀 VIEWSTATE: Updated current user: \(user.id)")
                }
                currentUserFound = true
                break
            }
        }
        
        // 2. Update/Add friends (always important)
        for user in eventUsers {
            if addedCount >= 50 {
                break
            }
            
            if user.relationship == .Friend {
                if users[user.id] == nil {
                    users[user.id] = user
                    addedCount += 1
                    // print("🚀 VIEWSTATE: Added friend: \(user.id)")
                } else {
                    users[user.id] = user
                    updatedCount += 1
                    // print("🚀 VIEWSTATE: Updated friend: \(user.id)")
                }
            }
        }
        
        // 3. Add users needed for visible DMs only (lazy approach)
        // Note: This will be called later in processDMs after allDmChannelIds is set
        
        // print("🚀 VIEWSTATE: FINAL USER COUNT: \(users.count) (added: \(addedCount), updated: \(updatedCount)) out of \(eventUsers.count) total")
        // print("🔄 LAZY_USER: Remaining users will be loaded on-demand")
        
        if !currentUserFound {
            // print("⚠️ VIEWSTATE: Current user not found in event users!")
        }
    }
    
    // Load users needed for currently visible DMs
    private func loadUsersForVisibleDms(from userDict: [String: Types.User], maxCount: Int) {
        var loadedCount = 0
        
        // Get IDs for first batch of DMs that will be visible
        let visibleDmIds = Array(allDmChannelIds.prefix(dmBatchSize))
        
        for dmId in visibleDmIds {
            if loadedCount >= maxCount {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load users for this DM
                for userId in recipientIds {
                    if loadedCount >= maxCount {
                        break
                    }
                    
                    if users[userId] == nil, let user = userDict[userId] {
                        users[userId] = user
                        loadedCount += 1
                        // print("🔄 LAZY_USER: Loaded DM participant: \(userId)")
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Loaded \(loadedCount) users for visible DMs")
    }
    
    // Load users for the first batch of DMs (called during processDMs)
    private func loadUsersForFirstDmBatch() {
        var loadedCount = 0
        let maxUsersToLoad = 50 // Limit to prevent memory issues
        
        // Get IDs for first batch of DMs that will be visible
        let visibleDmIds = Array(allDmChannelIds.prefix(dmBatchSize))
        
        for dmId in visibleDmIds {
            if loadedCount >= maxUsersToLoad {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load actual users from stored event data
                for userId in recipientIds {
                    if loadedCount >= maxUsersToLoad {
                        break
                    }
                    
                    if users[userId] == nil {
                        if let actualUser = allEventUsers[userId] {
                            // Load the real user data
                            users[userId] = actualUser
                            loadedCount += 1
                            // print("🔄 LAZY_USER: Loaded actual user \(actualUser.username) for DM participant: \(userId)")
                        } else {
                            // Create placeholder only if we can't find the real user
                            let placeholderUser = Types.User(
                                id: userId,
                                username: "Unknown User",
                                discriminator: "0000",
                                relationship: .None
                            )
                            users[userId] = placeholderUser
                            loadedCount += 1
                            // print("⚠️ LAZY_USER: Created placeholder for missing user: \(userId)")
                        }
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Loaded \(loadedCount) users for first DM batch")
    }
    
    // Load users on-demand when a new DM batch is loaded
    @MainActor
    func loadUsersForDmBatch(_ batchIndex: Int) {
        let startIndex = batchIndex * dmBatchSize
        let endIndex = min(startIndex + dmBatchSize, allDmChannelIds.count)
        
        guard startIndex < allDmChannelIds.count else {
            return
        }
        
        let batchIds = Array(allDmChannelIds[startIndex..<endIndex])
        var loadedCount = 0
        var skippedCount = 0
        let maxUsersToLoad = 10 // REDUCED to 10 users per batch for debugging
        
        for dmId in batchIds {
            if loadedCount >= maxUsersToLoad {
                break
            }
            
            if let channel = channels[dmId] {
                var recipientIds: [String] = []
                
                switch channel {
                case .dm_channel(let dm):
                    recipientIds = dm.recipients
                case .group_dm_channel(let group):
                    recipientIds = group.recipients
                default:
                    continue
                }
                
                // Load actual users from stored event data
                for userId in recipientIds {
                    if loadedCount >= maxUsersToLoad {
                        break
                    }
                    
                    // DUPLICATE PREVENTION: Skip if user already exists
                    if users[userId] != nil {
                        skippedCount += 1
                        continue
                    }
                    
                    if let actualUser = allEventUsers[userId] {
                        // Load the real user data
                        users[userId] = actualUser
                        loadedCount += 1
                        // print("🔄 LAZY_USER: Loaded NEW user \(actualUser.username) for DM batch \(batchIndex)")
                    } else {
                        // print("⚠️ LAZY_USER: User \(userId) not found in event data for batch \(batchIndex)")
                    }
                }
            }
        }
        
        // print("🔄 LAZY_USER: Batch \(batchIndex) - Loaded \(loadedCount) NEW users, skipped \(skippedCount) existing users. Total users now: \(users.count)")
    }
    
    // Load users for visible messages to prevent black messages
    @MainActor
    func loadUsersForVisibleMessages(channelId: String) {
        guard let messageIds = channelMessages[channelId] else {
            return
        }
        
        var loadedUsers = 0
        var missingUsers: [String] = []
        
        for messageId in messageIds {
            if let message = messages[messageId] {
                if users[message.author] == nil {
                    missingUsers.append(message.author)
                    
                    // Try to load from event data first
                    if let user = allEventUsers[message.author] {
                        users[message.author] = user
                        loadedUsers += 1
                        // print("🔄 LAZY_USER: Loaded message author \(user.username) from event data")
                    } else {
                        // Create placeholder user to prevent black messages
                        let placeholderUser = Types.User(
                            id: message.author,
                            username: "Unknown User",
                            discriminator: "0000",
                            relationship: .None
                        )
                        users[message.author] = placeholderUser
                        loadedUsers += 1
                        // print("⚠️ LAZY_USER: Created placeholder for missing user: \(message.author)")
                    }
                }
            }
        }
        
        if loadedUsers > 0 {
            // print("🔄 LAZY_USER: Loaded \(loadedUsers) users for channel \(channelId), missing: \(missingUsers.count)")
        }
    }
    
    // CRITICAL FIX: Restore missing users from allEventUsers to prevent black messages
    @MainActor
    func restoreMissingUsersForMessages() {
        var restoredCount = 0
        var placeholderCount = 0
        
        // print("🔄 RESTORE_USERS: Starting restoration of missing users")
        
        // Check all messages in memory
        for (messageId, message) in messages {
            if users[message.author] == nil {
                // Try to restore from allEventUsers
                if let storedUser = allEventUsers[message.author] {
                    users[message.author] = storedUser
                    restoredCount += 1
                    // print("🔄 RESTORE_USERS: Restored \(storedUser.username) for message \(messageId)")
                } else {
                    // Create placeholder as last resort
                    let placeholderUser = Types.User(
                        id: message.author,
                        username: "Unknown User",
                        discriminator: "0000",
                        relationship: .None
                    )
                    users[message.author] = placeholderUser
                    allEventUsers[message.author] = placeholderUser // Store for future use
                    placeholderCount += 1
                    // print("⚠️ RESTORE_USERS: Created placeholder for \(message.author) in message \(messageId)")
                }
            }
        }
        
        if restoredCount > 0 || placeholderCount > 0 {
            // print("🔄 RESTORE_USERS: Restoration complete - restored: \(restoredCount), placeholders: \(placeholderCount)")
        }
    }
    
    internal func processMembers(_ eventMembers: [Member]) {
        for member in eventMembers {
            members[member.id.server]?[member.id.user] = member
        }
    }
    
    internal func processDMs(channels: [Channel]) {
        // LAZY LOADING: Store all DM IDs but only load the first batch
        let dmChannels: [Channel] = channels.filter {
            switch $0 {
            case .dm_channel:
                return true // Include both active and inactive DMs
            case .group_dm_channel:
                return true
            default:
                return false
            }
        }
        
        // print("🚀 VIEWSTATE: Processing \(dmChannels.count) DM channels with lazy loading")
        
        // Sort all DM channels
        let sortedDmChannels = dmChannels.sorted { first, second in
            let firstLast = first.last_message_id
            let secondLast = second.last_message_id
            
            let firstUnreadLast = unreads[first.id]?.last_id
            let secondUnreadLast = unreads[second.id]?.last_id
            
            let firstIsUnread = firstLast != nil && firstLast != firstUnreadLast
            let secondIsUnread = secondLast != nil && secondLast != secondUnreadLast
            
            // Show unread DMs first
            if firstIsUnread && !secondIsUnread {
                return true
            } else if !firstIsUnread && secondIsUnread {
                return false
            } else {
                return (firstLast ?? "") > (secondLast ?? "")
            }
        }
        
        // Store all DM IDs in order
        allDmChannelIds = sortedDmChannels.map { $0.id }
        
        // Load users for visible DMs after we have the sorted list
        loadUsersForFirstDmBatch()
        
        // Simple lazy loading: start fresh
        loadedDmBatches.removeAll()
        dms.removeAll() // Clear existing DMs
        loadDmBatch(0) // Load first batch
        
        isDmListInitialized = true
        // print("🚀 VIEWSTATE: Stored \(allDmChannelIds.count) DM IDs, loaded first batch")
    }
    
    // Load a specific batch of DMs
    @MainActor
    func loadDmBatch(_ batchIndex: Int) {
        guard !isLoadingDmBatch else {
            // print("🔄 LAZY_DM: Already loading, skipping batch \(batchIndex)")
            return
        }
        
        // DUPLICATE PREVENTION: Check if this batch is already loaded
        if loadedDmBatches.contains(batchIndex) {
            // print("🔄 LAZY_DM: Batch \(batchIndex) already loaded, skipping")
            return
        }
        
        let startIndex = batchIndex * dmBatchSize
        let endIndex = min(startIndex + dmBatchSize, allDmChannelIds.count)
        
        guard startIndex < allDmChannelIds.count else {
            return
        }
        
        isLoadingDmBatch = true
        
        let memoryBefore = getCurrentMemoryUsage()
        // print("🔄 LAZY_DM: Loading batch \(batchIndex) (DMs \(startIndex) to \(endIndex-1)) - Memory: \(memoryBefore)MB")
        
        // Get batch IDs to load
        let batchIds = Array(allDmChannelIds[startIndex..<endIndex])
        var newDms: [Channel] = []
        
        for dmId in batchIds {
            if let channel = channels[dmId] {
                newDms.append(channel)
            }
        }
        
        // FIXED: Rebuild the entire DMs list from allDmChannelIds to maintain correct order
        // Mark this batch as loaded first
        loadedDmBatches.insert(batchIndex)
        
        // Now rebuild the DMs list from all loaded batches in correct order
        var rebuiltDms: [Channel] = []
        var addedChannelIds = Set<String>() // Prevent duplicates
        
        for loadedBatch in loadedDmBatches.sorted() {
            let batchStart = loadedBatch * dmBatchSize
            let batchEnd = min(batchStart + dmBatchSize, allDmChannelIds.count)
            
            for i in batchStart..<batchEnd {
                let channelId = allDmChannelIds[i]
                if !addedChannelIds.contains(channelId), let channel = channels[channelId] {
                    rebuiltDms.append(channel)
                    addedChannelIds.insert(channelId)
                }
            }
        }
        
        // Replace the entire DMs list with the rebuilt one
        dms = rebuiltDms
        
        // Load users for this batch
        loadUsersForDmBatch(batchIndex)
        
        // Simple memory protection: if too many batches, stop loading
        if loadedDmBatches.count >= maxLoadedBatches {
            // print("⚠️ LAZY_DM: Reached max batches limit (\(maxLoadedBatches)). No more loading.")
        }
        
        let memoryAfter = getCurrentMemoryUsage()
        let memoryDiff = memoryAfter - memoryBefore
        
        isLoadingDmBatch = false
        // print("🔄 LAZY_DM: Loaded batch \(batchIndex), total DMs: \(dms.count), Memory: \(memoryBefore)MB → \(memoryAfter)MB (\(memoryDiff > 0 ? "+" : "")\(memoryDiff)MB)")
    }
    
    // Load next batch when user scrolls to bottom
    @MainActor
    func loadMoreDmsIfNeeded() {
        // Find the highest loaded batch and load the next one
        let maxLoadedBatch = loadedDmBatches.max() ?? -1
        let nextBatchIndex = maxLoadedBatch + 1
        let totalBatches = (allDmChannelIds.count + dmBatchSize - 1) / dmBatchSize
        
        // Check if we haven't reached the limit and there are more batches
        if nextBatchIndex < totalBatches && loadedDmBatches.count < maxLoadedBatches {
            loadDmBatch(nextBatchIndex)
        }
    }
    
    // Ensure there are no gaps in loaded batches that could cause missing DMs
    @MainActor
    func ensureNoBatchGaps() {
        guard !loadedDmBatches.isEmpty else { return }
        
        let sortedBatches = loadedDmBatches.sorted()
        let minBatch = sortedBatches.first!
        let maxBatch = sortedBatches.last!
        
        // Fill any gaps between min and max loaded batches
        for batchIndex in minBatch...maxBatch {
            if !loadedDmBatches.contains(batchIndex) {
                // print("🔄 LAZY_DM: Found gap at batch \(batchIndex), loading to fill gap")
                loadDmBatch(batchIndex)
            }
        }
    }
    
    // Reset and reload DMs list (useful for fixing display issues)
    @MainActor
    func resetAndReloadDms() {
        // print("🔄 DM_RESET: Resetting and reloading DMs list")
        
        // Clear current state
        dms.removeAll()
        loadedDmBatches.removeAll()
        isLoadingDmBatch = false
        
        // Reload first batch
        if !allDmChannelIds.isEmpty {
            loadDmBatch(0)
        }
    }
    
}
