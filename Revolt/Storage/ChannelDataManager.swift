//
//  ChannelDataManager.swift
//  Revolt
//
//  Per-channel data manager for database-first architecture
//  Replaces ViewState singleton for channel-specific data
//

import Foundation
import SwiftUI
import Types
import OSLog

/// Manages data for a single channel view
/// Deallocates when view is dismissed, preventing memory accumulation
@MainActor
class ChannelDataManager: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "ChannelDataManager")
    
    /// Channel ID this manager is responsible for
    let channelId: String
    
    /// Messages loaded for this channel (paginated, max 100 in memory)
    @Published var messages: [Types.Message] = []
    
    /// Users dictionary for quick lookup (only users in loaded messages)
    @Published var users: [String: Types.User] = [:]
    
    /// Message IDs in display order (newest at bottom)
    @Published var messageIds: [String] = []
    
    /// Loading state
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    
    /// Pagination tracking
    private var oldestLoadedMessageId: String?
    private var hasMoreMessages: Bool = true
    
    /// Maximum messages to keep in memory
    private let maxMessagesInMemory = 100
    
    // MARK: - Initialization
    
    init(channelId: String) {
        self.channelId = channelId
        logger.debug("🆕 ChannelDataManager created for channel: \(channelId)")
    }
    
    deinit {
        //logger.debug("♻️ ChannelDataManager deallocated for channel: \(channelId) - freed \(messages.count) messages, \(users.count) users")
    }
    
    // MARK: - Data Loading
    
    /// Load initial messages for the channel (last 50)
    func loadInitialMessages() async {
        //logger.debug("📥 Loading initial messages for channel: \(channelId)")
        isLoading = true
        
        do {
            // Fetch last 50 messages from database
            let fetchedMessages = await MessageRepository.shared.fetchLatestMessages(
                forChannel: channelId,
                limit: 50
            )
            
            // Update messages
            messages = fetchedMessages.reversed() // Reverse to get oldest first
            messageIds = messages.map { $0.id }
            oldestLoadedMessageId = messages.first?.id
            hasMoreMessages = fetchedMessages.count == 50
            
            // Load users for these messages
            await loadUsersForMessages(fetchedMessages)
            
            //logger.debug("✅ Loaded \(messages.count) initial messages")
        }
        
        isLoading = false
    }
    
    /// Load more older messages (pagination)
    func loadMoreMessages() async -> Bool {
        guard !isLoadingMore, hasMoreMessages, let beforeId = oldestLoadedMessageId else {
            //logger.debug("⏭️ Skipping load more: isLoadingMore=\(isLoadingMore), hasMore=\(hasMoreMessages)")
            return false
        }
        
        logger.debug("📥 Loading more messages before: \(beforeId)")
        isLoadingMore = true
        
        do {
            // Fetch next batch of messages
            let fetchedMessages = await MessageRepository.shared.fetchMessagesBeforeId(
                channelId: channelId,
                beforeId: beforeId,
                limit: 50
            )
            
            if fetchedMessages.isEmpty {
                hasMoreMessages = false
                logger.debug("🏁 No more messages to load")
                isLoadingMore = false
                return false
            }
            
            // Prepend to existing messages (they're newer, so they go at the beginning)
            let reversedMessages = fetchedMessages.reversed()
            messages.insert(contentsOf: Array(reversedMessages), at: 0)
            messageIds.insert(contentsOf: reversedMessages.map { $0.id }, at: 0)
            oldestLoadedMessageId = messages.first?.id
            hasMoreMessages = fetchedMessages.count == 50
            
            // Load users for new messages
            await loadUsersForMessages(fetchedMessages)
            
            // Trim if we have too many messages in memory
            trimMessagesIfNeeded()
            
            //logger.debug("✅ Loaded \(fetchedMessages.count) more messages, total: \(messages.count)")
            isLoadingMore = false
            return true
        }
        
        isLoadingMore = false
        return false
    }
    
    /// Load users for a batch of messages
    func loadUsersForMessages(_ messages: [Types.Message]) async {
        // Collect unique user IDs from messages
        var userIds = Set<String>()
        for message in messages {
            userIds.insert(message.author)
            if let mentions = message.mentions {
                userIds.formUnion(mentions)
            }
        }
        
        // Filter out users we already have
        let missingUserIds = userIds.filter { users[$0] == nil }
        
        guard !missingUserIds.isEmpty else { return }
        
        logger.debug("👥 Loading \(missingUserIds.count) missing users")
        
        // Batch fetch users from database
        let fetchedUsers = await UserRepository.shared.fetchUsers(ids: Array(missingUserIds))
        
        // Merge into our users dictionary
        for (userId, user) in fetchedUsers {
            users[userId] = user
        }
        
        //logger.debug("✅ Loaded \(fetchedUsers.count) users, total: \(users.count)")
    }
    
    /// Add a new message (from WebSocket or send)
    func addMessage(_ message: Types.Message) async {
        guard message.channel == channelId else { return }
        
        // Check if message already exists
        if messages.contains(where: { $0.id == message.id }) {
            // Update existing message
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            }
        } else {
            // Add new message at the end
            messages.append(message)
            messageIds.append(message.id)
        }
        
        // Load user if needed
        if users[message.author] == nil {
            await loadUsersForMessages([message])
        }
        
        // Trim if needed
        trimMessagesIfNeeded()
    }
    
    /// Update an existing message
    func updateMessage(_ message: Types.Message) {
        guard message.channel == channelId else { return }
        
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        }
    }
    
    /// Delete a message
    func deleteMessage(id: String) {
        messages.removeAll { $0.id == id }
        messageIds.removeAll { $0 == id }
    }
    
    // MARK: - Memory Management
    
    /// Trim messages if we have too many in memory
    private func trimMessagesIfNeeded() {
        if messages.count > maxMessagesInMemory {
            let excessCount = messages.count - maxMessagesInMemory
            // Remove oldest messages
            messages.removeFirst(excessCount)
            messageIds.removeFirst(excessCount)
            oldestLoadedMessageId = messages.first?.id
            
            //logger.debug("✂️ Trimmed \(excessCount) old messages, keeping \(messages.count)")
            
            // Clean up users that are no longer referenced
            cleanupUnusedUsers()
        }
    }
    
    /// Remove users that aren't referenced by any loaded message
    private func cleanupUnusedUsers() {
        var referencedUserIds = Set<String>()
        for message in messages {
            referencedUserIds.insert(message.author)
            if let mentions = message.mentions {
                referencedUserIds.formUnion(mentions)
            }
        }
        
        let userIdsToRemove = users.keys.filter { !referencedUserIds.contains($0) }
        for userId in userIdsToRemove {
            users.removeValue(forKey: userId)
        }
        
        if !userIdsToRemove.isEmpty {
            logger.debug("🧹 Cleaned up \(userIdsToRemove.count) unused users")
        }
    }
    
    /// Clear all data (called when view is dismissed)
    func clearData() {
        //logger.debug("🗑️ Clearing all data for channel: \(channelId)")
        messages.removeAll()
        users.removeAll()
        messageIds.removeAll()
        oldestLoadedMessageId = nil
        hasMoreMessages = true
    }
    
    // MARK: - Accessors
    
    /// Get a message by ID
    func getMessage(id: String) -> Types.Message? {
        return messages.first { $0.id == id }
    }
    
    /// Get a user by ID
    func getUser(id: String) -> Types.User? {
        return users[id]
    }
    
    /// Get memory usage statistics
    func getMemoryStats() -> (messages: Int, users: Int, hasMore: Bool) {
        return (messages: messages.count, users: users.count, hasMore: hasMoreMessages)
    }
}

