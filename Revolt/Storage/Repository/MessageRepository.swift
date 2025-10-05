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
    
    /// Fetch messages for a specific channel
    func fetchMessages(forChannel channelId: String) async -> [Types.Message] {
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        let filtered = realms.filter { $0.channel == channelId }
        return filtered.compactMap { $0.toOriginal() as? Types.Message }
    }
    
    /// Fetch all messages from Realm
    func fetchAllMessages() async -> [Types.Message] {
        let realms = await realmManager.getListOfObjects(type: MessageRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.Message }
    }
}
