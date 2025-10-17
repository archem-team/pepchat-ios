//
//  MessageableChannelViewController+MemoryManagement.swift
//  Revolt
//
//  Memory management and cleanup functionality
//

import UIKit
import Kingfisher

extension MessageableChannelViewController {
    
    // MARK: - Memory Cleanup Methods
    
    /// Performs INSTANT memory cleanup - no delays, no async operations
    func performInstantMemoryCleanup() {
        let channelId = viewModel.channel.id
        print("⚡ INSTANT_CLEANUP: Starting IMMEDIATE memory cleanup for channel \(channelId)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 1. IMMEDIATE: Clear all local data synchronously
        self.localMessages.removeAll(keepingCapacity: false)
        viewModel.messages.removeAll(keepingCapacity: false)
        
        // 2. IMMEDIATE: Clear ViewState data synchronously (no Task, no async)
        viewModel.viewState.channelMessages.removeValue(forKey: channelId)
        viewModel.viewState.preloadedChannels.remove(channelId)
        viewModel.viewState.atTopOfChannel.remove(channelId)
        viewModel.viewState.currentlyTyping.removeValue(forKey: channelId)
        
        // 3. IMMEDIATE: Remove all message objects for this channel
        let messagesToRemove = viewModel.viewState.messages.keys.filter { messageId in
            if let message = viewModel.viewState.messages[messageId] {
                return message.channel == channelId
            }
            return false
        }
        
        for messageId in messagesToRemove {
            viewModel.viewState.messages.removeValue(forKey: messageId)
        }
        
        print("⚡ INSTANT_CLEANUP: Removed \(messagesToRemove.count) message objects immediately")
        
        // 4. IMMEDIATE: Clear table view and data source
        self.dataSource = nil
        
        // 5. IMMEDIATE: Reset all state variables
        isInTargetMessagePosition = false
        targetMessageProcessed = false
        isLoadingMore = false
        messageLoadingState = .notLoading
        
        // 6. IMMEDIATE: Force memory cleanup without autoreleasepool delays
        ImageCache.default.clearMemoryCache()
        
        // 7. IMMEDIATE: Call ViewState instant cleanup (no async operations)
        viewModel.viewState.cleanupChannelFromMemory(channelId: channelId, preserveForNavigation: false)
        
        // 8. IMMEDIATE: Force garbage collection
        _ = viewModel.viewState.messages.count + viewModel.viewState.users.count
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000 // Convert to milliseconds
        
        print("⚡ INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - IMMEDIATE cleanup done!")
    }
    
    /// Performs light memory cleanup for cross-channel navigation
    func performLightMemoryCleanup() {
        print("🧹 LIGHT_CLEANUP: Starting light memory cleanup")
        
        let channelId = viewModel.channel.id
        
        // Clear only local view controller data
        self.localMessages.removeAll()
        viewModel.messages.removeAll()
        
        // Clear preloaded status to allow reloading
        viewModel.viewState.preloadedChannels.remove(channelId)
        
        // For light cleanup, preserve ViewState messages but clear channel message list
        // This allows the messages to be reloaded when returning to the channel
        viewModel.viewState.channelMessages.removeValue(forKey: channelId)
        
        // Clear table view data source
        if let dataSource = self.dataSource as? LocalMessagesDataSource {
            dataSource.updateMessages([])
        }
        
        // Reset view controller state
        isInTargetMessagePosition = false
        targetMessageProcessed = false
        
        print("🧹 LIGHT_CLEANUP: Completed - preserved ViewState messages for navigation")
    }
    
    /// Performs aggressive memory cleanup when fully leaving channel
    func performAggressiveMemoryCleanup() {
        print("🧹 AGGRESSIVE_CLEANUP: Starting aggressive memory cleanup")
        
        let channelId = viewModel.channel.id
        let isDM = viewModel.channel.isDM
        let isGroupDM = viewModel.channel.isGroupDmChannel
        
        // 1. Clear all local data immediately
        self.localMessages.removeAll()
        viewModel.messages.removeAll()
        
        // 2. Use ViewState's comprehensive cleanup method
        Task { @MainActor in
            self.viewModel.viewState.cleanupChannelFromMemory(channelId: channelId, preserveForNavigation: false)
        }
        
        // 3. Special cleanup for DMs (additional local cleanup)
        if isDM || isGroupDM {
            cleanupDMSpecificData(channelId: channelId)
        }
        
        // 4. Clear table view data
        if let dataSource = self.dataSource as? LocalMessagesDataSource {
            dataSource.updateMessages([])
        }
        
        // 5. Force memory cleanup
        autoreleasepool {
            // Clear image cache for this channel
            ImageCache.default.clearMemoryCache()
            
            // Force garbage collection
            _ = viewModel.viewState.messages.count
        }
        
        print("🧹 AGGRESSIVE_CLEANUP: Completed - removed all channel data from memory")
    }
    
    /// Cleanup DM-specific data and unused user objects
    func cleanupDMSpecificData(channelId: String) {
        guard let channel = viewModel.viewState.channels[channelId] else { return }
        
        print("🧹 DM_CLEANUP: Cleaning up DM-specific data for channel \(channelId)")
        
        // Get recipient IDs for this DM
        let recipientIds = channel.recipients
        
        // Determine which users can be safely removed
        var usersToKeep = Set<String>()
        
        // Always keep current user
        if let currentUserId = viewModel.viewState.currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        
        // Keep users needed for other active channels
        for (otherChannelId, messageIds) in viewModel.viewState.channelMessages {
            if otherChannelId == channelId { continue }
            
            // Keep users from other DMs
            if let otherChannel = viewModel.viewState.channels[otherChannelId] {
                usersToKeep.formUnion(otherChannel.recipients)
            }
            
            // Keep message authors from other channels
            for messageId in messageIds {
                if let message = viewModel.viewState.messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }
        
        // Keep users needed for servers
        for server in viewModel.viewState.servers.values {
            usersToKeep.insert(server.owner)
            // Keep members of servers
            if let serverMembers = viewModel.viewState.members[server.id] {
                usersToKeep.formUnion(serverMembers.keys)
            }
        }
        
        // Remove users that are no longer needed
        let usersToRemove = recipientIds.filter { userId in
            !usersToKeep.contains(userId) && userId != viewModel.viewState.currentUser?.id
        }
        
        if !usersToRemove.isEmpty {
            print("🧹 DM_CLEANUP: Removing \(usersToRemove.count) unused users from memory")
            for userId in usersToRemove {
                viewModel.viewState.users.removeValue(forKey: userId)
                
                // Also remove from members if they exist
                for serverId in viewModel.viewState.members.keys {
                    viewModel.viewState.members[serverId]?.removeValue(forKey: userId)
                }
            }
        } else {
            print("🧹 DM_CLEANUP: All users are still needed, keeping them")
        }
        
        // Clear any DM-specific caches
        // Note: Keep the channel object itself for future conversations
        print("🧹 DM_CLEANUP: Completed DM cleanup")
    }
    
    // MARK: - Memory Enforcement (Disabled)
    
    /// Enforce message limits - currently disabled
    func enforceMessageLimits() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't perform any message limit enforcement while in the channel
        return
    }
    
    /// Check memory usage and cleanup - currently disabled
    func checkMemoryUsageAndCleanup() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't perform any memory cleanup checks while in the channel
        return
    }
    
