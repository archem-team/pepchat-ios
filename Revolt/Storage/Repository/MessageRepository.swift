//
//  MessageRepository.swift
//  Revolt
//
//  Repository for Message data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing Message data between Network and Realm
class MessageRepository {
    
    // MARK: - Singleton
    
    static let shared = MessageRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "MessageRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save a single message to Realm (from API or WebSocket)
    func saveMessage(_ message: Types.Message) async {
        await realmManager.write(message.toRealm())
        logger.debug("✅ Message saved: \(message.id)")
    }
    
    /// Save multiple messages to Realm (from API or WebSocket)
    func saveMessages(_ messages: [Types.Message]) async {
        guard !messages.isEmpty else { return }
        await realmManager.writeBatch(messages.map { $0.toRealm() })
        logger.debug("✅ Saved \(messages.count) messages")
    }
    
    // MARK: - Delete Operations
    
    /// Delete a message by ID
    func deleteMessage(id: String) async {
        await realmManager.deleteByPrimaryKey(MessageRealm.self, key: id)
        logger.debug("✅ Message deleted: \(id)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a message from Realm by ID
    func fetchMessage(id: String) async -> Types.Message? {
        guard let messageRealm = await realmManager.fetchItemByPrimaryKey(MessageRealm.self, primaryKey: id) else {
            return nil
        }
        return messageRealm.toOriginal() as? Types.Message
    }
    
    /// Fetch messages for a specific channel (all messages - use with caution)
    func fetchMessages(forChannel channelId: String) async -> [Types.Message] {
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        let filtered = realms.filter { $0.channel == channelId }
        return filtered.compactMap { $0.toOriginal() as? Types.Message }
    }
    
    /// Fetch latest messages for a channel with limit (paginated)
    func fetchLatestMessages(forChannel channelId: String, limit: Int = 50) async -> [Types.Message] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        let filtered = realms.filter { $0.channel == channelId }
        
        // Sort by ID (ULID contains timestamp, so sorting by ID = sorting by time)
        let sorted = filtered.sorted { $0.id > $1.id }
        let limited = Array(sorted.prefix(limit))
        let messages = limited.compactMap { $0.toOriginal() as? Types.Message }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        logger.debug("📊 Fetched \(messages.count) latest messages for channel \(channelId) in \(String(format: "%.2f", duration))ms")
        
        return messages
    }
    
    /// Fetch messages before a specific message ID (for pagination/infinite scroll)
    func fetchMessagesBeforeId(channelId: String, beforeId: String, limit: Int = 50) async -> [Types.Message] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        
        // Filter by channel
        let channelMessages = realms.filter { $0.channel == channelId }
        
        // ULID is time-based, so comparing IDs is equivalent to comparing timestamps
        // We want messages older than beforeId (with smaller timestamp)
        let filtered = channelMessages.filter { $0.id < beforeId }
        
        // Log what we found
        logger.debug("🔍 Found \(filtered.count) messages before \(beforeId) in channel \(channelId)")
        
        // Sort by ID descending (newest first)
        let sorted = filtered.sorted { $0.id > $1.id }
        let limited = Array(sorted.prefix(limit))
        let messages = limited.compactMap { $0.toOriginal() as? Types.Message }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        logger.debug("📊 Fetched \(messages.count) messages before \(beforeId) in \(String(format: "%.2f", duration))ms")
        
        return messages
    }
    
    /// Fetch messages with pagination (offset-based)
    func fetchMessages(forChannel channelId: String, limit: Int, offset: Int) async -> [Types.Message] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        let filtered = realms.filter { $0.channel == channelId }
        
        // Sort by ID descending
        let sorted = filtered.sorted { $0.id > $1.id }
        
        // Apply offset and limit
        let offsetArray = Array(sorted.dropFirst(offset))
        let limited = Array(offsetArray.prefix(limit))
        let messages = limited.compactMap { $0.toOriginal() as? Types.Message }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000
        logger.debug("📊 Fetched \(messages.count) messages (offset: \(offset), limit: \(limit)) in \(String(format: "%.2f", duration))ms")
        
        return messages
    }
    
    /// Get total message count for a channel
    func getMessageCount(forChannel channelId: String) async -> Int {
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        return realms.filter { $0.channel == channelId }.count
    }
    
    /// Fetch all messages from Realm
    func fetchAllMessages() async -> [Types.Message] {
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.Message }
    }
}
