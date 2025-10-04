//
//  RealmManager+NetworkData.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//
//  Extension for saving network data (API/WebSocket) to Realm
//  Uses existing RealmManager instead of creating a new bridge

import Foundation
import RealmSwift
import Types
import OSLog

// MARK: - Network Data Saving Extension

extension RealmManager {
    
    // MARK: - Ready Event (WebSocket)
    
    /// Save all data from WebSocket ready event to Realm
    func saveReadyEvent(users: [Types.User], servers: [Types.Server], channels: [Types.Channel], members: [Types.Member], emojis: [Types.Emoji]) async {
        logger.info("🌐 Saving ready event: users=\(users.count), servers=\(servers.count), channels=\(channels.count), members=\(members.count), emojis=\(emojis.count)")
        
        // Convert to Realm objects
        let usersRealm = users.map { $0.toRealm() }
        let serversRealm = servers.map { $0.toRealm() }
        let channelsRealm = channels.map { $0.toRealm() }
        let membersRealm = members.map { $0.toRealm() }
        let emojisRealm = emojis.map { $0.toRealm() }
        
        // Save all in batches
        writeBatch(usersRealm)
        writeBatch(serversRealm)
        writeBatch(channelsRealm)
        writeBatch(membersRealm)
        writeBatch(emojisRealm)
        
        logger.info("✅ Ready event saved successfully")
    }
    
    // MARK: - User Operations
    
    /// Save a single user (from API or WebSocket)
    func saveUser(_ user: Types.User) {
        write(user.toRealm())
        logger.debug("✅ User saved: \(user.id)")
    }
    
    /// Save multiple users (from API or WebSocket)
    func saveUsers(_ users: [Types.User]) {
        guard !users.isEmpty else { return }
        writeBatch(users.map { $0.toRealm() })
        logger.debug("✅ Saved \(users.count) users")
    }
    
    /// Delete a user by ID
    func deleteUser(id: String) {
        deleteByPrimaryKey(UserRealm.self, key: id)
        logger.debug("✅ User deleted: \(id)")
    }
    
    // MARK: - Message Operations
    
    /// Save a single message (from API or WebSocket)
    func saveMessage(_ message: Types.Message) {
        write(message.toRealm())
        logger.debug("✅ Message saved: \(message.id)")
    }
    
    /// Save multiple messages (from API or WebSocket)
    func saveMessages(_ messages: [Types.Message]) {
        guard !messages.isEmpty else { return }
        writeBatch(messages.map { $0.toRealm() })
        logger.debug("✅ Saved \(messages.count) messages")
    }
    
    /// Delete a message by ID
    func deleteMessage(id: String) {
        deleteByPrimaryKey(MessageRealm.self, key: id)
        logger.debug("✅ Message deleted: \(id)")
    }
    
    // MARK: - Channel Operations
    
    /// Save a single channel (from API or WebSocket)
    func saveChannel(_ channel: Types.Channel) {
        write(channel.toRealm())
        logger.debug("✅ Channel saved: \(channel.id)")
    }
    
    /// Save multiple channels (from API or WebSocket)
    func saveChannels(_ channels: [Types.Channel]) {
        guard !channels.isEmpty else { return }
        writeBatch(channels.map { $0.toRealm() })
        logger.debug("✅ Saved \(channels.count) channels")
    }
    
    /// Delete a channel by ID
    func deleteChannel(id: String) {
        deleteByPrimaryKey(ChannelRealm.self, key: id)
        logger.debug("✅ Channel deleted: \(id)")
    }
    
    // MARK: - Server Operations
    
    /// Save a single server (from API or WebSocket)
    func saveServer(_ server: Types.Server) {
        write(server.toRealm())
        logger.debug("✅ Server saved: \(server.id)")
    }
    
    /// Save multiple servers (from API or WebSocket)
    func saveServers(_ servers: [Types.Server]) {
        guard !servers.isEmpty else { return }
        writeBatch(servers.map { $0.toRealm() })
        logger.debug("✅ Saved \(servers.count) servers")
    }
    
    /// Delete a server by ID
    func deleteServer(id: String) {
        deleteByPrimaryKey(ServerRealm.self, key: id)
        logger.debug("✅ Server deleted: \(id)")
    }
    
    // MARK: - Member Operations
    
    /// Save a single member (from API or WebSocket)
    func saveMember(_ member: Types.Member) {
        write(member.toRealm())
        logger.debug("✅ Member saved: \(member.id.user) in server \(member.id.server)")
    }
    
    /// Save multiple members (from API or WebSocket)
    func saveMembers(_ members: [Types.Member]) {
        guard !members.isEmpty else { return }
        writeBatch(members.map { $0.toRealm() })
        logger.debug("✅ Saved \(members.count) members")
    }
    
    // MARK: - Emoji Operations
    
    /// Save a single emoji (from API or WebSocket)
    func saveEmoji(_ emoji: Types.Emoji) {
        write(emoji.toRealm())
        logger.debug("✅ Emoji saved: \(emoji.id)")
    }
    
    /// Save multiple emojis (from API or WebSocket)
    func saveEmojis(_ emojis: [Types.Emoji]) {
        guard !emojis.isEmpty else { return }
        writeBatch(emojis.map { $0.toRealm() })
        logger.debug("✅ Saved \(emojis.count) emojis")
    }
    
    /// Delete an emoji by ID
    func deleteEmoji(id: String) {
        deleteByPrimaryKey(EmojiRealm.self, key: id)
        logger.debug("✅ Emoji deleted: \(id)")
    }
}