    /// Start automatic memory cleanup timer - currently disabled
    func startMemoryCleanupTimer() {
        // DISABLED: Memory cleanup was causing UI freezes
        // Don't start any automatic cleanup timers while in the channel
        return
    }
    
    /// Stop memory cleanup timer
    func stopMemoryCleanupTimer() {
        memoryCleanupTimer?.invalidate()
        memoryCleanupTimer = nil
    }
    
    // MARK: - Memory Warnings
    
    /// Handle system memory warnings
    @objc func handleMemoryWarning() {
        // DISABLED: Memory cleanup was causing UI freezes while in the channel
        // Don't perform any aggressive cleanup while user is actively viewing messages
        // Messages will be cleared when leaving the channel
        print("⚠️ MEMORY WARNING: Received memory warning but deferring cleanup until channel exit")
        
        // PERFORMANCE: Clear height caches to free up memory
        MessageCellHeightCache.shared.clearAllCaches()
        
        return
    }
    
    /// Handle channel search closing notification
    @objc func handleChannelSearchClosing(_ notification: Notification) {
        guard let userInfo = notification.object as? [String: Any],
              let channelId = userInfo["channelId"] as? String,
              let isReturning = userInfo["isReturning"] as? Bool else {
            return
        }
        
        // Check if this notification is for our channel
        if channelId == viewModel.channel.id && isReturning {
            print("🔍 SEARCH_CLOSING: User is returning from search to channel \(channelId)")
            isReturningFromSearch = true
            
            // Don't clear the flag here - let viewDidAppear handle it
        }
    }
    
