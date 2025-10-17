//
//  MessageableChannelViewModel+DataLoading.swift
//  Revolt
//
//  Data loading logic for MessageableChannelViewModel
//  Reactive Architecture: Database-first approach
//

import Foundation
import Types
import OSLog

extension MessageableChannelViewModel {
    
    private var logger: Logger {
        Logger(subsystem: "chat.revolt.app", category: "MessageableChannelViewModel")
    }
    
    // MARK: - Reactive Data Loading
    
    /// Loads messages for the channel from Database (reactive)
    /// Network sync happens in background via NetworkSyncService
    @MainActor
    func loadChannelMessages() async {
        logger.info("💾 REACTIVE_VM: Loading messages from Database for channel \(self.channel.id)")
        
        // 1️⃣ Read from Database
        let dbMessages = await MessageRepository.shared.fetchMessages(forChannel: channel.id)
        
        if !dbMessages.isEmpty {
            logger.info("💾 REACTIVE_VM: Found \(dbMessages.count) messages in Database")
            
            // Update ViewState from Database
            for message in dbMessages {
                viewState.messages[message.id] = message
            }
            
            // Sort and update channel messages (newest first)
            let sortedIds = dbMessages.map { $0.id }.sorted { id1, id2 in
                let date1 = createdAt(id: id1)
                let date2 = createdAt(id: id2)
                return date1 > date2
            }
            
            viewState.channelMessages[channel.id] = sortedIds
            self.messages = sortedIds
            logger.info("💾 REACTIVE_VM: ViewState updated with \(sortedIds.count) messages")
            
            // Notify observers
            notifyMessagesDidChange()
        } else {
            logger.info("💾 REACTIVE_VM: No messages in Database (first time load)")
            
            // Initialize empty state and notify so view knows we checked
            viewState.channelMessages[channel.id] = []
            self.messages = []
            notifyMessagesDidChange()
        }
        
        // 2️⃣ Trigger background network sync
        await NetworkSyncService.shared.syncChannelMessages(
            channelId: channel.id,
            viewState: viewState
        )
        logger.info("🔄 REACTIVE_VM: Background sync triggered")
    }
    
    /// Loads a target message and nearby messages from Database
    @MainActor
    func loadTargetMessage(_ messageId: String) async -> Bool {
        logger.info("🎯 REACTIVE_VM: Loading target message \(messageId) from Database")
        
        // 1️⃣ Check if target message exists in Database
        if let targetMessage = await MessageRepository.shared.fetchMessage(id: messageId) {
            logger.info("💾 REACTIVE_VM: Target message found in Database!")
            
            // Load all channel messages
            let dbMessages = await MessageRepository.shared.fetchMessages(forChannel: channel.id)
            
            if !dbMessages.isEmpty {
                // Update ViewState
                for message in dbMessages {
                    viewState.messages[message.id] = message
                }
                
                let sortedIds = dbMessages.map { $0.id }.sorted { id1, id2 in
                    createdAt(id: id1) > createdAt(id: id2)
                }
                
                viewState.channelMessages[channel.id] = sortedIds
                self.messages = sortedIds
                notifyMessagesDidChange()
                
                logger.info("💾 REACTIVE_VM: Target message and context loaded from Database")
                return true
            }
        }
        
        // 2️⃣ Not in Database - trigger network sync
        logger.info("🔄 REACTIVE_VM: Target message not in Database, triggering network sync")
        await NetworkSyncService.shared.syncTargetMessage(
            messageId: messageId,
            channelId: channel.id,
            viewState: viewState
        )
        
        return false
    }
    
    /// Loads a single message (for replies, etc)
    @MainActor
    func loadSingleMessage(_ messageId: String) async -> Types.Message? {
        logger.info("📨 REACTIVE_VM: Loading single message \(messageId)")
        
        // 1️⃣ Check ViewState cache
        if let cachedMessage = viewState.messages[messageId] {
            logger.info("✅ REACTIVE_VM: Message found in ViewState cache")
            return cachedMessage
        }
        
        // 2️⃣ Check Database
        if let dbMessage = await MessageRepository.shared.fetchMessage(id: messageId) {
            logger.info("💾 REACTIVE_VM: Message found in Database")
            viewState.messages[messageId] = dbMessage
            return dbMessage
        }
        
        // 3️⃣ Trigger network sync (background)
        logger.info("🔄 REACTIVE_VM: Message not found, triggering network sync")
        await NetworkSyncService.shared.syncSingleMessage(
            messageId: messageId,
            channelId: channel.id,
            viewState: viewState
        )
        
        // Return nil - DatabaseObserver will update ViewState when sync completes
        return nil
    }
    
