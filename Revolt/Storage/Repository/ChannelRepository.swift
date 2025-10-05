//
//  ChannelRepository.swift
//  Revolt
//
//  Repository for Channel data operations
//

import Foundation
import RealmSwift
import Types
import OSLog

/// Repository for managing Channel data between Network and Realm
class ChannelRepository {
    
    // MARK: - Singleton
    
    static let shared = ChannelRepository()
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "ChannelRepository")
    private let realmManager = RealmManager.shared
    
    private init() {}
    
    // MARK: - Save Operations
    
    /// Save a single channel to Realm (from API or WebSocket)
    func saveChannel(_ channel: Types.Channel) async {
        await realmManager.write(channel.toRealm())
        logger.debug("✅ Channel saved: \(channel.id)")
    }
    
    /// Save multiple channels to Realm (from API or WebSocket)
    func saveChannels(_ channels: [Types.Channel]) async {
        guard !channels.isEmpty else { return }
        await realmManager.writeBatch(channels.map { $0.toRealm() })
        logger.debug("✅ Saved \(channels.count) channels")
    }
    
    // MARK: - Delete Operations
    
    /// Delete a channel by ID
    func deleteChannel(id: String) async {
        await realmManager.deleteByPrimaryKey(ChannelRealm.self, key: id)
        logger.debug("✅ Channel deleted: \(id)")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a channel from Realm by ID
    func fetchChannel(id: String) async -> Types.Channel? {
        guard let channelRealm = await realmManager.fetchItemByPrimaryKey(ChannelRealm.self, primaryKey: id) else {
            return nil
        }
        return channelRealm.toOriginal() as? Types.Channel
    }
    
    /// Fetch channels for a specific server
    func fetchChannels(forServer serverId: String) async -> [Types.Channel] {
        let realms = await realmManager.getListOfObjects(type: ChannelRealm.self)
        let filtered = realms.filter { channelRealm in
            if let textChannel = channelRealm.textChannel {
                return textChannel.server == serverId
            } else if let voiceChannel = channelRealm.voiceChannel {
                return voiceChannel.server == serverId
            }
            return false
        }
        return filtered.compactMap { $0.toOriginal() as? Types.Channel }
    }
    
    /// Fetch all channels from Realm
    func fetchAllChannels() async -> [Types.Channel] {
        let realms = await realmManager.getListOfObjects(type: ChannelRealm.self)
        return realms.compactMap { $0.toOriginal() as? Types.Channel }
    }
}