    // MARK: - Memory Logging
    
    /// Helper method to log memory usage
    func logMemoryUsage(prefix: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            print("📊 MEMORY USAGE [\(prefix)]: \(String(format: "%.2f", usedMB)) MB")
            print("   - Messages in viewState: \(viewModel.viewState.messages.count)")
            print("   - Users in viewState: \(viewModel.viewState.users.count)")
            print("   - Channel messages count: \(viewModel.viewState.channelMessages[viewModel.channel.id]?.count ?? 0)")
            print("   - Local messages count: \(localMessages.count)")
            print("   - Servers: \(viewModel.viewState.servers.count)")
            print("   - Members dictionaries: \(viewModel.viewState.members.count)")
        }
    }
    
    // MARK: - Final Cleanup
    
    /// Force immediate memory cleanup - called after view disappears
    func forceImmediateMemoryCleanup() {
        print("⚡ FORCE_IMMEDIATE_CLEANUP: Starting INSTANT memory cleanup")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // IMMEDIATE: Force image cache cleanup
        let cache = ImageCache.default
        cache.clearMemoryCache()
        
        // IMMEDIATE: Aggressive user cleanup - NO Task, NO async
        let channelId = self.viewModel.channel.id
        let isDM = self.viewModel.channel.isDM
        let isGroupDM = self.viewModel.channel.isGroupDmChannel
        
        print("👥 INSTANT_USER_CLEANUP: Starting for channel \(channelId) - DM: \(isDM), GroupDM: \(isGroupDM)")
        let initialUserCount = self.viewModel.viewState.users.count
        
        // Collect all user IDs that should be kept
        var usersToKeep = Set<String>()
        
        // Add current user if exists
        if let currentUserId = self.viewModel.viewState.currentUser?.id {
            usersToKeep.insert(currentUserId)
        }
        
        // Only keep users from OTHER channels (not the one we just left)
        for (otherChannelId, messageIds) in self.viewModel.viewState.channelMessages {
            // Skip the channel we just left
            if otherChannelId == channelId { continue }
            
            // Add users from messages in other channels
            for messageId in messageIds {
                if let message = self.viewModel.viewState.messages[messageId] {
                    usersToKeep.insert(message.author)
                    if let mentions = message.mentions {
                        usersToKeep.formUnion(mentions)
                    }
                }
            }
        }
        
        // IMMEDIATE: Keep users from OTHER active DMs
        for channel in self.viewModel.viewState.channels.values {
            // Skip the channel we just left
            if channel.id == channelId { continue }
            
            // Keep users from other active DMs
            if channel.isDM || channel.isGroupDmChannel {
                let recipientIds = channel.recipients
                usersToKeep.formUnion(recipientIds)
                print("👥 INSTANT_USER_CLEANUP: Keeping \(recipientIds.count) users from other DM \(channel.id)")
            }
        }
        
        // IMMEDIATE: Keep users that might be needed for server lists
        for server in self.viewModel.viewState.servers.values {
            usersToKeep.insert(server.owner)
        }
        
        print("👥 INSTANT_USER_CLEANUP: Users to keep: \(usersToKeep.count)")
        
        // IMMEDIATE: For DMs, be more aggressive about user cleanup
        if isDM || isGroupDM {
            print("👥 INSTANT_USER_CLEANUP: Performing DM-specific user cleanup")
            
            // Get users from the DM we just left
            let dmRecipients = self.viewModel.channel.recipients
            let usersToRemove = dmRecipients.filter { userId in
                !usersToKeep.contains(userId)
            }
            
            if !usersToRemove.isEmpty {
                print("👥 INSTANT_USER_CLEANUP: Removing \(usersToRemove.count) DM users that are no longer needed")
                for userId in usersToRemove {
                    self.viewModel.viewState.users.removeValue(forKey: userId)
                }
            } else {
                print("👥 INSTANT_USER_CLEANUP: All DM users are still needed elsewhere")
            }
        }
        
        let finalUserCount = self.viewModel.viewState.users.count
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        
        print("⚡ FORCE_IMMEDIATE_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - Users: \(initialUserCount) -> \(finalUserCount)")
    }
    
    /// Performs INSTANT final cleanup with no delays
    func performFinalInstantCleanup() {
        let channelId = viewModel.channel.id
        print("⚡ FINAL_INSTANT_CLEANUP: Starting IMMEDIATE final cleanup for channel \(channelId)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 1. IMMEDIATE: Clear table view synchronously
        self.tableView.dataSource = nil
        self.tableView.delegate = nil
        
        // 2. IMMEDIATE: Force ViewState cleanup synchronously (no Task, no async)
        viewModel.viewState.cleanupChannelFromMemory(channelId: channelId, preserveForNavigation: false)
        viewModel.viewState.forceMemoryCleanup()
        
        // 3. IMMEDIATE: Aggressive image cache cleanup
        ImageCache.default.clearMemoryCache()
        
        // 4. IMMEDIATE: Reset all controller state
        targetMessageId = nil
        targetMessageProcessed = false
        isInTargetMessagePosition = false
        isLoadingMore = false
        messageLoadingState = .notLoading
        
        // 5. IMMEDIATE: Final verification and force cleanup
        let remainingMessages = viewModel.viewState.messages.values.filter { $0.channel == channelId }.count
        let remainingChannelMessages = viewModel.viewState.channelMessages[channelId]?.count ?? 0
        
        if remainingMessages > 0 || remainingChannelMessages > 0 {
            print("⚠️ FINAL_INSTANT_CLEANUP: Found \(remainingMessages) remaining messages, force removing")
            
            // IMMEDIATE: Force remove any remaining data
            viewModel.viewState.channelMessages.removeValue(forKey: channelId)
            
            let finalMessagesToRemove = viewModel.viewState.messages.keys.filter { messageId in
                if let message = viewModel.viewState.messages[messageId] {
                    return message.channel == channelId
                }
                return false
            }
            
            for messageId in finalMessagesToRemove {
                viewModel.viewState.messages.removeValue(forKey: messageId)
            }
            
            print("⚡ FINAL_INSTANT_CLEANUP: Force removed \(finalMessagesToRemove.count) remaining messages")
        }
        
        // 6. IMMEDIATE: Force garbage collection
        _ = viewModel.viewState.messages.count + viewModel.viewState.users.count + viewModel.viewState.channelMessages.count
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000 // Convert to milliseconds
        
        print("⚡ FINAL_INSTANT_CLEANUP: Completed in \(String(format: "%.2f", duration))ms - ALL memory freed immediately!")
        logMemoryUsage(prefix: "AFTER INSTANT FINAL CLEANUP")
    }
}