    /// Loads user information
    @MainActor
    func loadUser(_ userId: String) async -> Types.User? {
        logger.info("👤 REACTIVE_VM: Loading user \(userId)")
        
        // 1️⃣ Check ViewState cache
        if let cachedUser = viewState.users[userId] {
            logger.info("✅ REACTIVE_VM: User found in ViewState cache")
            return cachedUser
        }
        
        // 2️⃣ Check Database
        if let dbUser = await UserRepository.shared.fetchUser(id: userId) {
            logger.info("💾 REACTIVE_VM: User found in Database")
            viewState.users[userId] = dbUser
            return dbUser
        }
        
        // 3️⃣ Trigger network sync (background)
        logger.info("🔄 REACTIVE_VM: User not found, triggering network sync")
        await NetworkSyncService.shared.syncUser(
            userId: userId,
            viewState: viewState
        )
        
        // Return nil - DatabaseObserver will update ViewState when sync completes
        return nil
    }
    
    /// Loads more older messages (for infinite scroll)
    @MainActor
    func loadMoreOlderMessages(before messageId: String) async {
        logger.info("📜 REACTIVE_VM: Loading older messages before \(messageId)")
        
        // Trigger network sync for older messages
        await NetworkSyncService.shared.syncMoreMessages(
            channelId: channel.id,
            before: messageId,
            viewState: viewState
        )
        
        logger.info("🔄 REACTIVE_VM: Older messages sync triggered")
    }
    
    // MARK: - Helper Methods
    
    /// Gets created timestamp from message ID
    func createdAt(id: String) -> Date {
        // Try ULID first (what Revolt uses)
        if let ulid = ULID(ulidString: id) {
            return ulid.timestamp
        }
        
        // Fallback to current date
        return Date()
    }
    
    // MARK: - Message Processing
    
    /// Processes reply messages and ensures they're loaded
    @MainActor
    func processReplyMessages(for messages: [Types.Message]) async {
        logger.info("🔗 REACTIVE_VM: Processing reply messages for \(messages.count) messages")
        
        var missingReplyIds: Set<String> = []
        
        // Find all reply IDs that aren't loaded
        for message in messages {
            if let replies = message.replies, !replies.isEmpty {
                for replyId in replies {
                    if viewState.messages[replyId] == nil {
                        missingReplyIds.insert(replyId)
                    }
                }
            }
        }
        
        if !missingReplyIds.isEmpty {
            logger.info("🔗 REACTIVE_VM: Found \(missingReplyIds.count) missing reply messages, triggering sync")
            
            // Trigger sync for each missing reply
            for replyId in missingReplyIds {
                await NetworkSyncService.shared.syncSingleMessage(
                    messageId: replyId,
                    channelId: channel.id,
                    viewState: viewState
                )
            }
        } else {
            logger.info("✅ REACTIVE_VM: All reply messages already loaded")
        }
    }
    
    /// Ensures all message authors are loaded
    @MainActor
    func ensureMessageAuthorsLoaded(for messages: [Types.Message]) async {
        logger.info("👥 REACTIVE_VM: Ensuring authors are loaded for \(messages.count) messages")
        
        var missingUserIds: Set<String> = []
        
        // Find all user IDs that aren't loaded
        for message in messages {
            if viewState.users[message.author] == nil {
                missingUserIds.insert(message.author)
            }
        }
        
        if !missingUserIds.isEmpty {
            logger.info("👥 REACTIVE_VM: Found \(missingUserIds.count) missing users, triggering sync")
            
            // Trigger sync for each missing user
            for userId in missingUserIds {
                await NetworkSyncService.shared.syncUser(
                    userId: userId,
                    viewState: viewState
                )
            }
        } else {
            logger.info("✅ REACTIVE_VM: All message authors already loaded")
        }
    }
}

